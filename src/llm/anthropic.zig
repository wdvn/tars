//! Anthropic Messages API provider (Claude) — mini-compatible SSE streaming.

const std = @import("std");
const llm = @import("mod.zig");
const config = @import("config.zig");
const http = @import("http.zig");
const json_util = @import("json_util.zig");
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
    default_max_tokens: u32,
    io: std.Io,
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator, io: std.Io) LlmError!AnthropicProvider {
        const settings = config.loadAnthropic(allocator, io) catch return LlmError.OutOfMemory;
        const s = settings orelse return LlmError.MissingApiKey;
        var runtime = config.Config.load(allocator, io) catch config.Config{};
        defer runtime.deinit(allocator);

        return .{
            .api_key = s.api_key,
            .base_url = s.base_url,
            .default_model = s.model,
            .default_max_tokens = runtime.max_tokens,
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
        if (std.mem.endsWith(u8, self.base_url, "/v1/messages")) {
            return allocator.dupe(u8, self.base_url);
        }
        const sep = if (std.mem.endsWith(u8, self.base_url, "/")) "" else "/";
        return std.fmt.allocPrint(allocator, "{s}{s}v1/messages", .{ self.base_url, sep });
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

        const max_tokens = if (request.config.max_tokens > 0) request.config.max_tokens else self.default_max_tokens;

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
            max_tokens,
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

        const owned = json_util.anthropicContent(allocator, resp.body) catch return LlmError.ParseError;
        const text = owned orelse return LlmError.ParseError;
        return .{
            .content_json = text,
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

        var ctx = StreamCtx{
            .allocator = allocator,
            .io = io,
            .sink = sink,
            .acc = &acc,
        };
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
            const parsed = json_util.anthropicContent(allocator, resp.body) catch return LlmError.ParseError;
            break :blk parsed orelse return LlmError.ParseError;
        };

        return .{
            .content_json = content,
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
    event_type: [64]u8 = undefined,
    event_type_len: usize = 0,
};

/// Anthropic SSE: `event:` line then `data:` JSON (content_block_delta, etc.).
fn onAnthropicLine(ctx_ptr: *anyopaque, line: []const u8) !void {
    const ctx: *StreamCtx = @ptrCast(@alignCast(ctx_ptr));
    const trimmed = std.mem.trim(u8, line, " \r");

    if (std.mem.startsWith(u8, trimmed, "event: ")) {
        const ev = trimmed["event: ".len..];
        const n = @min(ev.len, ctx.event_type.len);
        @memcpy(ctx.event_type[0..n], ev[0..n]);
        ctx.event_type_len = n;
        return;
    }

    if (!std.mem.startsWith(u8, trimmed, "data: ")) return;
    const data = trimmed["data: ".len..];
    const ev = ctx.event_type[0..ctx.event_type_len];

    if (std.mem.eql(u8, ev, "content_block_delta")) {
        if (json_util.extractJsonStringField(ctx.allocator, data, "text")) |token| {
            defer ctx.allocator.free(token);
            if (token.len > 0) {
                const piece = try ctx.allocator.dupe(u8, token);
                try ctx.acc.appendSlice(ctx.allocator, piece);
                try ctx.sink.emit(ctx.io, .{ .kind = .token, .text = piece });
                ctx.allocator.free(piece);
            }
        } else |_| {}
        return;
    }

    if (json_util.extractJsonStringField(ctx.allocator, data, "text")) |token| {
        defer ctx.allocator.free(token);
        if (token.len > 0) {
            const piece = try ctx.allocator.dupe(u8, token);
            try ctx.acc.appendSlice(ctx.allocator, piece);
            try ctx.sink.emit(ctx.io, .{ .kind = .token, .text = piece });
            ctx.allocator.free(piece);
        }
    } else |_| {}
}
