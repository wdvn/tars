//! Executor Agent — ACT phase · Safety Guard · Action blocks

const std = @import("std");
const types = @import("../../types.zig");
const memory = @import("../../memory/mod.zig");
const policy = @import("../../policy/mod.zig");
const action = @import("action/mod.zig");
const checkpoint = @import("checkpoint.zig");
const rollback_mod = @import("rollback.zig");
const metrics = @import("../../metrics/collector.zig");
const stream = @import("../../stream/mod.zig");

pub const Checkpoint = checkpoint;
pub const ExecuteOptions = checkpoint.ExecuteOptions;
pub const RollbackResult = rollback_mod.RollbackResult;

pub const Executor = struct {
    store: memory.store.Store,
    io: std.Io,
    guard: policy.safety_guard.Guard,

    pub fn init(store: memory.store.Store, io: std.Io) Executor {
        return .{
            .store = store,
            .io = io,
            .guard = .{},
        };
    }

    pub fn execute(
        self: *const Executor,
        allocator: std.mem.Allocator,
        plan: *const types.ApprovedPlan,
        sink: ?stream.Sink,
        opts: ExecuteOptions,
    ) !types.ExecuteOutcome {
        if (plan.steps.len == 0) return types.ExecutorError.InvalidPlan;

        var completed: std.ArrayList(types.ActionResult) = .empty;
        errdefer freeResults(allocator, &completed);

        const now: i64 = 0;

        for (plan.steps, 0..) |step, i| {
            if (i < opts.from_step) continue;

            if (opts.rollback_before_retry and i == opts.from_step) {
                checkpoint.rollbackStep(allocator, self.io, self.store, plan.mission_id, i, opts.repo_root) catch {};
                metrics.gInc("executor.retry.from_step", 1);
            }

            const act = types.Action{ .kind = step.kind, .payload = step.payload };
            metrics.gInc("executor.actions.total", 1);

            switch (policy.safety_guard.Guard.evaluate(act)) {
                .deny => |d| {
                    metrics.gInc("executor.actions.denied", 1);
                    const detail = try std.fmt.allocPrint(allocator,
                        \\{{"step":{d},"boundary":"{s}","reason":"{s}","alternative":"{s}"}}
                    , .{ i, d.boundary, d.reason, d.alternative });
                    defer allocator.free(detail);

                    try self.store.appendAudit(self.io, plan.mission_id, "executor", "action_denied", detail, now);

                    const blocked = types.BlockedAction{
                        .step_index = i,
                        .boundary = d.boundary,
                        .reason = d.reason,
                        .alternative = d.alternative,
                    };

                    try self.store.writeArtifact(
                        self.io,
                        plan.mission_id,
                        types.Phase.act.name(),
                        types.Agent.executor.name(),
                        "blocked_action",
                        detail,
                        now,
                    );

                    try self.store.publishBusEvent(
                        self.io,
                        plan.mission_id,
                        "executor",
                        "monitor",
                        "blocked",
                        detail,
                        now,
                    );

                    return .{ .blocked = .{
                        .completed = try completed.toOwnedSlice(allocator),
                        .blocked = blocked,
                    } };
                },
                .allow => {},
            }

            const backup_dir = checkpoint.prepareStep(
                allocator,
                self.io,
                self.store,
                plan.mission_id,
                i,
                step,
                opts.repo_root,
                now,
            ) catch |err| switch (err) {
                error.StorageUnavailable => return types.ExecutorError.StorageUnavailable,
                else => return types.ExecutorError.ActionFailed,
            };
            defer allocator.free(backup_dir);

            const started = try std.fmt.allocPrint(allocator, "{{\"step\":{d},\"kind\":\"{s}\",\"backup_dir\":\"{s}\"}}", .{
                i, step.kind.name(), backup_dir,
            });
            defer allocator.free(started);
            try self.store.appendAudit(self.io, plan.mission_id, "executor", "action_started", started, now);

            action.stream_sink.set(sink);
            defer action.stream_sink.set(null);

            const block = action.block.blockForKind(step.kind) orelse return types.ExecutorError.InvalidPlan;
            if (sink) |s| {
                stream.emitToolStart(self.io, s, step.kind.name(), step.payload) catch {};
            }
            const tool_start = std.Io.Clock.awake.now(self.io);
            var result = try block.run(allocator, self.io, act);
            const elapsed = tool_start.untilNow(self.io, .awake);
            const tool_duration_ms = @divTrunc(elapsed.toNanoseconds(), 1_000_000);
            if (sink) |s| {
                stream.emitToolEnd(self.io, s, step.kind.name(), result.success, result.exit_code, @intCast(tool_duration_ms)) catch {};
            }
            result.step_index = i;

            try completed.append(allocator, result);
            if (result.success) metrics.gInc("executor.actions.success", 1) else metrics.gInc("executor.actions.failed", 1);

            const result_json = try formatActionResult(allocator, &result);
            defer allocator.free(result_json);

            checkpoint.completeStep(self.io, self.store, plan.mission_id, i, result.success, result_json) catch {};

            try self.store.writeArtifact(
                self.io,
                plan.mission_id,
                types.Phase.act.name(),
                types.Agent.executor.name(),
                "action_result",
                result_json,
                now,
            );
            metrics.gInc("executor.artifacts.written", 1);

            const done_detail = try std.fmt.allocPrint(allocator, "{{\"step\":{d},\"success\":{s},\"exit\":{d},\"backup_dir\":\"{s}\"}}", .{
                i, if (result.success) "true" else "false", result.exit_code, backup_dir,
            });
            defer allocator.free(done_detail);
            try self.store.appendAudit(self.io, plan.mission_id, "executor", "action_completed", done_detail, now);

            if (!result.success) break;
        }

        const slice = try completed.toOwnedSlice(allocator);

        if (slice.len > 0) {
            const last_json = try formatActionResult(allocator, &slice[slice.len - 1]);
            defer allocator.free(last_json);
            try self.store.publishBusEvent(
                self.io,
                plan.mission_id,
                "executor",
                "monitor",
                "action_done",
                last_json,
                now,
            );
            metrics.gInc("bus.events.published", 1);
        }

        return .{ .completed = slice };
    }

    /// Roll back one step using its checkpoint (file copy / git HEAD snapshot).
    pub fn rollbackStep(
        self: *const Executor,
        allocator: std.mem.Allocator,
        mission_id: []const u8,
        step_index: usize,
        repo_root: []const u8,
    ) !void {
        try checkpoint.rollbackStep(allocator, self.io, self.store, mission_id, step_index, repo_root);
    }

    /// Re-run plan from `from_step`, optionally restoring that step's backup first.
    pub fn retryFromStep(
        self: *const Executor,
        allocator: std.mem.Allocator,
        plan: *const types.ApprovedPlan,
        sink: ?stream.Sink,
        from_step: usize,
        repo_root: []const u8,
    ) !types.ExecuteOutcome {
        return self.execute(allocator, plan, sink, .{
            .from_step = from_step,
            .rollback_before_retry = true,
            .repo_root = repo_root,
        });
    }

    /// Restore executor step checkpoints after verify failure (reverse step order).
    pub fn rollbackCompletedSteps(
        self: *const Executor,
        allocator: std.mem.Allocator,
        mission_id: []const u8,
        action_results: []const types.ActionResult,
        repo_root: []const u8,
    ) void {
        rollback_mod.rollbackCompletedSteps(allocator, self.io, self.store, mission_id, action_results, repo_root);
    }

    /// Run Analyst `plan.rollback` shell script (Safety Guard gated).
    pub fn runPlanRollback(
        self: *const Executor,
        allocator: std.mem.Allocator,
        mission_id: []const u8,
        script: []const u8,
        repo_root: []const u8,
        trigger_reason: []const u8,
    ) !RollbackResult {
        return rollback_mod.runPlanScript(allocator, self.io, self.store, mission_id, script, repo_root, trigger_reason);
    }

    fn freeResults(allocator: std.mem.Allocator, list: *std.ArrayList(types.ActionResult)) void {
        for (list.items) |*r| {
            allocator.free(r.stdout);
            allocator.free(r.stderr);
        }
        list.deinit(allocator);
    }

    fn formatActionResult(allocator: std.mem.Allocator, r: *const types.ActionResult) ![]const u8 {
        return std.fmt.allocPrint(allocator,
            \\{{"step":{d},"kind":"{s}","success":{s},"exit":{d}}}
        , .{
            r.step_index,
            r.kind.name(),
            if (r.success) "true" else "false",
            r.exit_code,
        });
    }
};

/// Release heap stdout/stderr from runPlanRollback.
pub fn freeRollbackResult(allocator: std.mem.Allocator, result: *RollbackResult) void {
    rollback_mod.freeResult(allocator, result);
}
