//! OpenAI-compatible chat completions provider.
//! Works with OpenAI, OpenRouter, Azure, Ollama (/v1), LM Studio, vLLM, etc.

const std = @import("std");
const llm = @import("mod.zig");
const config = @import("config.zig");
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

pub const BackendTag = enum {
    openai,
    ollama,
};

pub const OpenAiProvider = struct {
    api_key: []const u8,
    base_url: []const u8,
    api_header: []const u8,
    default_model: []const u8,
    default_max_tokens: u32,
    tag: BackendTag,
    io: std.Io,
    allocator: std.mem.Allocator,

    /// Load from OPENAI_COMPAT_* / OPENAI_* env (after dotenv).
    pub fn create(allocator: std.mem.Allocator, io: std.Io) LlmError!OpenAiProvider {
        const compat = config.loadOpenAiCompat(allocator, io, false) catch return LlmError.OutOfMemory;
        const c = compat orelse return LlmError.MissingApiKey;
        return createFromCompat(allocator, io, c, .openai);
    }

    /// Ollama local server via OpenAI-compatible API.
    pub fn createOllama(allocator: std.mem.Allocator, io: std.Io) LlmError!OpenAiProvider {
        const compat = config.loadOllamaCompat(allocator, io) catch return LlmError.OutOfMemory;
        return createFromCompat(allocator, io, compat, .ollama);
    }

    pub fn createFromCompat(
        allocator: std.mem.Allocator,
        io: std.Io,
        compat: config.OpenAiCompat,
        tag: BackendTag,
    ) LlmError!OpenAiProvider {
        var runtime = config.Config.load(allocator, io) catch config.Config{};
        defer runtime.deinit(allocator);

        return .{
            .api_key = compat.api_key,
            .base_url = compat.base_url,
            .api_header = compat.api_header,
            .default_model = compat.model,
            .default_max_tokens = runtime.max_tokens,
            .tag = tag,
            .io = io,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *OpenAiProvider) void {
        self.allocator.free(self.api_key);
        self.allocator.free(self.base_url);
        self.allocator.free(self.api_header);
        self.allocator.free(self.default_model);
    }

    pub fn provider(self: *OpenAiProvider) llm.Provider {
        return .{
            .ptr = @ptrCast(self),
            .completeFn = complete,
            .streamFn = streamComplete,
        };
    }

    fn endpoint(self: *const OpenAiProvider, allocator: std.mem.Allocator) ![]const u8 {
        if (std.mem.endsWith(u8, self.base_url, "/chat/completions")) {
            return allocator.dupe(u8, self.base_url);
        }
        const sep = if (std.mem.endsWith(u8, self.base_url, "/")) "" else "/";
        return std.fmt.allocPrint(allocator, "{s}{s}chat/completions", .{ self.base_url, sep });
    }

    fn authValue(self: *const OpenAiProvider, allocator: std.mem.Allocator) ![]const u8 {
        const key = if (self.api_key.len > 0) self.api_key else "ollama";
        if (std.mem.eql(u8, self.api_header, "Authorization")) {
            return std.fmt.allocPrint(allocator, "Bearer {s}", .{key});
        }
        return allocator.dupe(u8, key);
    }

    fn buildBody(
        self: *const OpenAiProvider,
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

        if (request.system.len > 0) {
            const sys = try json_util.escapeString(allocator, request.system);
            defer allocator.free(sys);
            try messages.appendSlice(allocator, "{\"role\":\"system\",\"content\":");
            try messages.appendSlice(allocator, sys);
            try messages.appendSlice(allocator, "}");
        }

        for (request.messages) |msg| {
            if (messages.items.len > 1) try messages.appendSlice(allocator, ",");
            const role = try json_util.escapeString(allocator, msg.role);
            defer allocator.free(role);
            const content = try json_util.escapeString(allocator, msg.content);
            defer allocator.free(content);
            try messages.appendSlice(allocator, "{\"role\":");
            try messages.appendSlice(allocator, role);
            try messages.appendSlice(allocator, ",\"content\":");
            try messages.appendSlice(allocator, content);
            try messages.appendSlice(allocator, "}");
        }
        try messages.appendSlice(allocator, "]");

        const json_mode = request.output_schema.len > 2;
        const body = try std.fmt.allocPrint(allocator,
            \\{{"model":"{s}","temperature":{d},"max_tokens":{d},"stream":{s},"messages":{s}{s}}}
        , .{
            model,
            request.config.temperature,
            max_tokens,
            if (stream) "true" else "false",
            messages.items,
            if (json_mode) ",\"response_format\":{\"type\":\"json_object\"}" else "",
        });
        messages.deinit(allocator);
        return body;
    }

    fn complete(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        request: llm.CompletionRequest,
    ) LlmError!llm.CompletionResponse {
        const self: *OpenAiProvider = @ptrCast(@alignCast(ptr));

        const url = try self.endpoint(allocator);
        defer allocator.free(url);
        const payload = try self.buildBody(allocator, request, false);
        defer allocator.free(payload);

        const auth = try self.authValue(allocator);
        defer allocator.free(auth);
        const auth_name = if (std.mem.eql(u8, self.api_header, "Authorization")) "Authorization" else self.api_header;

        const resp = try http.post(allocator, self.io, url, &.{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = auth_name, .value = auth },
        }, payload);

        if (resp.status < 200 or resp.status >= 300) {
            allocator.free(resp.body);
            return LlmError.ApiError;
        }
        defer allocator.free(resp.body);

        const owned = json_util.firstChoiceContent(allocator, resp.body) catch return LlmError.ParseError;
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
        const self: *OpenAiProvider = @ptrCast(@alignCast(ptr));
        const url = try self.endpoint(allocator);
        defer allocator.free(url);
        const payload = try self.buildBody(allocator, request, true);
        defer allocator.free(payload);

        const auth = try self.authValue(allocator);
        defer allocator.free(auth);
        const auth_name = if (std.mem.eql(u8, self.api_header, "Authorization")) "Authorization" else self.api_header;

        var acc: std.ArrayList(u8) = .empty;
        errdefer acc.deinit(allocator);

        var ctx = StreamCtx{ .allocator = allocator, .io = io, .sink = sink, .acc = &acc };
        const resp = try http.postStream(allocator, io, url, &.{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = auth_name, .value = auth },
        }, payload, @ptrCast(&ctx), onOpenAiLine);
        defer allocator.free(resp.body);

        if (resp.status < 200 or resp.status >= 300) return LlmError.ApiError;

        const content = if (acc.items.len > 0)
            try acc.toOwnedSlice(allocator)
        else blk: {
            const parsed = json_util.firstChoiceContent(allocator, resp.body) catch return LlmError.ParseError;
            break :blk parsed orelse return LlmError.ParseError;
        };

        return .{
            .content_json = content,
            .tokens_used = json_util.totalTokens(resp.body),
        };
    }
};

const StreamCtx = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    sink: stream_mod.Sink,
    acc: *std.ArrayList(u8),
};

/// Parse OpenAI SSE `data:` line — supports choices[].delta.content streaming.
fn onOpenAiLine(ctx_ptr: *anyopaque, line: []const u8) !void {
    const ctx: *StreamCtx = @ptrCast(@alignCast(ctx_ptr));
    if (!std.mem.startsWith(u8, line, "data: ")) return;
    const data = line["data: ".len..];
    if (std.mem.eql(u8, data, "[DONE]")) return;

    if (json_util.openAiStreamDelta(ctx.allocator, data)) |token| {
        defer ctx.allocator.free(token);
        if (token.len > 0) {
            const piece = try ctx.allocator.dupe(u8, token);
            try ctx.acc.appendSlice(ctx.allocator, piece);
            try ctx.sink.emit(ctx.io, .{ .kind = .token, .text = piece });
            ctx.allocator.free(piece);
        }
    } else |_| {}
}
