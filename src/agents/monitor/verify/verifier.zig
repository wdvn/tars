const std = @import("std");
const vb = @import("block.zig");

pub fn block() vb.Block {
    return .{
        .id = "verifier",
        .ptr = @ptrCast(@constCast(&state)),
        .runFn = run,
    };
}

fn run(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    io: std.Io,
    command: []const u8,
) vb.MonitorError!vb.VerifyCheck {
    _ = ptr;

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "bash", "-c", command },
    }) catch return error.VerifyFailed;

    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    const output = try allocator.dupe(u8, result.stdout);

    const exit_code: u8 = switch (result.term) {
        .exited => |c| c,
        else => 255,
    };

    return .{
        .name = command,
        .passed = exit_code == 0,
        .exit_code = exit_code,
        .output = output,
    };
}

var state: u8 = 0;
