const std = @import("std");
const types = @import("../../../types.zig");
const action = @import("block.zig");

pub fn block() action.Block {
    return .{
        .id = "shell_runner",
        .kind = .shell,
        .ptr = @ptrCast(@constCast(&state)),
        .runFn = run,
    };
}

fn run(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    io: std.Io,
    act: types.Action,
) types.ExecutorError!types.ActionResult {
    _ = ptr;
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "bash", "-c", act.payload },
    }) catch return types.ExecutorError.ActionFailed;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const stdout = try allocator.dupe(u8, result.stdout);
    errdefer allocator.free(stdout);
    const stderr = try allocator.dupe(u8, result.stderr);
    errdefer allocator.free(stderr);

    const exit_code: u8 = switch (result.term) {
        .exited => |c| c,
        else => 255,
    };

    return .{
        .step_index = 0,
        .kind = .shell,
        .success = exit_code == 0,
        .stdout = stdout,
        .stderr = stderr,
        .exit_code = exit_code,
    };
}

var state: u8 = 0;
