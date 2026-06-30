//! Plan-level rollback — Analyst `rollback` script on verify failure.

const std = @import("std");
const types = @import("../../types.zig");
const memory = @import("../../memory/mod.zig");
const policy = @import("../../policy/mod.zig");
const checkpoint = @import("checkpoint.zig");
const metrics = @import("../../metrics/collector.zig");

pub const RollbackResult = struct {
    ran: bool = false,
    success: bool = false,
    exit_code: u8 = 0,
    stdout: []const u8 = "",
    stderr: []const u8 = "",
    denied: bool = false,
};

/// Release heap fields from runPlanScript when stdout/stderr were allocated.
pub fn freeResult(allocator: std.mem.Allocator, result: *RollbackResult) void {
    if (result.stdout.len > 0) allocator.free(result.stdout);
    if (result.stderr.len > 0) allocator.free(result.stderr);
    result.stdout = "";
    result.stderr = "";
}

/// Restore completed executor step checkpoints in reverse order (best-effort).
pub fn rollbackCompletedSteps(
    allocator: std.mem.Allocator,
    io: std.Io,
    store: memory.store.Store,
    mission_id: []const u8,
    action_results: []const types.ActionResult,
    repo_root: []const u8,
) void {
    var i: isize = @intCast(action_results.len);
    while (i > 0) {
        i -= 1;
        const step_index = action_results[@intCast(i)].step_index;
        checkpoint.rollbackStep(allocator, io, store, mission_id, step_index, repo_root) catch {};
    }
}

/// Run Analyst-approved rollback shell script after verify failure (Safety Guard gated).
pub fn runPlanScript(
    allocator: std.mem.Allocator,
    io: std.Io,
    store: memory.store.Store,
    mission_id: []const u8,
    script: []const u8,
    repo_root: []const u8,
    trigger_reason: []const u8,
) !RollbackResult {
    if (script.len == 0) return .{};

    metrics.gInc("executor.plan_rollback.total", 1);

    const act = types.Action{ .kind = .shell, .payload = script };
    switch (policy.safety_guard.Guard.evaluate(act)) {
        .deny => |d| {
            metrics.gInc("executor.plan_rollback.denied", 1);
            const detail = try std.fmt.allocPrint(allocator,
                \\{{"trigger":"{s}","boundary":"{s}","reason":"{s}"}}
            , .{ trigger_reason, d.boundary, d.reason });
            defer allocator.free(detail);
            store.appendAudit(io, mission_id, "executor", "action_denied", detail, 0) catch {};
            return .{
                .ran = false,
                .denied = true,
            };
        },
        .allow => {},
    }

    const started = try std.fmt.allocPrint(allocator,
        \\{{"event":"plan_rollback","trigger":"{s}","script_len":{d}}}
    , .{ trigger_reason, script.len });
    defer allocator.free(started);
    store.appendAudit(io, mission_id, "executor", "action_started", started, 0) catch {};

    const cmd = try std.fmt.allocPrint(allocator, "cd '{s}' && {s}", .{ repo_root, script });
    defer allocator.free(cmd);

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "bash", "-c", cmd },
    }) catch {
        metrics.gInc("executor.plan_rollback.failed", 1);
        return .{ .ran = true, .success = false, .exit_code = 255 };
    };
    defer allocator.free(result.stderr);

    const exit_code: u8 = switch (result.term) {
        .exited => |c| c,
        else => 255,
    };
    const stdout = try allocator.dupe(u8, result.stdout);
    errdefer allocator.free(stdout);
    const stderr = try allocator.dupe(u8, result.stderr);
    errdefer allocator.free(stderr);
    allocator.free(result.stdout);

    const success = exit_code == 0;
    if (success) metrics.gInc("executor.plan_rollback.success", 1) else metrics.gInc("executor.plan_rollback.failed", 1);

    const done = try std.fmt.allocPrint(allocator,
        \\{{"event":"plan_rollback","success":{s},"exit":{d}}}
    , .{ if (success) "true" else "false", exit_code });
    defer allocator.free(done);
    store.appendAudit(io, mission_id, "executor", "action_completed", done, 0) catch {};

    const artifact = try std.fmt.allocPrint(allocator,
        \\{{"trigger":"{s}","success":{s},"exit":{d}}}
    , .{ trigger_reason, if (success) "true" else "false", exit_code });
    defer allocator.free(artifact);
    store.writeArtifact(
        io,
        mission_id,
        types.Phase.verify.name(),
        types.Agent.executor.name(),
        "action_result",
        artifact,
        0,
    ) catch {};

    return .{
        .ran = true,
        .success = success,
        .exit_code = exit_code,
        .stdout = stdout,
        .stderr = stderr,
    };
}
