const std = @import("std");
const types = @import("../../../types.zig");
const verify = @import("block.zig");

/// Assemble Handoff summary JSON from verify check results and action count.
pub fn build(
    allocator: std.mem.Allocator,
    mission_id: []const u8,
    checks: []const verify.VerifyCheck,
    action_count: usize,
) !types.Handoff {
    var parts: std.ArrayList(u8) = .empty;
    errdefer parts.deinit(allocator);

    try parts.appendSlice(allocator, "{\"mission_id\":\"");
    try parts.appendSlice(allocator, mission_id);

    const mid = try std.fmt.allocPrint(allocator, "\",\"actions\":{d},\"checks\":[", .{action_count});
    defer allocator.free(mid);
    try parts.appendSlice(allocator, mid);

    for (checks, 0..) |c, i| {
        if (i > 0) try parts.appendSlice(allocator, ",");
        const item = try std.fmt.allocPrint(allocator, "{{\"passed\":{s},\"exit\":{d}}}", .{
            if (c.passed) "true" else "false",
            c.exit_code,
        });
        defer allocator.free(item);
        try parts.appendSlice(allocator, item);
    }

    try parts.appendSlice(allocator, "]}");

    return .{
        .summary_json = try parts.toOwnedSlice(allocator),
    };
}
