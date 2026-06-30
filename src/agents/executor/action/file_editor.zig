const std = @import("std");
const types = @import("../../../types.zig");
const action = @import("block.zig");

/// File edit block — skeleton records path intent without applying patches yet.
pub fn block() action.Block {
    return .{
        .id = "file_editor",
        .kind = .file_edit,
        .ptr = @ptrCast(@constCast(&state)),
        .runFn = run,
    };
}

/// Return stub JSON acknowledging path — real patch application not implemented.
fn run(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    io: std.Io,
    act: types.Action,
) types.ExecutorError!types.ActionResult {
    _ = ptr;
    _ = io;
    const msg = try std.fmt.allocPrint(allocator, "{{\"path\":\"{s}\",\"status\":\"stub_not_applied\"}}", .{act.payload});
    return .{
        .step_index = 0,
        .kind = .file_edit,
        .success = true,
        .stdout = msg,
        .stderr = try allocator.dupe(u8, ""),
        .exit_code = 0,
    };
}

var state: u8 = 0;
