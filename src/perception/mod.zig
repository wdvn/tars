//! Codebase perception — read files, search patterns (no LLM).

const std = @import("std");

pub const file_reader = @import("file_reader.zig");
pub const grep = @import("grep.zig");
const metrics = @import("../metrics/collector.zig");

pub const Snapshot = struct {
    path: []const u8,
    content: []const u8,
};

/// Build JSON evidence blob for Analyst ORIENT from repo root.
pub fn gatherEvidence(
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    paths: []const []const u8,
) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"files\":[");
    var first = true;

    for (paths) |rel| {
        const content = file_reader.readRelative(allocator, io, root, rel, 8192) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        defer allocator.free(content);
        metrics.gInc("perception.files.read", 1);
        metrics.gInc("perception.bytes.read", @floatFromInt(content.len));

        if (!first) try buf.appendSlice(allocator, ",");
        first = false;

        const preview = content[0..@min(content.len, 256)];
        const quoted = try jsonString(allocator, preview);
        defer allocator.free(quoted);

        const entry = try std.fmt.allocPrint(allocator,
            \\{{"path":"{s}","bytes":{d},"preview":{s}}}
        , .{ rel, content.len, quoted });
        defer allocator.free(entry);
        try buf.appendSlice(allocator, entry);
    }

    try buf.appendSlice(allocator, "]}");
    return buf.toOwnedSlice(allocator);
}

fn jsonString(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.append(allocator, '"');
    for (text) |c| {
        if (c == '"') {
            try out.appendSlice(allocator, "\\\"");
        } else if (c == '\\') {
            try out.appendSlice(allocator, "\\\\");
        } else if (c == '\n') {
            try out.appendSlice(allocator, "\\n");
        } else if (c == '\r') {
            try out.appendSlice(allocator, "\\r");
        } else if (c == '\t') {
            try out.appendSlice(allocator, "\\t");
        } else if (c < 32) {
        } else {
            try out.append(allocator, c);
        }
    }
    try out.append(allocator, '"');
    return out.toOwnedSlice(allocator);
}
