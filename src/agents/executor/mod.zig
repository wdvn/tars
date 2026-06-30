//! Executor Agent — ACT phase · Safety Guard · Action blocks

const std = @import("std");
const types = @import("../../types.zig");
const memory = @import("../../memory/mod.zig");
const policy = @import("../../policy/mod.zig");
const action = @import("action/mod.zig");
const metrics = @import("../../metrics/collector.zig");

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
    ) !types.ExecuteOutcome {
        if (plan.steps.len == 0) return types.ExecutorError.InvalidPlan;

        var completed: std.ArrayList(types.ActionResult) = .empty;
        errdefer freeResults(allocator, &completed);

        const now: i64 = 0;

        for (plan.steps, 0..) |step, i| {
            const act = types.Action{ .kind = step.kind, .payload = step.payload };
            metrics.gInc("executor.actions.total", 1);

            // Safety Guard may deny before any side-effecting action runs.
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

            const started = try std.fmt.allocPrint(allocator, "{{\"step\":{d},\"kind\":\"{s}\"}}", .{
                i, step.kind.name(),
            });
            defer allocator.free(started);
            try self.store.appendAudit(self.io, plan.mission_id, "executor", "action_started", started, now);

            const block = action.block.blockForKind(step.kind) orelse return types.ExecutorError.InvalidPlan;
            var result = try block.run(allocator, self.io, act);
            result.step_index = i;

            try completed.append(allocator, result);
            if (result.success) metrics.gInc("executor.actions.success", 1) else metrics.gInc("executor.actions.failed", 1);

            const result_json = try formatActionResult(allocator, &result);
            defer allocator.free(result_json);

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

            const done_detail = try std.fmt.allocPrint(allocator, "{{\"step\":{d},\"success\":{s},\"exit\":{d}}}", .{
                i, if (result.success) "true" else "false", result.exit_code,
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
