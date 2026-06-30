//! Embedding provider — hash fallback or Ollama (auto-pull Qwen3-Embedding, etc.).

const std = @import("std");
const hash = @import("hash.zig");
const ollama = @import("ollama.zig");
const cfg_mod = @import("config.zig");
const metrics = @import("../../metrics/collector.zig");

pub const Config = cfg_mod.Config;
pub const EmbedRole = enum { query, document };

pub const ProviderKind = enum {
    hash,
    ollama,

    pub fn name(self: ProviderKind) []const u8 {
        return @tagName(self);
    }
};

pub const Provider = struct {
    kind: ProviderKind,
    ptr: *anyopaque,
    embedFn: *const fn (
        ptr: *anyopaque,
        allocator: std.mem.Allocator,
        io: std.Io,
        text: []const u8,
        role: EmbedRole,
    ) anyerror![]f32,
    dimension: u32,

    pub fn embed(
        self: Provider,
        allocator: std.mem.Allocator,
        io: std.Io,
        text: []const u8,
        role: EmbedRole,
    ) ![]f32 {
        return self.embedFn(self.ptr, allocator, io, text, role);
    }
};

pub const Resolved = union(enum) {
    hash: void,
    ollama: ollama.OllamaEmbedder,

    pub fn deinit(_: *Resolved) void {}

    pub fn provider(self: *Resolved, output_dim: u32) Provider {
        return switch (self.*) {
            .hash => .{
                .kind = .hash,
                .ptr = @ptrCast(@constCast(&hash_state)),
                .embedFn = hashEmbedFn,
                .dimension = hash.dimension,
            },
            .ollama => |*o| .{
                .kind = .ollama,
                .ptr = @ptrCast(o),
                .embedFn = ollamaEmbedFn,
                .dimension = output_dim,
            },
        };
    }

    pub fn kind(self: *const Resolved) ProviderKind {
        return switch (self.*) {
            .hash => .hash,
            .ollama => .ollama,
        };
    }
};

var runtime: ?Resolved = null;
var runtime_config: ?Config = null;

pub fn runtimeConfig() ?*const Config {
    if (runtime_config) |*c| return c;
    return null;
}

pub fn activeProvider() ?Provider {
    if (runtime) |*r| {
        const dim = if (runtime_config) |*c| c.dimensionForProvider(c.resolvedProvider()) else hash.dimension;
        return r.provider(dim);
    }
    return null;
}

/// Load config, optionally pull model, and install global embed provider.
pub fn resolve(allocator: std.mem.Allocator, io: std.Io) !Resolved {
    if (runtime) |r| return r;

    var cfg = try Config.load(allocator, io);
    const provider_name = cfg.resolvedProvider();

    const resolved: Resolved = if (std.mem.eql(u8, provider_name, "ollama")) blk: {
        if (cfg.auto_pull and !ollama.OllamaEmbedder.modelPresent(allocator, io, cfg.ollama_host, cfg.model)) {
            try ollama.OllamaEmbedder.pullModel(allocator, io, cfg.ollama_host, cfg.model);
        }
        break :blk .{ .ollama = ollama.OllamaEmbedder.init(cfg.ollama_host, cfg.model, cfg.output_dim) };
    } else .{ .hash = {} };

    runtime = resolved;
    runtime_config = cfg;
    return resolved;
}

/// Explicitly pull embedding model (CLI: `tars embed pull`).
pub fn pullModel(allocator: std.mem.Allocator, io: std.Io) !void {
    var cfg = try Config.load(allocator, io);
    defer cfg.deinit(allocator);
    const name = cfg.resolvedProvider();
    if (!std.mem.eql(u8, name, "ollama")) return error.ProviderNotOllama;
    try ollama.OllamaEmbedder.pullModel(allocator, io, cfg.ollama_host, cfg.model);
}

pub fn deinitRuntime(allocator: std.mem.Allocator) void {
    if (runtime_config) |*c| {
        c.deinit(allocator);
        runtime_config = null;
    }
    runtime = null;
}

/// Active output dimension (512 for Ollama MRL, 384 for hash).
pub fn dimension() u32 {
    if (runtime_config) |*c| return c.dimensionForProvider(c.resolvedProvider());
    return hash.dimension;
}

/// Embed episode / document text.
pub fn embedDocument(allocator: std.mem.Allocator, io: std.Io, text: []const u8) ![]f32 {
    return embedWithRole(allocator, io, text, .document);
}

/// Embed recall query (adds instruction prefix for Ollama).
pub fn embedQuery(allocator: std.mem.Allocator, io: std.Io, text: []const u8) ![]f32 {
    return embedWithRole(allocator, io, text, .query);
}

/// Backward-compatible alias — document embedding.
pub fn embed(allocator: std.mem.Allocator, io: std.Io, text: []const u8) ![]f32 {
    return embedDocument(allocator, io, text);
}

pub fn embedWithRole(
    allocator: std.mem.Allocator,
    io: std.Io,
    text: []const u8,
    role: EmbedRole,
) ![]f32 {
    const trimmed = truncateText(text, if (runtime_config) |*c| c.max_chars else cfg_mod.default_max_chars);

    if (runtime) |*r| {
        const dim = if (runtime_config) |*c| c.dimensionForProvider(c.resolvedProvider()) else hash.dimension;
        const p = r.provider(dim);
        return p.embed(allocator, io, trimmed, role) catch {
            metrics.gInc("embed.fallback.hash", 1);
            return hash.embed(allocator, trimmed);
        };
    }

    return hash.embed(allocator, trimmed);
}

pub fn cosineSimilarity(a: []const f32, b: []const f32) f32 {
    const n = @min(a.len, b.len);
    if (n == 0) return 0;
    var dot: f32 = 0;
    var na: f32 = 0;
    var nb: f32 = 0;
    for (0..n) |i| {
        dot += a[i] * b[i];
        na += a[i] * a[i];
        nb += b[i] * b[i];
    }
    if (na == 0 or nb == 0) return 0;
    return dot / (@sqrt(na) * @sqrt(nb));
}

pub fn serializeJson(allocator: std.mem.Allocator, vec: []const f32) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    try buf.appendSlice(allocator, "[");
    for (vec, 0..) |v, i| {
        if (i > 0) try buf.appendSlice(allocator, ",");
        const num = try std.fmt.allocPrint(allocator, "{d:.6}", .{v});
        defer allocator.free(num);
        try buf.appendSlice(allocator, num);
    }
    try buf.appendSlice(allocator, "]");
    return buf.toOwnedSlice(allocator);
}

pub fn parseJson(allocator: std.mem.Allocator, json: []const u8) ![]f32 {
    var vec: std.ArrayList(f32) = .empty;
    errdefer vec.deinit(allocator);

    var i: usize = 0;
    while (i < json.len and json[i] != '[') : (i += 1) {}
    if (i >= json.len) return error.InvalidEmbedding;

    i += 1;
    while (i < json.len) {
        while (i < json.len and (json[i] == ' ' or json[i] == ',')) : (i += 1) {}
        if (i >= json.len or json[i] == ']') break;
        const start = i;
        while (i < json.len and json[i] != ',' and json[i] != ']') : (i += 1) {}
        const slice = std.mem.trim(u8, json[start..i], " ");
        const val = try std.fmt.parseFloat(f32, slice);
        try vec.append(allocator, val);
    }
    return vec.toOwnedSlice(allocator);
}

pub const PullError = error{
    ProviderNotOllama,
};

pub const InvalidEmbedding = error{InvalidEmbedding};

fn truncateText(text: []const u8, max_chars: usize) []const u8 {
    if (text.len <= max_chars) return text;
    return text[0..max_chars];
}

fn formatQueryInput(allocator: std.mem.Allocator, instruction: []const u8, text: []const u8) ![]const u8 {
    return std.fmt.allocPrint(allocator, "Instruct: {s}\nQuery: {s}", .{ instruction, text });
}

fn hashEmbedFn(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    io: std.Io,
    text: []const u8,
    role: EmbedRole,
) ![]f32 {
    _ = ptr;
    _ = io;
    _ = role;
    return hash.embed(allocator, text);
}

fn ollamaEmbedFn(
    ptr: *anyopaque,
    allocator: std.mem.Allocator,
    io: std.Io,
    text: []const u8,
    role: EmbedRole,
) ![]f32 {
    const o: *ollama.OllamaEmbedder = @ptrCast(@alignCast(ptr));

    if (role == .query) {
        const instruction = if (runtime_config) |*c| c.instruction else cfg_mod.default_instruction;
        const formatted = try formatQueryInput(allocator, instruction, text);
        defer allocator.free(formatted);
        return o.embed(allocator, io, formatted);
    }
    return o.embed(allocator, io, text);
}

var hash_state: u8 = 0;
