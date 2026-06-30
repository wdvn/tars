//! LLM runtime configuration — mini-agent compatible env names.

const std = @import("std");
const env = @import("env.zig");

/// Default local LLM via Ollama (OpenAI-compatible /v1).
pub const default_ollama_host = "http://127.0.0.1:11434";
pub const default_ollama_model = "qwen2.5:0.5b";
/// Alternative small model — set `TARS_LLM_MODEL=deepseek-r1:0.5b` to use.
pub const alt_ollama_model = "deepseek-r1:0.5b";

pub const Config = struct {
    max_tokens: u32 = 8192,
    system_prompt: []const u8 = "",
    system_prompt_owned: ?[]u8 = null,

    /// Read TARS_MAX_TOKENS / MINI_MAX_TOKENS and optional TARS_SYSTEM_FILE.
    pub fn load(allocator: std.mem.Allocator, io: std.Io) !Config {
        var cfg: Config = .{};

        if (try env.get(allocator, io, "TARS_MAX_TOKENS")) |raw| {
            defer allocator.free(raw);
            cfg.max_tokens = std.fmt.parseInt(u32, std.mem.trim(u8, raw, " \r\n"), 10) catch 8192;
        } else if (try env.get(allocator, io, "MINI_MAX_TOKENS")) |raw| {
            defer allocator.free(raw);
            cfg.max_tokens = std.fmt.parseInt(u32, std.mem.trim(u8, raw, " \r\n"), 10) catch 8192;
        }

        const sys_path = if (try env.get(allocator, io, "TARS_SYSTEM_FILE")) |p| p else blk: {
            if (try env.get(allocator, io, "MINI_SYSTEM_FILE")) |p| break :blk p else break :blk null;
        };
        if (sys_path) |path| {
            defer allocator.free(path);
            const cmd = try std.fmt.allocPrint(allocator, "test -f '{s}' && cat '{s}'", .{ path, path });
            defer allocator.free(cmd);
            const result = std.process.run(allocator, io, .{ .argv = &.{ "bash", "-c", cmd } }) catch return cfg;
            defer allocator.free(result.stderr);
            switch (result.term) {
                .exited => |code| if (code == 0 and result.stdout.len > 0) {
                    cfg.system_prompt_owned = result.stdout;
                    cfg.system_prompt = result.stdout;
                } else allocator.free(result.stdout),
                else => allocator.free(result.stdout),
            }
        }

        return cfg;
    }

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.system_prompt_owned) |buf| {
            allocator.free(buf);
            self.system_prompt_owned = null;
            self.system_prompt = "";
        }
    }
};

/// OpenAI-compatible endpoint settings (OPENAI_COMPAT_* with OPENAI_* fallback).
pub const OpenAiCompat = struct {
    base_url: []const u8,
    api_key: []const u8,
    api_header: []const u8,
    model: []const u8,
    from_ollama: bool,

    pub fn deinit(self: *OpenAiCompat, allocator: std.mem.Allocator) void {
        allocator.free(self.base_url);
        allocator.free(self.api_key);
        allocator.free(self.api_header);
        allocator.free(self.model);
    }
};

/// Resolve OpenAI-compatible backend from env (mini priority: OPENAI_COMPAT_* then OPENAI_*).
/// When `require_explicit_url` is true, an API key alone does not enable auto-detection (use Ollama default).
pub fn loadOpenAiCompat(allocator: std.mem.Allocator, io: std.Io, require_explicit_url: bool) !?OpenAiCompat {
    const url = try env.getFirst(allocator, io, &.{ "OPENAI_COMPAT_URL", "OPENAI_BASE_URL" });
    const key = try env.getFirst(allocator, io, &.{ "OPENAI_COMPAT_API_KEY", "OPENAI_API_KEY" });

    if (require_explicit_url and url == null) return null;
    if (url == null and key == null) return null;

    const base_raw = url orelse try allocator.dupe(u8, "https://api.openai.com/v1");
    defer allocator.free(base_raw);
    const base_url = try env.trimSlash(allocator, base_raw);
    errdefer allocator.free(base_url);

    const api_key = key orelse try allocator.dupe(u8, "");
    errdefer if (key == null) allocator.free(api_key);

    const header = try env.getFirst(allocator, io, &.{ "OPENAI_COMPAT_API_HEADER" }) orelse
        try allocator.dupe(u8, "Authorization");

    const model = try env.getFirst(allocator, io, &.{ "OPENAI_COMPAT_MODEL", "OPENAI_MODEL" }) orelse
        try allocator.dupe(u8, "gpt-4o-mini");

    return .{
        .base_url = base_url,
        .api_key = api_key,
        .api_header = header,
        .model = model,
        .from_ollama = false,
    };
}

/// Ollama via OpenAI-compatible /v1/chat/completions (default local LLM backend).
pub fn loadOllamaCompat(allocator: std.mem.Allocator, io: std.Io) !OpenAiCompat {
    const host_raw = try env.getOr(allocator, io, "OLLAMA_HOST", default_ollama_host);
    defer allocator.free(host_raw);
    const host = try env.trimSlash(allocator, host_raw);
    defer allocator.free(host);

    const base_url = try std.fmt.allocPrint(allocator, "{s}/v1", .{host});

    const model = if (try env.get(allocator, io, "TARS_LLM_MODEL")) |raw| blk: {
        defer allocator.free(raw);
        break :blk try allocator.dupe(u8, std.mem.trim(u8, raw, " \r\n"));
    } else if (try env.get(allocator, io, "OLLAMA_MODEL")) |raw| blk: {
        defer allocator.free(raw);
        break :blk try allocator.dupe(u8, std.mem.trim(u8, raw, " \r\n"));
    } else try allocator.dupe(u8, default_ollama_model);
    const api_key = try allocator.dupe(u8, "");
    const api_header = try allocator.dupe(u8, "Authorization");

    return .{
        .base_url = base_url,
        .api_key = api_key,
        .api_header = api_header,
        .model = model,
        .from_ollama = true,
    };
}

/// Trimmed OLLAMA_HOST for `ollama pull` / `ollama show`.
pub fn ollamaHost(allocator: std.mem.Allocator, io: std.Io) ![]const u8 {
    const host_raw = try env.getOr(allocator, io, "OLLAMA_HOST", default_ollama_host);
    defer allocator.free(host_raw);
    return env.trimSlash(allocator, host_raw);
}

/// True unless TARS_LLM_AUTO_PULL=0|false (default: auto-pull missing model).
pub fn llmAutoPullEnabled(allocator: std.mem.Allocator, io: std.Io) !bool {
    if (try env.get(allocator, io, "TARS_LLM_AUTO_PULL")) |raw| {
        defer allocator.free(raw);
        const t = std.mem.trim(u8, raw, " \r\n");
        return !std.mem.eql(u8, t, "0") and !std.mem.eql(u8, t, "false");
    }
    return true;
}

/// Anthropic Messages API settings (ANTHROPIC_* + CLAUDE_MODEL alias).
pub const AnthropicSettings = struct {
    api_key: []const u8,
    base_url: []const u8,
    model: []const u8,

    pub fn deinit(self: *AnthropicSettings, allocator: std.mem.Allocator) void {
        allocator.free(self.api_key);
        allocator.free(self.base_url);
        allocator.free(self.model);
    }
};

pub fn loadAnthropic(allocator: std.mem.Allocator, io: std.Io) !?AnthropicSettings {
    const api_key = try env.get(allocator, io, "ANTHROPIC_API_KEY") orelse return null;

    const base_raw = try env.getOr(allocator, io, "ANTHROPIC_BASE_URL", "https://api.anthropic.com");
    defer allocator.free(base_raw);
    const base_url = try env.trimSlash(allocator, base_raw);
    errdefer allocator.free(base_url);

    const model = try env.getFirst(allocator, io, &.{ "CLAUDE_MODEL", "ANTHROPIC_MODEL" }) orelse
        try allocator.dupe(u8, "claude-sonnet-4-20250514");

    return .{
        .api_key = api_key,
        .base_url = base_url,
        .model = model,
    };
}
