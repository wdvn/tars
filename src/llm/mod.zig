//! LLM provider interface — OpenAI-compatible, Anthropic, stub.

const std = @import("std");

pub const openai = @import("openai.zig");
pub const anthropic = @import("anthropic.zig");
pub const env = @import("env.zig");

pub const Config = struct {
    model: []const u8 = "default",
    temperature: f32 = 0.2,
    max_tokens: u32 = 4096,
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const CompletionRequest = struct {
    config: Config,
    system: []const u8,
    messages: []const Message,
    /// Expected JSON schema description (honesty / structured output)
    output_schema: []const u8,
};

pub const CompletionResponse = struct {
    content_json: []const u8,
    tokens_used: u32 = 0,
};

pub const ProviderKind = enum {
    stub,
    openai,
    anthropic,
};

pub const Provider = struct {
    ptr: *anyopaque,
    completeFn: *const fn (
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        request: CompletionRequest,
    ) anyerror!CompletionResponse,
    streamFn: ?*const fn (
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        io: std.Io,
        request: CompletionRequest,
        sink: @import("../stream/mod.zig").Sink,
    ) anyerror!CompletionResponse = null,

    /// Dispatch non-stream completion to the vtable-backed provider implementation.
    pub fn complete(
        self: Provider,
        allocator: std.mem.Allocator,
        request: CompletionRequest,
    ) !CompletionResponse {
        return self.completeFn(self.ptr, allocator, request);
    }

    /// Prefer native streaming; fall back to one-shot complete + single token emit.
    pub fn completeStream(
        self: Provider,
        allocator: std.mem.Allocator,
        io: std.Io,
        request: CompletionRequest,
        sink: @import("../stream/mod.zig").Sink,
    ) !CompletionResponse {
        if (self.streamFn) |stream| {
            return stream(self.ptr, allocator, io, request, sink);
        }
        const resp = try self.complete(allocator, request);
        try sink.emit(io, .{ .kind = .token, .text = resp.content_json });
        return resp;
    }
};

/// Heap-owned provider selected from env (TARS_LLM_PROVIDER, API keys).
pub const Resolved = union(enum) {
    stub: void,
    openai: openai.OpenAiProvider,
    anthropic: anthropic.AnthropicProvider,

    /// Free provider-owned env strings (API keys, base URLs, models).
    pub fn deinit(self: *Resolved) void {
        switch (self.*) {
            .stub => {},
            .openai => |*p| p.deinit(),
            .anthropic => |*p| p.deinit(),
        }
    }

    /// Return a vtable Provider view over the resolved union variant.
    pub fn provider(self: *Resolved) Provider {
        return switch (self.*) {
            .stub => StubProvider.init(),
            .openai => |*p| p.provider(),
            .anthropic => |*p| p.provider(),
        };
    }

    /// Which backend was selected — used for metrics tags and logging.
    pub fn kind(self: *const Resolved) ProviderKind {
        return switch (self.*) {
            .stub => .stub,
            .openai => .openai,
            .anthropic => .anthropic,
        };
    }

    /// Human-readable provider tag (stub | openai | anthropic).
    pub fn kindName(self: *const Resolved) []const u8 {
        return @tagName(self.kind());
    }
};

/// Resolve provider:
/// - `TARS_LLM_PROVIDER=openai|anthropic|stub`
/// - else `ANTHROPIC_API_KEY` → anthropic
/// - else `OPENAI_API_KEY` → openai
/// - else stub
/// Explicit env wins over key heuristics so CI can force stub offline.
pub fn resolve(allocator: std.mem.Allocator, io: std.Io) !Resolved {
    if (try env.get(allocator, io, "TARS_LLM_PROVIDER")) |choice| {
        defer allocator.free(choice);
        if (std.ascii.eqlIgnoreCase(choice, "openai")) {
            return .{ .openai = try openai.OpenAiProvider.create(allocator, io) };
        }
        if (std.ascii.eqlIgnoreCase(choice, "anthropic")) {
            return .{ .anthropic = try anthropic.AnthropicProvider.create(allocator, io) };
        }
        if (std.ascii.eqlIgnoreCase(choice, "stub")) {
            return .{ .stub = {} };
        }
    }

    if (try env.isSet(allocator, io, "ANTHROPIC_API_KEY")) {
        return .{ .anthropic = try anthropic.AnthropicProvider.create(allocator, io) };
    }
    if (try env.isSet(allocator, io, "OPENAI_API_KEY")) {
        return .{ .openai = try openai.OpenAiProvider.create(allocator, io) };
    }

    return .{ .stub = {} };
}

/// Stub provider for tests and offline skeleton — returns deterministic JSON.
pub const StubProvider = struct {
    /// Build a Provider vtable pointing at static stub state (no heap allocation).
    pub fn init() Provider {
        return .{
            .ptr = @ptrCast(@constCast(&stub_state)),
            .completeFn = completeStub,
            .streamFn = streamStub,
        };
    }

    /// Return fixed JSON so tests and offline runs never hit the network.
    fn completeStub(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        request: CompletionRequest,
    ) !CompletionResponse {
        _ = ptr;
        _ = request;
        const json =
            \\{"status":"stub","note":"replace with real LLM provider"}
        ;
        return .{
            .content_json = try allocator.dupe(u8, json),
            .tokens_used = 0,
        };
    }

    /// Emit stub JSON char-by-char so stream consumers exercise the same path as live LLMs.
    fn streamStub(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        io: std.Io,
        request: CompletionRequest,
        sink: @import("../stream/mod.zig").Sink,
    ) !CompletionResponse {
        _ = ptr;
        _ = request;
        const json =
            \\{"status":"stub","note":"replace with real LLM provider"}
        ;
        for (json) |c| {
            var one: [1]u8 = .{c};
            try sink.emit(io, .{ .kind = .token, .text = one[0..] });
        }
        return .{
            .content_json = try allocator.dupe(u8, json),
            .tokens_used = @intCast(json.len),
        };
    }
};

var stub_state: u8 = 0;
