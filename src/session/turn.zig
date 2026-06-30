//! Session turn parsing and LLM role mapping.

const std = @import("std");
const llm = @import("../llm/mod.zig");

pub const Turn = struct {
    role: []const u8,
    content: []const u8,
};

pub const ParseError = error{
    OutOfMemory,
    InvalidJson,
};

/// Parse newline-delimited JSON rows from `loadSessionTurnsJson`.
pub fn parseTurnsJson(allocator: std.mem.Allocator, blob: []const u8) ParseError![]Turn {
    var turns: std.ArrayList(Turn) = .empty;
    errdefer freeTurns(allocator, turns.items);

    var lines = std.mem.splitScalar(u8, blob, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (trimmed.len == 0) continue;

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{ .allocate = .alloc_always }) catch return ParseError.InvalidJson;
        defer parsed.deinit();

        const obj = parsed.value.object;
        const role_val = obj.get("role") orelse return ParseError.InvalidJson;
        const content_val = obj.get("content") orelse return ParseError.InvalidJson;
        if (role_val != .string or content_val != .string) return ParseError.InvalidJson;

        const role = try allocator.dupe(u8, role_val.string);
        errdefer allocator.free(role);
        const content = try allocator.dupe(u8, content_val.string);
        errdefer allocator.free(content);

        try turns.append(allocator, .{ .role = role, .content = content });
    }

    return turns.toOwnedSlice(allocator);
}

pub fn freeTurns(allocator: std.mem.Allocator, turns: []Turn) void {
    for (turns) |t| {
        allocator.free(t.role);
        allocator.free(t.content);
    }
    allocator.free(turns);
}

/// Map persisted session role to OpenAI-compatible message role + optional prefix.
pub fn toLlmMessage(allocator: std.mem.Allocator, turn: Turn) ParseError!llm.Message {
    if (std.mem.eql(u8, turn.role, "operator")) {
        return .{ .role = "user", .content = try allocator.dupe(u8, turn.content) };
    }
    if (std.mem.eql(u8, turn.role, "analyst")) {
        return .{ .role = "assistant", .content = try allocator.dupe(u8, turn.content) };
    }
    const prefixed = try std.fmt.allocPrint(allocator, "[{s}] {s}", .{ turn.role, turn.content });
    return .{ .role = "user", .content = prefixed };
}
