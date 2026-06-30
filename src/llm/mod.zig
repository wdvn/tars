//! LLM provider interface — OpenAI-compatible, Anthropic, Ollama, stub.

const std = @import("std");

pub const openai = @import("openai.zig");
pub const anthropic = @import("anthropic.zig");
pub const env = @import("env.zig");
pub const config = @import("config.zig");

pub const Config = struct {
    model: []const u8 = "default",
    temperature: f32 = 0.2,
    max_tokens: u32 = 0,
};

pub const Message = struct {
    role: []const u8,
    content: []const u8,
};

pub const CompletionRequest = struct {
    config: Config,
    system: []const u8,
    messages: []const Message,
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
    ollama,
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

    pub fn complete(
        self: Provider,
        allocator: std.mem.Allocator,
        request: CompletionRequest,
    ) !CompletionResponse {
        return self.completeFn(self.ptr, allocator, request);
    }

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

/// Heap-owned provider — mini-agent resolution order after dotenv load.
pub const Resolved = union(enum) {
    stub: void,
    openai: openai.OpenAiProvider,
    ollama: openai.OpenAiProvider,
    anthropic: anthropic.AnthropicProvider,

    pub fn deinit(self: *Resolved) void {
        switch (self.*) {
            .stub => {},
            .openai => |*p| p.deinit(),
            .ollama => |*p| p.deinit(),
            .anthropic => |*p| p.deinit(),
        }
    }

    pub fn provider(self: *Resolved) Provider {
        return switch (self.*) {
            .stub => StubProvider.init(),
            .openai => |*p| p.provider(),
            .ollama => |*p| p.provider(),
            .anthropic => |*p| p.provider(),
        };
    }

    pub fn kind(self: *const Resolved) ProviderKind {
        return switch (self.*) {
            .stub => .stub,
            .openai => .openai,
            .ollama => .ollama,
            .anthropic => .anthropic,
        };
    }

    pub fn kindName(self: *const Resolved) []const u8 {
        return @tagName(self.kind());
    }
};

/// Global runtime config loaded once per resolve (max_tokens, system file).
var runtime_config: ?config.Config = null;

pub fn runtimeConfig() ?*const config.Config {
    if (runtime_config) |*c| return c;
    return null;
}

/// Resolve backend (mini priority):
/// 1. TARS_LLM_PROVIDER override
/// 2. Ollama local (default qwen2.5:0.5b, auto-pull)
/// 3. OPENAI_COMPAT_URL / OPENAI_BASE_URL (explicit endpoint)
/// 4. ANTHROPIC_API_KEY
/// 5. stub
pub fn resolve(allocator: std.mem.Allocator, io: std.Io) !Resolved {
    try env.initDotEnv(allocator, io);
    errdefer env.deinitDotEnv();

    runtime_config = try config.Config.load(allocator, io);

    if (try env.get(allocator, io, "TARS_LLM_PROVIDER")) |choice_raw| {
        defer allocator.free(choice_raw);
        const choice = std.mem.trim(u8, choice_raw, " \r\n");
        if (std.ascii.eqlIgnoreCase(choice, "openai")) {
            return .{ .openai = try openai.OpenAiProvider.create(allocator, io) };
        }
        if (std.ascii.eqlIgnoreCase(choice, "anthropic") or std.ascii.eqlIgnoreCase(choice, "claude")) {
            return .{ .anthropic = try anthropic.AnthropicProvider.create(allocator, io) };
        }
        if (std.ascii.eqlIgnoreCase(choice, "ollama")) {
            return try resolveOllama(allocator, io);
        }
        if (std.ascii.eqlIgnoreCase(choice, "stub")) {
            return .{ .stub = {} };
        }
    }

    return try resolveOllama(allocator, io);
}

fn resolveOllama(allocator: std.mem.Allocator, io: std.Io) !Resolved {
    const ollama_util = @import("../memory/embed/ollama.zig");
    var compat = try config.loadOllamaCompat(allocator, io);
    errdefer compat.deinit(allocator);

    if (try config.llmAutoPullEnabled(allocator, io)) {
        const host = try config.ollamaHost(allocator, io);
        defer allocator.free(host);
        if (!ollama_util.OllamaEmbedder.modelPresent(allocator, io, host, compat.model)) {
            ollama_util.OllamaEmbedder.pullModel(allocator, io, host, compat.model) catch {};
        }
    }

    return .{ .ollama = try openai.OpenAiProvider.createFromCompat(allocator, io, compat, .ollama) };
}

pub fn deinitRuntime(allocator: std.mem.Allocator) void {
    if (runtime_config) |*c| {
        c.deinit(allocator);
        runtime_config = null;
    }
    env.deinitDotEnv();
}

pub const StubProvider = struct {
    pub fn init() Provider {
        return .{
            .ptr = @ptrCast(@constCast(&stub_state)),
            .completeFn = completeStub,
            .streamFn = streamStub,
        };
    }

    fn completeStub(
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        request: CompletionRequest,
    ) !CompletionResponse {
        _ = ptr;
        const json = if (std.mem.indexOf(u8, request.output_schema, "rollback") != null)
            \\{"steps":["echo stub-plan-step"],"rollback":"echo analyst-plan-rollback","contingencies":["re-run verify"]}
        else
            \\{"status":"stub","note":"set TARS_LLM_PROVIDER=ollama or OPENAI_COMPAT_URL / ANTHROPIC_API_KEY"}
        ;
        return .{
            .content_json = try allocator.dupe(u8, json),
            .tokens_used = @intCast(json.len),
        };
    }

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
            \\{"status":"stub","note":"set TARS_LLM_PROVIDER=ollama or OPENAI_COMPAT_URL / ANTHROPIC_API_KEY"}
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
