//! JSON-RPC 2.0 helpers for MCP over stdio (newline-delimited messages).

const std = @import("std");
const json_util = @import("../llm/json_util.zig");

pub const RpcError = error{
    RpcErrorResponse,
    InvalidResponse,
    OutOfMemory,
};

/// Build a single-line JSON-RPC 2.0 request (caller owns returned buffer).
pub fn buildRequest(
    allocator: std.mem.Allocator,
    id: i64,
    method: []const u8,
    params_json: []const u8,
) ![]const u8 {
    const method_esc = try json_util.escapeString(allocator, method);
    defer allocator.free(method_esc);
    return std.fmt.allocPrint(allocator, "{{\"jsonrpc\":\"2.0\",\"id\":{d},\"method\":{s},\"params\":{s}}}\n", .{
        id, method_esc, params_json,
    });
}

/// MCP initialize handshake params (protocol 2024-11-05).
pub fn initializeParams() []const u8 {
    return "{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"clientInfo\":{\"name\":\"tars\",\"version\":\"0.1.0\"}}";
}

pub fn emptyParams() []const u8 {
    return "{}";
}

/// Build tools/call params JSON with escaped tool name and raw arguments object.
pub fn toolsCallParams(allocator: std.mem.Allocator, tool_name: []const u8, args_json: []const u8) ![]const u8 {
    const name_esc = try json_util.escapeString(allocator, tool_name);
    defer allocator.free(name_esc);
    return std.fmt.allocPrint(allocator, "{{\"name\":{s},\"arguments\":{s}}}", .{ name_esc, args_json });
}

pub fn hasError(body: []const u8) bool {
    return std.mem.indexOf(u8, body, "\"error\"") != null;
}

/// Return trimmed RPC response body when no error field is present.
pub fn extractResult(allocator: std.mem.Allocator, body: []const u8) RpcError![]const u8 {
    if (hasError(body)) return RpcError.RpcErrorResponse;
    return allocator.dupe(u8, std.mem.trim(u8, body, " \r\n\t"));
}

/// Pull human-readable text from MCP tools/call result.content[] if present.
pub fn extractToolText(allocator: std.mem.Allocator, response_json: []const u8) ![]const u8 {
    var parsed = json_util.parseDynamic(allocator, response_json) catch {
        return allocator.dupe(u8, response_json);
    };
    defer parsed.deinit();

    const root = parsed.value;
    const result_val = if (root.object.get("result")) |r| r else root;

    const content = switch (result_val) {
        .object => |o| o.get("content"),
        else => null,
    } orelse {
        return allocator.dupe(u8, response_json);
    };

    switch (content) {
        .array => |arr| {
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            for (arr.items) |item| {
                if (item != .object) continue;
                if (item.object.get("text")) |t| {
                    if (t == .string) {
                        try out.appendSlice(allocator, t.string);
                        try out.appendSlice(allocator, "\n");
                    }
                }
            }
            if (out.items.len == 0) return allocator.dupe(u8, response_json);
            return out.toOwnedSlice(allocator);
        },
        else => return allocator.dupe(u8, response_json),
    }
}
