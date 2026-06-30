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

    while (iteration < cfg.max_iterations) : (iteration += 1) {
        metrics.gInc("mission.phase.entered", 1);
        try sink.emit(io, .{ .kind = .phase, .text = ctx.phase.name() });

        // ORIENT: perception + semantic recall → evidence
        if (ctx.phase == .orient) {
            const evidence = try perception.gatherEvidence(allocator, io, cfg.repo_root, cfg.perception_paths);
            defer allocator.free(evidence);

            const hits = recall_mod.recall(allocator, &store, io, ctx.goal, 3) catch |err| switch (err) {
                error.SqliteFailed => &[_]recall_mod.Hit{},
                else => |e| return e,
            };
            defer {
                if (hits.len > 0) {
                    for (hits) |hit| {
                        allocator.free(hit.content);
                        allocator.free(hit.meta_json);
                    }
                    allocator.free(hits);
                }
            }

            var ev_buf: std.ArrayList(u8) = .empty;
            defer ev_buf.deinit(allocator);
            try ev_buf.appendSlice(allocator, evidence);
            if (hits.len > 0) {
                try ev_buf.appendSlice(allocator, ",\"recall\":[");
                for (hits, 0..) |h, i| {
                    if (i > 0) try ev_buf.appendSlice(allocator, ",");
                    const item = try std.fmt.allocPrint(allocator, "{{\"score\":{d:.3},\"content\":{s}}}", .{
                        h.score, try jsonQuote(allocator, h.content),
                    });
                    defer allocator.free(item);
                    try ev_buf.appendSlice(allocator, item);
                }
                try ev_buf.appendSlice(allocator, "]");
            }
            ctx.evidence = try ev_buf.toOwnedSlice(allocator);
            defer allocator.free(ctx.evidence);
        }

        if (ctx.phase == .orient or ctx.phase == .assess or ctx.phase == .plan) {
            const results = try analyst_agent.runPhase(allocator, ctx);
            defer freeBlockResults(allocator, results);
        }

        if (ctx.phase == .act) {
            const outcome = try exec.execute(allocator, plan);
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

fn nextPhase(phase: types.Phase) types.Phase {
    return switch (phase) {
        .orient => .assess,
        .assess => .plan,
        .plan => .act,
        .act => .verify,
        .verify => .orient,
    };
}

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
    for (results) |r| allocator.free(r.payload_json);
    allocator.free(results);
}

fn freeExecuteOutcome(allocator: std.mem.Allocator, outcome: types.ExecuteOutcome) void {
    switch (outcome) {
        .completed => |r| freeActionResults(allocator, r),
        .blocked => |b| freeActionResults(allocator, b.completed),
    }
}

fn freeActionResults(allocator: std.mem.Allocator, results: []const types.ActionResult) void {
    for (results) |r| {
        allocator.free(r.stdout);
        allocator.free(r.stderr);
    }
    allocator.free(results);
}
