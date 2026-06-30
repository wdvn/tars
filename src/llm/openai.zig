//! OpenAI-compatible chat completions provider.
//! Works with OpenAI, Azure OpenAI, Ollama, vLLM, etc.

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

pub const OpenAiProvider = struct {
    api_key: []const u8,
    base_url: []const u8,
    default_model: []const u8,
    io: std.Io,
    allocator: std.mem.Allocator,

    /// Load API key, base URL, and default model from env; trim trailing slash on base.
    pub fn create(allocator: std.mem.Allocator, io: std.Io) LlmError!OpenAiProvider {
        const api_key = try env.get(allocator, io, "OPENAI_API_KEY") orelse return LlmError.MissingApiKey;
        const base_raw = try env.getOr(allocator, io, "OPENAI_BASE_URL", "https://api.openai.com/v1");
        const base_url = try env.trimSlash(allocator, base_raw);
        if (!std.mem.eql(u8, base_raw, base_url)) allocator.free(base_raw);
        const default_model = try env.getOr(allocator, io, "OPENAI_MODEL", "gpt-4o-mini");

        return .{
            .api_key = api_key,
            .base_url = base_url,
            .default_model = default_model,
            .io = io,
            .allocator = allocator,
        };
    }

    /// Release heap-owned credential and endpoint strings.
    pub fn deinit(self: *OpenAiProvider) void {
        self.allocator.free(self.api_key);
        self.allocator.free(self.base_url);
        self.allocator.free(self.default_model);
    }

    /// Expose this struct through the generic llm.Provider vtable.
    pub fn provider(self: *OpenAiProvider) llm.Provider {
        return .{
            .ptr = @ptrCast(self),
            .completeFn = complete,
            .streamFn = streamComplete,
        };
    }

    /// OpenAI-compatible chat/completions URL under configurable base.
    fn endpoint(self: *const OpenAiProvider, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}/chat/completions", .{self.base_url});
    }

    /// Standard Bearer header for OpenAI and compatible proxies.
    fn authHeader(self: *const OpenAiProvider, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "Bearer {s}", .{self.api_key});
    }

    /// Hand-build JSON body: system first, then messages; enable json_object when schema set.
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
            request.config.max_tokens,
            if (stream) "true" else "false",
            messages.items,
            if (json_mode) ",\"response_format\":{\"type\":\"json_object\"}" else "",
        });
        messages.deinit(allocator);
        return body;
    }

    /// POST chat/completions, parse first choice content and token usage from response.
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
        const auth = try self.authHeader(allocator);
        defer allocator.free(auth);

        const resp = try http.post(allocator, self.io, url, &.{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Authorization", .value = auth },
        }, payload);

        if (resp.status < 200 or resp.status >= 300) {
            allocator.free(resp.body);
            return LlmError.ApiError;
        }
        defer allocator.free(resp.body);

        const content = json_util.firstChoiceContent(resp.body) catch return LlmError.ParseError;
        const text = content orelse return LlmError.ParseError;
        const owned = try allocator.dupe(u8, text);
        return .{
            .content_json = owned,
            .tokens_used = json_util.totalTokens(resp.body),
        };
    }

    /// Stream SSE lines, accumulate tokens, and mirror each chunk to the operator sink.
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
        const auth = try self.authHeader(allocator);
        defer allocator.free(auth);

        var acc: std.ArrayList(u8) = .empty;
        errdefer acc.deinit(allocator);

        var ctx = StreamCtx{ .allocator = allocator, .io = io, .sink = sink, .acc = &acc };
        const resp = try http.postStream(allocator, io, url, &.{
            .{ .name = "Content-Type", .value = "application/json" },
            .{ .name = "Authorization", .value = auth },
        }, payload, @ptrCast(&ctx), onOpenAiLine);
        defer allocator.free(resp.body);

        if (resp.status < 200 or resp.status >= 300) return LlmError.ApiError;

        const content = if (acc.items.len > 0)
            try acc.toOwnedSlice(allocator)
        else blk: {
            const parsed = json_util.firstChoiceContent(resp.body) catch return LlmError.ParseError;
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

const StreamCtx = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    sink: stream_mod.Sink,
    acc: *std.ArrayList(u8),
};

/// Parse one OpenAI SSE data line; skip [DONE] and non-data prefixes.
fn onOpenAiLine(ctx_ptr: *anyopaque, line: []const u8) !void {
    const ctx: *StreamCtx = @ptrCast(@alignCast(ctx_ptr));
    if (!std.mem.startsWith(u8, line, "data: ")) return;
    const data = line["data: ".len..];
    if (std.mem.eql(u8, data, "[DONE]")) return;

    if (json_util.extractJsonStringField(ctx.allocator, data, "content")) |token| {
        defer ctx.allocator.free(token);
        if (token.len > 0) {
            try ctx.acc.appendSlice(ctx.allocator, token);
            try ctx.sink.emit(ctx.io, .{ .kind = .token, .text = token });
        }
    } else |_| {}
}
