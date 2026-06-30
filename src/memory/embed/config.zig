//! Embedding runtime configuration from env.

const std = @import("std");
const llm_env = @import("../../llm/env.zig");

pub const default_provider = "ollama";
pub const default_model = "qwen3-embedding:0.6b";
pub const default_host = "http://127.0.0.1:11434";
pub const default_dim: u32 = 512;
pub const default_instruction =
    \\Given a TARS mission goal and agent run context, retrieve relevant episodic memories from past missions.
;
pub const default_max_chars: usize = 8192;

pub const Config = struct {
    provider: []const u8,
    model: []const u8,
    output_dim: u32,
    instruction: []const u8,
    max_chars: usize,
    auto_pull: bool,
    ollama_host: []const u8,

    provider_owned: ?[]const u8 = null,
    model_owned: ?[]const u8 = null,
    instruction_owned: ?[]const u8 = null,
    host_owned: ?[]const u8 = null,

    pub fn load(allocator: std.mem.Allocator, io: std.Io) !Config {
        try llm_env.initDotEnv(allocator, io);

        var cfg: Config = .{
            .provider = default_provider,
            .model = default_model,
            .output_dim = default_dim,
            .instruction = default_instruction,
            .max_chars = default_max_chars,
            .auto_pull = true,
            .ollama_host = default_host,
        };

        if (try llm_env.get(allocator, io, "TARS_EMBED_PROVIDER")) |raw| {
            defer allocator.free(raw);
            cfg.provider_owned = try allocator.dupe(u8, std.mem.trim(u8, raw, " \r\n"));
            cfg.provider = cfg.provider_owned.?;
        }

        if (try llm_env.get(allocator, io, "TARS_EMBED_MODEL")) |raw| {
            defer allocator.free(raw);
            cfg.model_owned = try allocator.dupe(u8, std.mem.trim(u8, raw, " \r\n"));
            cfg.model = cfg.model_owned.?;
        } else if (try llm_env.get(allocator, io, "OLLAMA_EMBED_MODEL")) |raw| {
            defer allocator.free(raw);
            cfg.model_owned = try allocator.dupe(u8, std.mem.trim(u8, raw, " \r\n"));
            cfg.model = cfg.model_owned.?;
        }

        if (try llm_env.get(allocator, io, "TARS_EMBED_DIM")) |raw| {
            defer allocator.free(raw);
            cfg.output_dim = std.fmt.parseInt(u32, std.mem.trim(u8, raw, " \r\n"), 10) catch default_dim;
        }

        if (try llm_env.get(allocator, io, "TARS_EMBED_INSTRUCTION")) |raw| {
            defer allocator.free(raw);
            cfg.instruction_owned = try allocator.dupe(u8, std.mem.trim(u8, raw, " \r\n"));
            cfg.instruction = cfg.instruction_owned.?;
        }

        if (try llm_env.get(allocator, io, "TARS_EMBED_MAX_CHARS")) |raw| {
            defer allocator.free(raw);
            cfg.max_chars = std.fmt.parseInt(usize, std.mem.trim(u8, raw, " \r\n"), 10) catch default_max_chars;
        }

        if (try llm_env.get(allocator, io, "TARS_EMBED_AUTO_PULL")) |raw| {
            defer allocator.free(raw);
            const t = std.mem.trim(u8, raw, " \r\n");
            cfg.auto_pull = !std.mem.eql(u8, t, "0") and !std.mem.eql(u8, t, "false");
        }

        const host_raw = try llm_env.getOr(allocator, io, "OLLAMA_HOST", default_host);
        defer allocator.free(host_raw);
        cfg.host_owned = try llm_env.trimSlash(allocator, host_raw);
        cfg.ollama_host = cfg.host_owned.?;

        return cfg;
    }

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.provider_owned) |b| allocator.free(b);
        if (self.model_owned) |b| allocator.free(b);
        if (self.instruction_owned) |b| allocator.free(b);
        if (self.host_owned) |b| allocator.free(b);
        self.* = undefined;
    }

    pub fn resolvedProvider(self: *const Config) []const u8 {
        if (std.mem.eql(u8, self.provider, "auto")) {
            if (self.model_owned != null) return "ollama";
            return default_provider;
        }
        return self.provider;
    }

    pub fn dimensionForProvider(self: *const Config, provider: []const u8) u32 {
        if (std.mem.eql(u8, provider, "hash")) return hash.dimension;
        return self.output_dim;
    }
};

const hash = @import("hash.zig");
