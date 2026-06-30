//! Read environment variables (no libc dependency).

const std = @import("std");

var dotenv_state: ?@import("dotenv.zig").DotEnv = null;

/// Load .env files before resolving LLM backends (idempotent).
pub fn initDotEnv(allocator: std.mem.Allocator, io: std.Io) !void {
    if (dotenv_state != null) return;
    dotenv_state = try @import("dotenv.zig").DotEnv.load(allocator, io);
}

pub fn deinitDotEnv() void {
    if (dotenv_state) |*d| {
        d.deinit();
        dotenv_state = null;
    }
}

/// Read one env var via printenv; returns owned stdout or null if unset/missing.
pub fn get(allocator: std.mem.Allocator, io: std.Io, name: []const u8) !?[]const u8 {
    if (try getFromShell(allocator, io, name)) |value| return value;
    if (dotenv_state) |*d| {
        if (d.get(name)) |val| return try allocator.dupe(u8, val);
    }
    return null;
}

fn getFromShell(allocator: std.mem.Allocator, io: std.Io, name: []const u8) !?[]const u8 {
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

/// First non-null env among candidates (mini-style aliases).
pub fn getFirst(allocator: std.mem.Allocator, io: std.Io, names: []const []const u8) !?[]const u8 {
    for (names) |name| {
        if (try get(allocator, io, name)) |value| return value;
    }
    return null;
}

/// Return env value or duplicate default when variable is absent.
pub fn getOr(allocator: std.mem.Allocator, io: std.Io, name: []const u8, default: []const u8) ![]const u8 {
    if (try get(allocator, io, name)) |value| return value;
    return allocator.dupe(u8, default);
}

/// True when printenv succeeds — used for provider auto-detection without reading secret.
pub fn isSet(allocator: std.mem.Allocator, io: std.Io, name: []const u8) !bool {
    if (try get(allocator, io, name)) |value| {
        allocator.free(value);
        return true;
    }
    return false;
}

/// Strip trailing slashes so URL concatenation does not produce double // paths.
pub fn trimSlash(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    var end = url.len;
    while (end > 0 and url[end - 1] == '/') end -= 1;
    return allocator.dupe(u8, url[0..end]);
}
