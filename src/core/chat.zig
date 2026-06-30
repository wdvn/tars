//! Operator chat turn — Memory Controller + tri-agent loop with VERIFY before reply.

const std = @import("std");
const types = @import("../types.zig");
const llm = @import("../llm/mod.zig");
const memory = @import("../memory/mod.zig");
const session_mod = @import("../session/mod.zig");
const stream = @import("../stream/mod.zig");
const perception = @import("../perception/mod.zig");
const recall_mod = @import("../memory/recall.zig");
const analyst_mod = @import("../agents/analyst/mod.zig");
const executor_mod = @import("../agents/executor/mod.zig");
const monitor_mod = @import("../agents/monitor/mod.zig");
const metrics = @import("../metrics/collector.zig");

const mission = @import("mission.zig");
const plan_parse = @import("plan_parse.zig");

pub const Config = struct {
    repo_root: []const u8 = ".",
    perception_paths: []const []const u8 = &.{ "README.md", "build.zig", "docs/vi/README.md" },
};

pub const TurnError = error{
    OutOfMemory,
    LlmFailed,
    SqliteFailed,
};

pub const TurnResult = struct {
    response: []const u8,
    verified: bool,
    /// When true, response was already streamed to the operator sink.
    streamed: bool = false,

    pub fn deinit(self: *TurnResult, allocator: std.mem.Allocator) void {
        allocator.free(self.response);
        self.* = undefined;
    }
};

const verify_instruction =
    \\Answer the operator using [verified_evidence] and memory context blocks.
    \\If evidence is present, stick strictly to the evidence and do not invent facts.
    \\If no tools were executed, answer the query naturally using conversational context or general knowledge.
;

/// Run one operator turn: assemble context → OODA loop → VERIFY → grounded reply.
pub fn runTurn(
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *memory.store.Store,
    sess: *const session_mod.Session,
    provider: llm.Provider,
    sink: stream.Sink,
    query: []const u8,
    pack: *const memory.context.ContextPack,
    cfg: Config,
) TurnError!TurnResult {
    const evidence = buildEvidence(allocator, io, store, query, pack, cfg) catch return TurnError.OutOfMemory;
    defer allocator.free(evidence);

    var ctx = mission.defaultContext(sess.id, query);
    ctx.evidence = evidence;

    var analyst = analyst_mod.Analyst.init(store.*, provider, io);
    var exec = executor_mod.Executor.init(store.*, io);
    var mon = monitor_mod.Monitor.init(store.*, io);

    const ooda = [_]types.Phase{ .orient, .assess, .plan };
    var plan_json: ?[]const u8 = null;
    defer if (plan_json) |p| allocator.free(p);

    for (ooda) |phase| {
        ctx.phase = phase;
        metrics.gInc("mission.phase.entered", 1);
        sink.emit(io, .{ .kind = .phase, .text = phase.name() }) catch {};
        const start = std.Io.Clock.awake.now(io);
        var run_err: ?anyerror = null;
        const results = analyst.runPhase(allocator, &ctx) catch |e| blk: {
            run_err = e;
            break :blk @as([]types.BlockResult, &.{});
        };
        const elapsed = start.untilNow(io, .awake);
        const duration_ms = @divTrunc(elapsed.toNanoseconds(), 1_000_000);
        const duration_text = if (run_err != null)
            std.fmt.allocPrint(allocator, " (failed in {d}ms)", .{duration_ms}) catch ""
        else
            std.fmt.allocPrint(allocator, " ({d}ms)", .{duration_ms}) catch "";
        defer if (duration_text.len > 0) allocator.free(duration_text);
        if (duration_text.len > 0) {
            sink.emit(io, .{ .kind = .token, .text = duration_text }) catch {};
        }

        if (run_err == null) {
            defer freeBlockResults(allocator, results);
            if (phase == .plan) {
                for (results) |r| {
                    if (std.mem.eql(u8, r.kind, "plan")) {
                        if (plan_json) |prev| allocator.free(prev);
                        plan_json = try allocator.dupe(u8, r.payload_json);
                    }
                }
            }
        }
    }

    var verified = false;
    var verified_block: ?[]const u8 = null;
    defer if (verified_block) |b| allocator.free(b);

    var owned_plan: ?plan_parse.OwnedPlan = null;
    if (plan_json) |pj| {
        owned_plan = plan_parse.fromPlannerJson(allocator, sess.id, pj) catch null;
    }

    if (owned_plan) |plan| {
        var op = plan;
        defer op.deinit(allocator);
        if (op.steps.len > 0) {
            metrics.gInc("mission.phase.entered", 1);
            sink.emit(io, .{ .kind = .phase, .text = "act" }) catch {};

            const approved = op.asApproved();
            const act_start = std.Io.Clock.awake.now(io);
            const outcome = exec.execute(allocator, &approved, sink, .{ .repo_root = cfg.repo_root }) catch {
                const elapsed = act_start.untilNow(io, .awake);
                const act_duration_ms = @divTrunc(elapsed.toNanoseconds(), 1_000_000);
                const duration_text = std.fmt.allocPrint(allocator, " (failed in {d}ms)", .{act_duration_ms}) catch "";
                defer if (duration_text.len > 0) allocator.free(duration_text);
                if (duration_text.len > 0) sink.emit(io, .{ .kind = .token, .text = duration_text }) catch {};

                verified_block = try std.fmt.allocPrint(allocator, "Executor failed to run plan steps.", .{});
                const synth = try synthesizeResponse(allocator, io, provider, sink, pack, query, verified_block, false);
                return .{ .response = synth.content, .verified = false, .streamed = synth.streamed };
            };
            const elapsed = act_start.untilNow(io, .awake);
            const act_duration_ms = @divTrunc(elapsed.toNanoseconds(), 1_000_000);
            const act_duration_text = std.fmt.allocPrint(allocator, " ({d}ms)", .{act_duration_ms}) catch "";
            defer if (act_duration_text.len > 0) allocator.free(act_duration_text);
            if (act_duration_text.len > 0) {
                sink.emit(io, .{ .kind = .token, .text = act_duration_text }) catch {};
            }
            defer freeExecuteOutcome(allocator, outcome);

            const action_results = switch (outcome) {
                .completed => |r| r,
                .blocked => |b| b.completed,
            };

            metrics.gInc("mission.phase.entered", 1);
            sink.emit(io, .{ .kind = .phase, .text = "verify" }) catch {};

            const verify_start = std.Io.Clock.awake.now(io);
            const verify_out = mon.verify(allocator, sess.id, action_results, &.{}) catch {
                const elapsed_verify = verify_start.untilNow(io, .awake);
                const verify_duration_ms = @divTrunc(elapsed_verify.toNanoseconds(), 1_000_000);
                const duration_text = std.fmt.allocPrint(allocator, " (failed in {d}ms)", .{verify_duration_ms}) catch "";
                defer if (duration_text.len > 0) allocator.free(duration_text);
                if (duration_text.len > 0) sink.emit(io, .{ .kind = .token, .text = duration_text }) catch {};

                verified_block = try formatActionEvidence(allocator, action_results);
                const synth = try synthesizeResponse(allocator, io, provider, sink, pack, query, verified_block, false);
                return .{ .response = synth.content, .verified = false, .streamed = synth.streamed };
            };
            const elapsed_verify = verify_start.untilNow(io, .awake);
            const verify_duration_ms = @divTrunc(elapsed_verify.toNanoseconds(), 1_000_000);
            const verify_duration_text = std.fmt.allocPrint(allocator, " ({d}ms)", .{verify_duration_ms}) catch "";
            defer if (verify_duration_text.len > 0) allocator.free(verify_duration_text);
            if (verify_duration_text.len > 0) {
                sink.emit(io, .{ .kind = .token, .text = verify_duration_text }) catch {};
            }

            switch (verify_out) {
                .pass => |h| {
                    verified = true;
                    metrics.gInc("mission.verify.pass", 1);
                    verified_block = try formatActionEvidence(allocator, action_results);
                    allocator.free(h.summary_json);
                },
                .fail => |loop| {
                    metrics.gInc("mission.verify.fail", 1);
                    verified_block = try std.fmt.allocPrint(allocator, "Verify failed: {s}\n", .{loop.reason});
                    allocator.free(loop.detail_json);
                },
            }
        }
    }

    const synth = try synthesizeResponse(allocator, io, provider, sink, pack, query, verified_block, verified);
    return .{ .response = synth.content, .verified = verified, .streamed = synth.streamed };
}

fn buildEvidence(
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *const memory.store.Store,
    query: []const u8,
    pack: *const memory.context.ContextPack,
    cfg: Config,
) ![]const u8 {
    const file_evidence = perception.gatherEvidence(allocator, io, cfg.repo_root, cfg.perception_paths) catch "{}";
    defer allocator.free(file_evidence);

    const hits = recall_mod.recall(allocator, store, io, query, 3) catch |err| switch (err) {
        error.SqliteFailed => &[_]recall_mod.Hit{},
        else => return err,
    };
    defer if (hits.len > 0) recall_mod.freeHitsSlice(allocator, hits);

    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"memory_context\":");
    const mem_json = try jsonQuote(allocator, pack.system);
    defer allocator.free(mem_json);
    try buf.appendSlice(allocator, mem_json);
    try buf.appendSlice(allocator, ",\"file_snapshot\":");
    try buf.appendSlice(allocator, file_evidence);
    try buf.appendSlice(allocator, ",\"recall\":[");
    for (hits, 0..) |h, i| {
        if (i > 0) try buf.appendSlice(allocator, ",");
        const quoted = try jsonQuote(allocator, h.content[0..@min(h.content.len, 400)]);
        defer allocator.free(quoted);
        const item = try std.fmt.allocPrint(allocator, "{{\"score\":{d:.3},\"content\":{s}}}", .{ h.score, quoted });
        defer allocator.free(item);
        try buf.appendSlice(allocator, item);
    }
    try buf.appendSlice(allocator, "]");
    try buf.appendSlice(allocator, "}");
    return buf.toOwnedSlice(allocator);
}

const SynthOutcome = struct {
    content: []const u8,
    streamed: bool,
};

fn synthesizeResponse(
    allocator: std.mem.Allocator,
    io: std.Io,
    provider: llm.Provider,
    sink: stream.Sink,
    pack: *const memory.context.ContextPack,
    query: []const u8,
    verified_block: ?[]const u8,
    verified: bool,
) TurnError!SynthOutcome {
    _ = io;
    if (verified) {
        if (verified_block) |block| {
            if (block.len > 0 and std.mem.indexOf(u8, block, "(empty stdout)") == null) {
                const text = std.fmt.allocPrint(allocator, "Verified answer (Monitor PASS):\n{s}", .{block}) catch return TurnError.OutOfMemory;
                return .{ .content = text, .streamed = false };
            }
        }
    }

    var system_parts: std.ArrayList(u8) = .empty;
    errdefer system_parts.deinit(allocator);

    // Base prompt only — strip memory blocks from pack.system for synthesis ordering.
    const mem_start = std.mem.indexOf(u8, pack.system, "\n\n[session_summary]") orelse
        std.mem.indexOf(u8, pack.system, "\n\n[episodic_recall]") orelse
        std.mem.indexOf(u8, pack.system, "\n\n[session_recall]") orelse pack.system.len;
    try system_parts.appendSlice(allocator, pack.system[0..mem_start]);

    try system_parts.appendSlice(allocator, "\n\n");
    try system_parts.appendSlice(allocator, verify_instruction);
    if (verified_block) |block| {
        try system_parts.appendSlice(allocator, "\n\n[verified_evidence]\n");
        try system_parts.appendSlice(allocator, block);
        if (verified) {
            try system_parts.appendSlice(allocator, "\n(verify: PASS — this block overrides any conflicting memory below)");
        }
    } else {
        try system_parts.appendSlice(allocator, "\n\n[verified_evidence]\n(none — no tool steps executed or verified)");
    }

    if (!verified and mem_start < pack.system.len) {
        try system_parts.appendSlice(allocator, pack.system[mem_start..]);
    }

    const system = try system_parts.toOwnedSlice(allocator);
    defer allocator.free(system);

    const max_tokens: u32 = if (llm.runtimeConfig()) |rc| rc.max_tokens else 4096;
    const user_msg = llm.Message{ .role = "user", .content = query };
    const req = llm.CompletionRequest{
        .config = .{ .max_tokens = max_tokens },
        .system = system,
        .messages = &.{user_msg},
        .output_schema = "{}",
    };

    _ = sink;
    const resp = provider.complete(allocator, req) catch return TurnError.LlmFailed;
    return .{ .content = resp.content_json, .streamed = false };
}

fn formatActionEvidence(allocator: std.mem.Allocator, results: []const types.ActionResult) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    for (results) |r| {
        const header = try std.fmt.allocPrint(allocator, "step {d} ({s}): ", .{ r.step_index, r.kind.name() });
        defer allocator.free(header);
        try buf.appendSlice(allocator, header);
        if (r.stdout.len > 0) {
            try buf.appendSlice(allocator, r.stdout[0..@min(r.stdout.len, 6000)]);
        } else {
            try buf.appendSlice(allocator, "(empty stdout)");
        }
        if (r.stderr.len > 0) {
            try buf.appendSlice(allocator, "\nstderr: ");
            try buf.appendSlice(allocator, r.stderr[0..@min(r.stderr.len, 512)]);
        }
        try buf.appendSlice(allocator, "\n\n");
    }
    return buf.toOwnedSlice(allocator);
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
        '\r' => try out.appendSlice(allocator, "\\r"),
        '\t' => try out.appendSlice(allocator, "\\t"),
        else => {
            if (c >= 32) try out.append(allocator, c);
        },
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
