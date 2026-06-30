//! Autonomous mission loop — ORIENT → … → VERIFY with loop-back.

const std = @import("std");
const types = @import("../types.zig");
const llm = @import("../llm/mod.zig");
const memory = @import("../memory/mod.zig");
const stream = @import("../stream/mod.zig");
const perception = @import("../perception/mod.zig");
const recall_mod = @import("../memory/recall.zig");
const analyst_mod = @import("../agents/analyst/mod.zig");
const executor_mod = @import("../agents/executor/mod.zig");
const monitor_mod = @import("../agents/monitor/mod.zig");
const metrics = @import("../metrics/collector.zig");

pub const mission = @import("mission.zig");
const plan_mod = @import("plan.zig");

pub const Config = struct {
    max_iterations: usize = 8,
    verify_commands: []const []const u8 = &.{},
    perception_paths: []const []const u8 = &.{ "build.zig", "src/root.zig" },
    repo_root: []const u8 = ".",
};

pub const LoopResult = struct {
    iterations: usize,
    final_status: types.MissionStatus,
    last_verify: ?types.VerifyOutcome,
};

/// Drive mission phases until verify passes, fails with loop-back, or max iterations.
pub fn runAutonomous(
    allocator: std.mem.Allocator,
    io: std.Io,
    store: memory.store.Store,
    provider: llm.Provider,
    sink: stream.Sink,
    cfg: Config,
    ctx: *types.MissionContext,
    plan: *const types.ApprovedPlan,
) !LoopResult {
    var analyst_agent = analyst_mod.Analyst.init(store, provider, io);
    var exec = executor_mod.Executor.init(store, io);
    var mon = monitor_mod.Monitor.init(store, io);

    var iteration: usize = 0;
    var last_verify: ?types.VerifyOutcome = null;
    var status = ctx.status;

    // Evidence built inside ORIENT is owned here so later phases can read it.
    var loop_evidence: ?[]u8 = null;
    defer if (loop_evidence) |e| allocator.free(e);

    var rollback_owned: ?[]u8 = null;
    defer if (rollback_owned) |r| allocator.free(r);
    var effective_rollback: []const u8 = plan.rollback;

    while (iteration < cfg.max_iterations) : (iteration += 1) {
        metrics.gInc("mission.phase.entered", 1);
        try sink.emit(io, .{ .kind = .phase, .text = ctx.phase.name() });

        // ORIENT: merge filesystem perception with semantic recall into JSON evidence.
        if (ctx.phase == .orient) {
            const evidence = try perception.gatherEvidence(allocator, io, cfg.repo_root, cfg.perception_paths);
            defer allocator.free(evidence);

            const hits = recall_mod.recall(allocator, &store, io, ctx.goal, 3) catch |err| switch (err) {
                error.SqliteFailed => &[_]recall_mod.Hit{},
                else => |e| return e,
            };
            defer if (hits.len > 0) recall_mod.freeHitsSlice(allocator, hits);

            var ev_buf: std.ArrayList(u8) = .empty;
            defer ev_buf.deinit(allocator);
            try ev_buf.appendSlice(allocator, evidence);
            if (hits.len > 0) {
                try ev_buf.appendSlice(allocator, ",\"recall\":[");
                for (hits, 0..) |h, i| {
                    if (i > 0) try ev_buf.appendSlice(allocator, ",");
                    const quoted = try jsonQuote(allocator, h.content);
                    defer allocator.free(quoted);
                    const item = try std.fmt.allocPrint(allocator, "{{\"score\":{d:.3},\"content\":{s}}}", .{
                        h.score, quoted,
                    });
                    defer allocator.free(item);
                    try ev_buf.appendSlice(allocator, item);
                }
                try ev_buf.appendSlice(allocator, "]");
            }

            // Replace prior loop-owned evidence; caller's original slice is unchanged.
            if (loop_evidence) |prev| allocator.free(prev);
            loop_evidence = try ev_buf.toOwnedSlice(allocator);
            ctx.evidence = loop_evidence.?;
        }

        // Analyst runs reasoning blocks for orient / assess / plan.
        if (ctx.phase == .orient or ctx.phase == .assess or ctx.phase == .plan) {
            const results = try analyst_agent.runPhase(allocator, ctx);
            defer freeBlockResults(allocator, results);

            if (ctx.phase == .plan) {
                const loaded = plan_mod.loadLatestRollback(allocator, store, io, ctx.mission_id) catch null;
                if (loaded) |rb| {
                    if (rollback_owned) |prev| allocator.free(prev);
                    rollback_owned = rb;
                    effective_rollback = rb;
                } else if (plan.rollback.len > 0) {
                    effective_rollback = plan.rollback;
                }
            }
        }

        // ACT → VERIFY: execute plan steps then run monitor checks.
        if (ctx.phase == .act) {
            const outcome = try exec.execute(allocator, plan, sink, .{ .repo_root = cfg.repo_root });
            defer freeExecuteOutcome(allocator, outcome);

            const action_results = switch (outcome) {
                .completed => |r| r,
                .blocked => |b| b.completed,
            };

            ctx.phase = .verify;
            ctx.status = .verify;
            status = .verify;

            const verify_out = try mon.verify(allocator, ctx.mission_id, action_results, cfg.verify_commands);
            last_verify = verify_out;

            switch (verify_out) {
                .pass => {
                    status = .done;
                    metrics.gInc("mission.verify.pass", 1);
                    metrics.gInc("mission.iterations", @floatFromInt(iteration + 1));
                    try sink.emit(io, .{ .kind = .done, .text = "mission complete" });
                    return .{ .iterations = iteration + 1, .final_status = status, .last_verify = last_verify };
                },
                .fail => |loop| {
                    metrics.gInc("mission.verify.fail", 1);

                    exec.rollbackCompletedSteps(allocator, ctx.mission_id, action_results, cfg.repo_root);

                    if (effective_rollback.len > 0) {
                        try sink.emit(io, .{ .kind = .phase, .text = "plan rollback" });
                        var rb = exec.runPlanRollback(
                            allocator,
                            ctx.mission_id,
                            effective_rollback,
                            cfg.repo_root,
                            loop.reason,
                        ) catch executor_mod.RollbackResult{};
                        defer executor_mod.freeRollbackResult(allocator, &rb);
                    }

                    ctx.phase = loop.target_phase;
                    ctx.status = switch (loop.target_phase) {
                        .orient => .orient,
                        .assess => .assess,
                        .plan => .plan,
                        .act => .act,
                        .verify => .verify,
                    };
                    status = ctx.status;
                    try sink.emit(io, .{ .kind = .phase, .text = loop.reason });
                    allocator.free(loop.detail_json);
                    continue;
                },
            }
        }

        // Advance to the next phase in the OODA cycle.
        ctx.phase = nextPhase(ctx.phase);
        ctx.status = switch (ctx.phase) {
            .orient => .orient,
            .assess => .assess,
            .plan => .plan,
            .act => .act,
            .verify => .verify,
        };
        status = ctx.status;
    }

    metrics.gInc("mission.iterations", @floatFromInt(iteration));
    return .{ .iterations = iteration, .final_status = status, .last_verify = last_verify };
}

/// Single step forward in ORIENT → ASSESS → PLAN → ACT → VERIFY → ORIENT.
fn nextPhase(phase: types.Phase) types.Phase {
    return switch (phase) {
        .orient => .assess,
        .assess => .plan,
        .plan => .act,
        .act => .verify,
        .verify => .orient,
    };
}

/// Escape a string for embedding inside JSON.
fn jsonQuote(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.append(allocator, '"');
    for (text) |c| switch (c) {
        '"', '\\' => {
            try out.append(allocator, '\\');
            try out.append(allocator, c);
        },
        '\n' => try out.appendSlice(allocator, "\\n"),
        else => try out.append(allocator, c),
    };
    try out.append(allocator, '"');
    return out.toOwnedSlice(allocator);
}

fn freeBlockResults(allocator: std.mem.Allocator, results: []types.BlockResult) void {
    // Each BlockResult owns a heap JSON payload from the LLM reasoning block.
    for (results) |r| allocator.free(r.payload_json);
    allocator.free(results);
}

fn freeExecuteOutcome(allocator: std.mem.Allocator, outcome: types.ExecuteOutcome) void {
    // Both completed and blocked paths may hold partial action stdout/stderr buffers.
    switch (outcome) {
        .completed => |r| freeActionResults(allocator, r),
        .blocked => |b| freeActionResults(allocator, b.completed),
    }
}

fn freeActionResults(allocator: std.mem.Allocator, results: []const types.ActionResult) void {
    // Shell/git/MCP runners allocate stdout and stderr per step.
    for (results) |r| {
        allocator.free(r.stdout);
        allocator.free(r.stderr);
    }
    allocator.free(results);
}
