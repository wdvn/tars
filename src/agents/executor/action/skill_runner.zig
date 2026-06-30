const std = @import("std");
const types = @import("../../../types.zig");
const action = @import("block.zig");
const skills = @import("../../../skills/mod.zig");
const metrics = @import("../../../metrics/collector.zig");

/// Skill action block — list or load SKILL.md packs from TARS_SKILLS_DIR.
pub fn block() action.Block {
    return .{
        .id = "skill_runner",
        .kind = .skill,
        .ptr = @ptrCast(@constCast(&state)),
        .runFn = run,
    };
}

/// Payload: `list` | `skill_name` | `skill_name:{"context":"..."}` (context appended to output).
fn run(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    io: std.Io,
    act: types.Action,
) types.ExecutorError!types.ActionResult {
    _ = ptr;
    metrics.gInc("executor.skills.invoked", 1);

    if (std.mem.eql(u8, act.payload, "list")) {
        const listing = skills.loader.listSkills(allocator, io) catch |err| switch (err) {
            error.OutOfMemory => return types.ExecutorError.OutOfMemory,
            else => blk: {
                metrics.gInc("executor.skills.errors", 1);
                break :blk try std.fmt.allocPrint(allocator, "{{\"skills\":[],\"error\":\"{s}\"}}", .{@errorName(err)});
            },
        };
        return okResult(allocator, listing);
    }

    const parsed = parsePayload(act.payload);
    const skill_name = parsed[0];
    const extra = parsed[1];

    const body = skills.loader.loadSkill(allocator, io, skill_name) catch |err| switch (err) {
        error.OutOfMemory => return types.ExecutorError.OutOfMemory,
        else => blk: {
            metrics.gInc("executor.skills.errors", 1);
            break :blk try std.fmt.allocPrint(allocator, "{{\"skill\":\"{s}\",\"error\":\"not_found\"}}", .{skill_name});
        },
    };

    if (extra.len == 0) return okResult(allocator, body);

    const merged = std.fmt.allocPrint(allocator, "{s}\n\n--- context ---\n{s}", .{ body, extra }) catch {
        allocator.free(body);
        return types.ExecutorError.OutOfMemory;
    };
    allocator.free(body);
    return okResult(allocator, merged);
}

fn parsePayload(payload: []const u8) [2][]const u8 {
    if (std.mem.indexOfScalar(u8, payload, ':')) |colon| {
        return .{ payload[0..colon], std.mem.trim(u8, payload[colon + 1 ..], " ") };
    }
    return .{ payload, "" };
}

fn okResult(allocator: std.mem.Allocator, stdout: []const u8) types.ExecutorError!types.ActionResult {
    return .{
        .step_index = 0,
        .kind = .skill,
        .success = true,
        .stdout = stdout,
        .stderr = try allocator.dupe(u8, ""),
        .exit_code = 0,
    };
}

var state: u8 = 0;
