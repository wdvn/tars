const std = @import("std");
const types = @import("../../../types.zig");
const action = @import("block.zig");

/// Git action block — read-only subcommands (status, diff, log) in skeleton.
pub fn block() action.Block {
    return .{
        .id = "git_ops",
        .kind = .git,
        .ptr = @ptrCast(@constCast(&state)),
        .runFn = run,
    };
}

/// Run git with tokenized subcommand argv; success follows process exit code.
fn run(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    io: std.Io,
    act: types.Action,
) types.ExecutorError!types.ActionResult {
    _ = ptr;

    const argv = try buildArgv(allocator, act.payload);
    defer allocator.free(argv);

    const result = std.process.run(allocator, io, .{
        .argv = argv,
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
        .kind = .git,
        .success = exit_code == 0,
        .stdout = stdout,
        .stderr = stderr,
        .exit_code = exit_code,
    };
}

/// Split subcommand on spaces into git argv slice (caller owns returned slice).
fn buildArgv(allocator: std.mem.Allocator, subcommand: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer list.deinit(allocator);

    try list.append(allocator, "git");
    var iter = std.mem.tokenizeScalar(u8, subcommand, ' ');
    while (iter.next()) |tok| {
        try list.append(allocator, tok);
    }
    return list.toOwnedSlice(allocator);
}

var state: u8 = 0;
