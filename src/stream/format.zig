//! Stream wire formats — plain CLI, SSE (text/event-stream), NDJSON (one JSON object per line).

const std = @import("std");
const stream = @import("mod.zig");

pub const Format = enum {
    plain,
    sse,
    ndjson,

    /// Parse TARS_STREAM_FORMAT env (default: plain).
    pub fn fromName(name: []const u8) Format {
        if (std.ascii.eqlIgnoreCase(name, "sse")) return .sse;
        if (std.ascii.eqlIgnoreCase(name, "ndjson")) return .ndjson;
        return .plain;
    }
};

/// Resolve operator-facing stream format from environment.
pub fn resolveFormat(allocator: std.mem.Allocator, io: std.Io) !Format {
    const llm_env = @import("../llm/env.zig");
    if (try llm_env.get(allocator, io, "TARS_STREAM_FORMAT")) |raw| {
        defer allocator.free(raw);
        return Format.fromName(raw);
    }
    return .plain;
}

/// Stable event name for SSE `event:` field and NDJSON `type` field.
pub fn eventName(kind: stream.ChunkKind) []const u8 {
    return switch (kind) {
        .token => "token",
        .phase => "phase",
        .step => "step",
        .tool_start => "tool_start",
        .tool_end => "tool_end",
        .done => "done",
        .error_msg => "error",
    };
}

/// Build one SSE frame: optional event line + data line + blank line terminator.
pub fn encodeSse(allocator: std.mem.Allocator, kind: stream.ChunkKind, text: []const u8) ![]const u8 {
    const escaped = try escapeJsonString(allocator, text);
    defer allocator.free(escaped);
    return std.fmt.allocPrint(allocator, "event: {s}\ndata: {{\"text\":{s}}}\n\n", .{
        eventName(kind),
        escaped,
    });
}

/// Build one NDJSON record: {"type":"...","text":"..."}\n
pub fn encodeNdjson(allocator: std.mem.Allocator, kind: stream.ChunkKind, text: []const u8) ![]const u8 {
    const escaped = try escapeJsonString(allocator, text);
    defer allocator.free(escaped);
    return std.fmt.allocPrint(allocator, "{{\"type\":\"{s}\",\"text\":{s}}}\n", .{
        eventName(kind),
        escaped,
    });
}

fn escapeJsonString(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    return @import("../llm/json_util.zig").escapeString(allocator, text);
}

test "Format fromName" {
    try std.testing.expectEqual(Format.plain, Format.fromName("plain"));
    try std.testing.expectEqual(Format.sse, Format.fromName("sse"));
    try std.testing.expectEqual(Format.sse, Format.fromName("SSE"));
    try std.testing.expectEqual(Format.ndjson, Format.fromName("ndjson"));
    try std.testing.expectEqual(Format.plain, Format.fromName("unknown"));
}

test "eventName mapping" {
    try std.testing.expectEqualStrings("token", eventName(.token));
    try std.testing.expectEqualStrings("phase", eventName(.phase));
    try std.testing.expectEqualStrings("done", eventName(.done));
    try std.testing.expectEqualStrings("error", eventName(.error_msg));
}

test "encodeSse and encodeNdjson" {
    const sse_frame = try encodeSse(std.testing.allocator, .token, "hello");
    defer std.testing.allocator.free(sse_frame);
    try std.testing.expect(std.mem.startsWith(u8, sse_frame, "event: token\n"));
    try std.testing.expect(std.mem.endsWith(u8, sse_frame, "\n\n"));

    const ndjson_frame = try encodeNdjson(std.testing.allocator, .phase, "orient");
    defer std.testing.allocator.free(ndjson_frame);
    try std.testing.expect(std.mem.startsWith(u8, ndjson_frame, "{\"type\":\"phase\""));
    try std.testing.expect(std.mem.endsWith(u8, ndjson_frame, "\n"));
}

