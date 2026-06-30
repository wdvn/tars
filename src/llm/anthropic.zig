//! Anthropic Messages API provider.

const std = @import("std");
const llm = @import("mod.zig");
const http = @import("http.zig");
const json_util = @import("json_util.zig");
const env = @import("env.zig");
const stream_mod = @import("../stream/mod.zig");

pub const LlmError = error{
    MissingApiKey,
    ApiError,
    ParseError,
    OutOfMemory,
} || http.HttpError;

pub const AnthropicProvider = struct {
    api_key: []const u8,
    base_url: []const u8,
    default_model: []const u8,
    io: std.Io,
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, io: std.Io) LlmError!AnthropicProvider {
        const api_key = try env.get(allocator, io, "ANTHROPIC_API_KEY") orelse return LlmError.MissingApiKey;
        const base_raw = try env.getOr(allocator, io, "ANTHROPIC_BASE_URL", "https://api.anthropic.com");
        const base_url = try env.trimSlash(allocator, base_raw);
        if (!std.mem.eql(u8, base_raw, base_url)) allocator.free(base_raw);
        const default_model = try env.getOr(allocator, io, "ANTHROPIC_MODEL", "claude-sonnet-4-20250514");

        return .{
            .api_key = api_key,
            .base_url = base_url,
            .default_model = default_model,
            .io = io,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *AnthropicProvider) void {
        self.allocator.free(self.api_key);
        self.allocator.free(self.base_url);
        self.allocator.free(self.default_model);
    }

    pub fn provider(self: *AnthropicProvider) llm.Provider {
        return .{
            .ptr = @ptrCast(self),
            .completeFn = complete,
            .streamFn = streamComplete,
        };
    }

    fn endpoint(self: *const AnthropicProvider, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}/v1/messages", .{self.base_url});
    }

    fn buildBody(
        self: *const AnthropicProvider,
        allocator: std.mem.Allocator,
        request: llm.CompletionRequest,
        stream: bool,
    ) ![]const u8 {
        const model = if (request.config.model.len > 0 and !std.mem.eql(u8, request.config.model, "default"))
            request.config.model
        else
            self.default_model;

        var messages: std.ArrayList(u8) = .empty;
        errdefer messages.deinit(allocator);
        try messages.appendSlice(allocator, "[");

        for (request.messages, 0..) |msg, i| {
            if (i > 0) try messages.appendSlice(allocator, ",");
            const role = mapRole(msg.role);
            const content = try json_util.escapeString(allocator, msg.content);
            defer allocator.free(content);
            try messages.appendSlice(allocator, "{\"role\":\"");
            try messages.appendSlice(allocator, role);
            try messages.appendSlice(allocator, "\",\"content\":");
            try messages.appendSlice(allocator, content);
            try messages.appendSlice(allocator, "}");
        }
        try messages.appendSlice(allocator, "]");

        const system = if (request.system.len > 0) blk: {
            const sys = try json_util.escapeString(allocator, request.system);
            defer allocator.free(sys);
            break :blk try std.fmt.allocPrint(allocator, ",\"system\":{s}", .{sys});
        } else try allocator.dupe(u8, "");
        defer allocator.free(system);

        return std.fmt.allocPrint(allocator,
            \\{{"model":"{s}","max_tokens":{d},"stream":{s}{s},"messages":{s}}}
        , .{
            model,
            request.config.max_tokens,
            if (stream) "true" else "false",
            system,
            messages.items,
        });
    }

    fn complete(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        request: llm.CompletionRequest,
    ) LlmError!llm.CompletionResponse {
        const self: *AnthropicProvider = @ptrCast(@alignCast(ptr));

        const url = try self.endpoint(allocator);
        defer allocator.free(url);
        const payload = try self.buildBody(allocator, request, false);
        defer allocator.free(payload);

        const resp = try http.post(allocator, self.io, url, &.{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "x-api-key", .value = self.api_key },
            .{ .name = "anthropic-version", .value = "2023-06-01" },
        }, payload);

        if (resp.status < 200 or resp.status >= 300) {
            allocator.free(resp.body);
            return LlmError.ApiError;
        }
        defer allocator.free(resp.body);

        const content = json_util.anthropicContent(resp.body) catch return LlmError.ParseError;
        const text = content orelse return LlmError.ParseError;
        const owned = try allocator.dupe(u8, text);
        return .{
            .content_json = owned,
            .tokens_used = json_util.totalTokens(resp.body),
        };
    }

    fn streamComplete(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        io: std.Io,
        request: llm.CompletionRequest,
        sink: stream_mod.Sink,
    ) LlmError!llm.CompletionResponse {
        const self: *AnthropicProvider = @ptrCast(@alignCast(ptr));
        const url = try self.endpoint(allocator);
        defer allocator.free(url);
        const payload = try self.buildBody(allocator, request, true);
        defer allocator.free(payload);

        var acc: std.ArrayList(u8) = .empty;
        errdefer acc.deinit(allocator);

        var ctx = StreamCtx{ .allocator = allocator, .io = io, .sink = sink, .acc = &acc };
        const resp = try http.postStream(allocator, io, url, &.{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "x-api-key", .value = self.api_key },
            .{ .name = "anthropic-version", .value = "2023-06-01" },
        }, payload, @ptrCast(&ctx), onAnthropicLine);
        defer allocator.free(resp.body);

        if (resp.status < 200 or resp.status >= 300) return LlmError.ApiError;

        const content = if (acc.items.len > 0)
            try acc.toOwnedSlice(allocator)
        else blk: {
            const parsed = json_util.anthropicContent(resp.body) catch return LlmError.ParseError;
            break :blk parsed orelse return LlmError.ParseError;
        };

        errdefer allocator.free(content);
        const owned = try allocator.dupe(u8, content);
        allocator.free(content);
        return .{
            .content_json = owned,
            .tokens_used = json_util.totalTokens(resp.body),
        };
    }
};

fn mapRole(role: []const u8) []const u8 {
    if (std.mem.eql(u8, role, "assistant")) return "assistant";
    return "user";
}

const StreamCtx = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    sink: stream_mod.Sink,
    acc: *std.ArrayList(u8),
};

fn onAnthropicLine(ctx_ptr: *anyopaque, line: []const u8) !void {
    const ctx: *StreamCtx = @ptrCast(@alignCast(ctx_ptr));
    if (!std.mem.startsWith(u8, line, "data: ")) return;
    const data = line["data: ".len..];

    if (json_util.extractJsonStringField(ctx.allocator, data, "text")) |token| {
        defer ctx.allocator.free(token);
        if (token.len > 0) {
            try ctx.acc.appendSlice(ctx.allocator, token);
            try ctx.sink.emit(ctx.io, .{ .kind = .token, .text = token });
        }
    } else |_| {}
}
