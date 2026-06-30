//! Read project files relative to repo root.

const std = @import("std");

pub const ReadError = error{
    FileNotFound,
    PathEscape,
    OutOfMemory,
    IoFailed,
};

pub fn readRelative(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    rel_path: []const u8,
    max_bytes: usize,
) ReadError![]const u8 {
    if (std.mem.indexOf(u8, rel_path, "..") != null) return ReadError.PathEscape;

    const cmd = try std.fmt.allocPrint(allocator, "head -c {d} '{s}/{s}' 2>/dev/null", .{ max_bytes, root, rel_path });
    defer allocator.free(cmd);

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "bash", "-c", cmd },
    }) catch return ReadError.IoFailed;
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code != 0) {
                allocator.free(result.stdout);
                return ReadError.FileNotFound;
            }
            return result.stdout;
        },
        else => {
            allocator.free(result.stdout);
            return ReadError.IoFailed;
        },
    }
}

pub fn listGlob(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    pattern: []const u8,
) ReadError![]const []const u8 {
    const cmd = try std.fmt.allocPrint(allocator, "cd '{s}' && find . -path './{s}' -type f 2>/dev/null | head -50", .{ root, pattern });
    defer allocator.free(cmd);

    const result = std.process.run(allocator, io, .{
        .argv = &.{ "bash", "-c", cmd },
    }) catch return ReadError.IoFailed;
    defer allocator.free(result.stderr);

    switch (result.term) {
        .exited => {},
        else => {
            allocator.free(result.stdout);
            return ReadError.IoFailed;
        },
    }

    var lines: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (lines.items) |l| allocator.free(l);
        lines.deinit(allocator);
    }

    var iter = std.mem.splitScalar(u8, result.stdout, '\n');
    while (iter.next()) |line| {
        if (line.len == 0) continue;
        const owned = allocator.dupe(u8, std.mem.trim(u8, line, " \r")) catch return ReadError.OutOfMemory;
        try lines.append(allocator, owned);
    }
    allocator.free(result.stdout);
    return lines.toOwnedSlice(allocator);
}
