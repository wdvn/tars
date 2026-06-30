//! MCP tool reference parsing — supports `server__tool` prefix (mini-agent style).

const std = @import("std");

pub const ToolRef = struct {
    server: ?[]const u8,
    tool: []const u8,
};

/// Split `filesystem__read` into server=filesystem, tool=read; plain name has server=null.
pub fn parse(allocator: std.mem.Allocator, raw: []const u8) !ToolRef {
    if (std.mem.indexOf(u8, raw, "__")) |sep| {
        const server = try allocator.dupe(u8, raw[0..sep]);
        const tool = try allocator.dupe(u8, raw[sep + 2 ..]);
        return .{ .server = server, .tool = tool };
    }
    return .{ .server = null, .tool = try allocator.dupe(u8, raw) };
}

pub fn deinit(allocator: std.mem.Allocator, ref: ToolRef) void {
    if (ref.server) |s| allocator.free(s);
    allocator.free(ref.tool);
}
