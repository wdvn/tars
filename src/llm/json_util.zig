//! Minimal JSON helpers for LLM request/response handling.

const std = @import("std");

/// Escape a string for embedding in hand-built JSON request bodies.
pub fn escapeString(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
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

/// Parse arbitrary JSON text into a dynamic Value tree (always allocates).
pub fn parseDynamic(allocator: std.mem.Allocator, text: []const u8) !std.json.Parsed(std.json.Value) {
    return std.json.parseFromSlice(std.json.Value, allocator, text, .{ .allocate = .alloc_always });
}

/// Narrow json.Value to string slice; null for non-string types.
pub fn valueAsString(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |s| s,
        else => null,
    };
}

/// Safe object field lookup without panicking on wrong node type.
pub fn objectGet(obj: std.json.ObjectMap, key: []const u8) ?std.json.Value {
    return obj.get(key);
}

/// Extract OpenAI chat completion message.content from choices[0].
pub fn firstChoiceContent(body: []const u8) !?[]const u8 {
    var parsed = try parseDynamic(std.heap.page_allocator, body);
    defer parsed.deinit();

    const root = parsed.value;
    const choices = objectGet(root.object, "choices") orelse return null;
    if (choices != .array or choices.array.items.len == 0) return null;

    const first = choices.array.items[0];
    const message = objectGet(first.object, "message") orelse return null;
    const content = objectGet(message.object, "content") orelse return null;
    return valueAsString(content);
}

/// Extract Anthropic text from content[0].text block.
pub fn anthropicContent(body: []const u8) !?[]const u8 {
    var parsed = try parseDynamic(std.heap.page_allocator, body);
    defer parsed.deinit();

    const content = objectGet(parsed.value.object, "content") orelse return null;
    if (content != .array or content.array.items.len == 0) return null;

    const block = content.array.items[0];
    const text = objectGet(block.object, "text") orelse return null;
    return valueAsString(text);
}

/// Sum usage tokens — supports OpenAI total_tokens or Anthropic input+output pair.
pub fn totalTokens(body: []const u8) u32 {
    var parsed = parseDynamic(std.heap.page_allocator, body) catch return 0;
    defer parsed.deinit();

    if (objectGet(parsed.value.object, "usage")) |usage| {
        if (objectGet(usage.object, "total_tokens")) |t| {
            if (t == .integer) return @intCast(@max(t.integer, 0));
        }
        if (objectGet(usage.object, "input_tokens")) |in_t| {
            if (objectGet(usage.object, "output_tokens")) |out_t| {
                if (in_t == .integer and out_t == .integer) {
                    return @intCast(@max(in_t.integer + out_t.integer, 0));
                }
            }
        }
    }
    return 0;
}

/// Reverse JSON string escapes (\\n, \\uXXXX, etc.) into raw UTF-8 bytes.
pub fn unescapeJsonString(allocator: std.mem.Allocator, raw: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '\\' and i + 1 < raw.len) {
            i += 1;
            const c = raw[i];
            switch (c) {
                'n' => try out.append(allocator, '\n'),
                'r' => try out.append(allocator, '\r'),
                't' => try out.append(allocator, '\t'),
                '"', '\\', '/' => try out.append(allocator, c),
                'u' => {
                    if (i + 4 >= raw.len) return error.InvalidJsonEscape;
                    const hex = raw[i + 1 .. i + 5];
                    const code = std.fmt.parseInt(u21, hex, 16) catch return error.InvalidJsonEscape;
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(code, &buf) catch return error.InvalidJsonEscape;
                    try out.appendSlice(allocator, buf[0..len]);
                    i += 4;
                },
                else => try out.append(allocator, c),
            }
        } else {
            try out.append(allocator, raw[i]);
        }
        i += 1;
    }
    return out.toOwnedSlice(allocator);
}

/// Extract streaming token from OpenAI chunk JSON (choices[0].delta.content).
pub fn openAiStreamDelta(allocator: std.mem.Allocator, json: []const u8) ![]const u8 {
    if (extractJsonStringField(allocator, json, "content")) |token| {
        return token;
    } else |_| {
        return extractJsonStringField(allocator, json, "reasoning_content") catch return error.FieldNotFound;
    }
}

/// Lightweight string-field extractor for streaming SSE JSON fragments (no full parse).
pub fn extractJsonStringField(allocator: std.mem.Allocator, json: []const u8, field: []const u8) ![]const u8 {
    const needle = try std.fmt.allocPrint(allocator, "\"{s}\":\"", .{field});
    defer allocator.free(needle);
    const start = std.mem.indexOf(u8, json, needle) orelse return error.FieldNotFound;
    const i = start + needle.len;
    var end = i;
    while (end < json.len) : (end += 1) {
        if (json[end] == '\\') {
            end += 1;
            continue;
        }
        if (json[end] == '"') break;
    }
    return unescapeJsonString(allocator, json[i..end]);
}

pub const InvalidJsonEscape = error{InvalidJsonEscape};
pub const FieldNotFound = error{FieldNotFound};
