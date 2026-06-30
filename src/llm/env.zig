//! Read environment variables (no libc dependency).

const std = @import("std");

pub fn get(allocator: std.mem.Allocator, io: std.Io, name: []const u8) !?[]const u8 {
    const script = try std.fmt.allocPrint(allocator, "printenv {s}", .{name});
    defer allocator.free(script);

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "bash", "-c", script },
    }) catch return null;
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| if (code != 0) {
            allocator.free(result.stdout);
            return null;
        },
        else => {
            allocator.free(result.stdout);
            return null;
        },
    }

    if (result.stdout.len == 0) {
        allocator.free(result.stdout);
        return null;
    }
    return result.stdout;
}

pub fn getOr(allocator: std.mem.Allocator, io: std.Io, name: []const u8, default: []const u8) ![]const u8 {
    if (try get(allocator, io, name)) |value| return value;
    return allocator.dupe(u8, default);
}

pub fn isSet(allocator: std.mem.Allocator, io: std.Io, name: []const u8) !bool {
    if (try get(allocator, io, name)) |value| {
        allocator.free(value);
        return true;
    }
    return false;
}

pub fn trimSlash(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    var end = url.len;
    while (end > 0 and url[end - 1] == '/') end -= 1;
    return allocator.dupe(u8, url[0..end]);
}
