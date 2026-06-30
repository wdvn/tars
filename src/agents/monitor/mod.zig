//! Monitor Agent — VERIFY phase · audit · handoff · loop-back

const std = @import("std");
const types = @import("../../types.zig");
const memory = @import("../../memory/mod.zig");
const verify_mod = @import("verify/mod.zig");
const metrics = @import("../../metrics/collector.zig");

pub const Monitor = struct {
    store: memory.store.Store,
    io: std.Io,
    watchdog: verify_mod.block.health_watchdog.Watchdog,

    pub fn init(store: memory.store.Store, io: std.Io) Monitor {
        return .{
            .store = store,
            .io = io,
            .watchdog = .{},
        };
    }

    pub fn verify(
        self: *Monitor,
        allocator: std.mem.Allocator,
        mission_id: []const u8,
        action_results: []const types.ActionResult,
        verify_commands: []const []const u8,
    ) !types.VerifyOutcome {
        const now: i64 = 0;
        const blocks = verify_mod.block.defaultBlocks();
        const verifier = blocks[0];

        var checks: std.ArrayList(verify_mod.block.VerifyCheck) = .empty;
        errdefer freeChecks(allocator, &checks);

        for (action_results) |r| {
            if (!r.success) {
                _ = self.watchdog.recordFailure();
                metrics.gInc("monitor.watchdog.failures", 1);
                metrics.gInc("monitor.verify.fail", 1);
                const detail = try std.fmt.allocPrint(allocator, "{{\"step\":{d},\"exit\":{d}}}", .{
                    r.step_index, r.exit_code,
                });
                defer allocator.free(detail);
                try verify_mod.block.audit_writer.Writer.log(&self.store, self.io, mission_id, "verify_fail", detail, now);

                const loop = types.LoopBack{
                    .target_phase = self.watchdog.loopBackPhase(),
                    .reason = "executor action failed",
                    .detail_json = try allocator.dupe(u8, detail),
                };

                try self.publishLoopBack(mission_id, &loop, now);
                return .{ .fail = loop };
            }
        }

        for (verify_commands) |cmd| {
            metrics.gInc("monitor.verify.checks", 1);
            const check = try verifier.run(allocator, self.io, cmd);
            try checks.append(allocator, check);

            if (!check.passed) {
                _ = self.watchdog.recordFailure();
                metrics.gInc("monitor.watchdog.failures", 1);
                metrics.gInc("monitor.verify.fail", 1);
                const detail = try std.fmt.allocPrint(allocator, "{{\"command\":\"{s}\",\"exit\":{d}}}", .{
                    cmd, check.exit_code,
                });
                defer allocator.free(detail);
                try verify_mod.block.audit_writer.Writer.log(&self.store, self.io, mission_id, "verify_fail", detail, now);

                const loop = types.LoopBack{
                    .target_phase = .assess,
                    .reason = "verify command failed",
                    .detail_json = try allocator.dupe(u8, detail),
                };

                try self.publishLoopBack(mission_id, &loop, now);
                return .{ .fail = loop };
            }
        }

        self.watchdog.recordSuccess();
        metrics.gInc("monitor.verify.pass", 1);

        const handoff = try verify_mod.block.handoff_builder.build(
            allocator,
            mission_id,
            checks.items,
            action_results.len,
        );

        defer {
            for (checks.items) |c| allocator.free(c.output);
            checks.deinit(allocator);
        }

        try self.store.writeArtifact(
            self.io,
            mission_id,
            types.Phase.verify.name(),
            types.Agent.monitor.name(),
            "handoff",
            handoff.summary_json,
            now,
        );

        try verify_mod.block.audit_writer.Writer.log(
            &self.store,
            self.io,
            mission_id,
            "verify_pass",
            handoff.summary_json,
            now,
        );

        try self.store.publishBusEvent(
            self.io,
            mission_id,
            "monitor",
            "operator",
            "handoff",
            handoff.summary_json,
            now,
        );

        return .{ .pass = handoff };
    }

    fn publishLoopBack(self: *Monitor, mission_id: []const u8, loop: *const types.LoopBack, now: i64) !void {
        try self.store.publishBusEvent(
            self.io,
            mission_id,
            "monitor",
            "analyst",
            "loop_back",
            loop.detail_json,
            now,
        );
        metrics.gInc("bus.events.published", 1);
        metrics.gInc("mission.loop_back", 1);
    }

    fn freeChecks(allocator: std.mem.Allocator, list: *std.ArrayList(verify_mod.block.VerifyCheck)) void {
        for (list.items) |c| allocator.free(c.output);
        list.deinit(allocator);
    }
};
