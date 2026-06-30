//! Memory Controller — assemble chat LLM context (write–manage–read, P1).

const std = @import("std");
const llm = @import("../llm/mod.zig");
const llm_env = @import("../llm/env.zig");
const recall_mod = @import("recall.zig");
const embed = @import("embed/mod.zig");
const store_mod = @import("store.zig");
const session_mod = @import("../session/mod.zig");

pub const Config = struct {
    /// Raw operator/analyst turns kept in messages[] (working window K).
    raw_turns: usize = 6,
    /// Pool of recent turns considered for session recall scoring.
    session_pool: usize = 24,
    /// Top session chunks injected into system [session_recall].
    session_recall_k: usize = 3,
    /// Top episodic hits in [episodic_recall].
    episodic_recall_k: usize = 2,
    /// Max semantic scoring candidates (most recent operator turns).
    session_semantic_candidates: usize = 8,
    /// Char budget for system + messages before trim (approximate).
    max_context_chars: usize = 24_000,
    /// Fold older turns into sessions.summary when turn count exceeds this.
    summary_trigger_turns: usize = 12,
    max_summary_chars: usize = 4_000,

    pub fn load(allocator: std.mem.Allocator, io: std.Io) !Config {
        var cfg: Config = .{};
        if (try llm_env.get(allocator, io, "TARS_SESSION_RAW_TURNS")) |raw| {
            defer allocator.free(raw);
            cfg.raw_turns = std.fmt.parseInt(usize, std.mem.trim(u8, raw, " \r\n"), 10) catch cfg.raw_turns;
        }
        if (try llm_env.get(allocator, io, "TARS_SESSION_POOL")) |raw| {
            defer allocator.free(raw);
            cfg.session_pool = std.fmt.parseInt(usize, std.mem.trim(u8, raw, " \r\n"), 10) catch cfg.session_pool;
        }
        if (try llm_env.get(allocator, io, "TARS_SESSION_RECALL_K")) |raw| {
            defer allocator.free(raw);
            cfg.session_recall_k = std.fmt.parseInt(usize, std.mem.trim(u8, raw, " \r\n"), 10) catch cfg.session_recall_k;
        }
        if (try llm_env.get(allocator, io, "TARS_EPISODIC_RECALL_K")) |raw| {
            defer allocator.free(raw);
            cfg.episodic_recall_k = std.fmt.parseInt(usize, std.mem.trim(u8, raw, " \r\n"), 10) catch cfg.episodic_recall_k;
        }
        if (try llm_env.get(allocator, io, "TARS_CONTEXT_MAX_CHARS")) |raw| {
            defer allocator.free(raw);
            cfg.max_context_chars = std.fmt.parseInt(usize, std.mem.trim(u8, raw, " \r\n"), 10) catch cfg.max_context_chars;
        }
        return cfg;
    }
};

pub const ContextError = error{
    OutOfMemory,
    SqliteFailed,
};

/// Owned LLM request fields built by the memory controller.
pub const ContextPack = struct {
    system: []const u8,
    messages: []const llm.Message,

    system_owned: []const u8,
    messages_owned: []llm.Message,
    content_owned: []const []const u8,

    pub fn deinit(self: *ContextPack, allocator: std.mem.Allocator) void {
        allocator.free(self.system_owned);
        for (self.content_owned) |c| allocator.free(c);
        allocator.free(self.content_owned);
        allocator.free(self.messages_owned);
        self.* = undefined;
    }
};

const ScoredSnippet = struct {
    score: f32,
    line: []const u8,
};

/// READ path: build system blocks + working window messages for one chat turn.
pub fn assembleChatContext(
    allocator: std.mem.Allocator,
    io: std.Io,
    store: *const store_mod.Store,
    sess: *const session_mod.Session,
    query: []const u8,
    base_system: []const u8,
    cfg: Config,
) ContextError!ContextPack {
    const pool_limit = @max(cfg.session_pool, cfg.raw_turns);
    var turns = sess.loadRecentTurns(allocator, pool_limit) catch return ContextError.OutOfMemory;
    defer session_mod.turn.freeTurns(allocator, turns);

    const summary_owned = sess.summary() catch return ContextError.SqliteFailed;
    defer allocator.free(summary_owned);

    const episodic = recall_mod.recall(allocator, store, io, query, cfg.episodic_recall_k) catch |err| switch (err) {
        recall_mod.RecallError.SqliteFailed => &[_]recall_mod.Hit{},
        recall_mod.RecallError.OutOfMemory => return ContextError.OutOfMemory,
    };
    defer if (episodic.len > 0) recall_mod.freeHitsSlice(allocator, episodic);

    const raw_start = if (turns.len > cfg.raw_turns) turns.len - cfg.raw_turns else 0;
    const raw_turns = turns[raw_start..];

    var content_owned: std.ArrayList([]const u8) = .empty;
    errdefer freeContents(allocator, &content_owned);
    var messages_owned: std.ArrayList(llm.Message) = .empty;
    errdefer messages_owned.deinit(allocator);

    for (raw_turns) |t| {
        const msg = session_mod.turn.toLlmMessage(allocator, t) catch return ContextError.OutOfMemory;
        try content_owned.append(allocator, msg.content);
        try messages_owned.append(allocator, msg);
    }

    var system_parts: std.ArrayList(u8) = .empty;
    errdefer system_parts.deinit(allocator);
    try system_parts.appendSlice(allocator, base_system);

    if (summary_owned.len > 0) {
        try system_parts.appendSlice(allocator, "\n\n[session_summary]\n");
        try system_parts.appendSlice(allocator, summary_owned);
    }

    if (episodic.len > 0) {
        try system_parts.appendSlice(allocator, "\n\n[episodic_recall]\n");
        for (episodic) |h| {
            try system_parts.appendSlice(allocator, "- ");
            const snippet = h.content[0..@min(h.content.len, 240)];
            try system_parts.appendSlice(allocator, snippet);
            try system_parts.appendSlice(allocator, "\n");
        }
    }

    if (cfg.session_recall_k > 0 and raw_start > 0) {
        const older = turns[0..raw_start];
        const snippets = try scoreSessionSnippets(allocator, io, query, older, cfg);
        defer {
            for (snippets) |s| allocator.free(s.line);
            allocator.free(snippets);
        }

        if (snippets.len > 0) {
            try system_parts.appendSlice(allocator, "\n\n[session_recall]\n");
            for (snippets) |s| {
                try system_parts.appendSlice(allocator, "- ");
                try system_parts.appendSlice(allocator, s.line);
                try system_parts.appendSlice(allocator, "\n");
            }
        }
    }

    if (isFollowUpQuery(query) and turns.len >= 2) {
        const prev = turns[turns.len - 2];
        try system_parts.appendSlice(allocator, "\n\n[immediate_prior]\n");
        try system_parts.appendSlice(allocator, prev.role);
        try system_parts.appendSlice(allocator, ": ");
        const snip = prev.content[0..@min(prev.content.len, 512)];
        try system_parts.appendSlice(allocator, snip);
        try system_parts.appendSlice(allocator, "\n");
    }

    try trimToBudget(&system_parts, messages_owned.items, cfg.max_context_chars);

    const system_buf = try system_parts.toOwnedSlice(allocator);
    errdefer allocator.free(system_buf);
    system_parts.deinit(allocator);

    const msgs = try messages_owned.toOwnedSlice(allocator);
    const contents = try content_owned.toOwnedSlice(allocator);

    return .{
        .system = system_buf,
        .messages = msgs,
        .system_owned = system_buf,
        .messages_owned = msgs,
        .content_owned = contents,
    };
}

/// MANAGE path: fold turns outside the raw window into sessions.summary (no LLM).
pub fn manageSessionSummary(
    allocator: std.mem.Allocator,
    sess: *const session_mod.Session,
    cfg: Config,
) ContextError!void {
    const count = sess.turnCount() catch return ContextError.SqliteFailed;
    if (count <= cfg.summary_trigger_turns) return;

    const pool_limit = @max(count, cfg.session_pool);
    var turns = sess.loadRecentTurns(allocator, pool_limit) catch return ContextError.OutOfMemory;
    defer session_mod.turn.freeTurns(allocator, turns);

    if (turns.len <= cfg.raw_turns) return;

    const fold_end = turns.len - cfg.raw_turns;
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);

    try buf.appendSlice(allocator, "Prior conversation (compressed):\n");
    for (turns[0..fold_end]) |t| {
        if (!std.mem.eql(u8, t.role, "operator")) continue;
        try buf.appendSlice(allocator, "- ");
        const line = t.content[0..@min(t.content.len, 200)];
        try buf.appendSlice(allocator, line);
        try buf.appendSlice(allocator, "\n");
        if (buf.items.len >= cfg.max_summary_chars) break;
    }

    const summary = try buf.toOwnedSlice(allocator);
    defer allocator.free(summary);
    sess.setSummary(summary) catch return ContextError.SqliteFailed;
}

fn scoreSessionSnippets(
    allocator: std.mem.Allocator,
    io: std.Io,
    query: []const u8,
    older: []const session_mod.Turn,
    cfg: Config,
) ContextError![]ScoredSnippet {
    var scored: std.ArrayList(ScoredSnippet) = .empty;
    errdefer {
        for (scored.items) |s| allocator.free(s.line);
        scored.deinit(allocator);
    }

    const query_vec = embed.embedQuery(allocator, io, query) catch return try scored.toOwnedSlice(allocator);
    defer allocator.free(query_vec);

    const n = older.len;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const t = older[i];
        const recency: f32 = @as(f32, @floatFromInt(i + 1)) / @as(f32, @floatFromInt(n));

        var semantic: f32 = 0;
        const semantic_cutoff = if (n > cfg.session_semantic_candidates) n - cfg.session_semantic_candidates else 0;
        if (i >= semantic_cutoff) {
            const text = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ t.role, t.content[0..@min(t.content.len, 512)] });
            defer allocator.free(text);
            if (embed.embedQuery(allocator, io, text)) |vec| {
                defer allocator.free(vec);
                semantic = embed.cosineSimilarity(query_vec, vec);
            } else |_| {}
        }

        const score = 0.45 * recency + 0.55 * semantic;
        const line = try std.fmt.allocPrint(allocator, "({s}) {s}", .{
            t.role,
            t.content[0..@min(t.content.len, 280)],
        });
        try scored.append(allocator, .{ .score = score, .line = line });
    }

    std.sort.pdq(ScoredSnippet, scored.items, {}, snippetLess);
    const take = @min(cfg.session_recall_k, scored.items.len);
    const out = try allocator.alloc(ScoredSnippet, take);
    for (0..take) |j| out[j] = scored.items[j];

    for (scored.items[take..]) |s| allocator.free(s.line);
    scored.deinit(allocator);

    return out;
}

fn snippetLess(_: void, a: ScoredSnippet, b: ScoredSnippet) bool {
    return a.score > b.score;
}

fn isFollowUpQuery(query: []const u8) bool {
    const needles = [_][]const u8{
        "that",
        "this",
        "it",
        "same",
        "above",
        "my question",
        "previous",
        "earlier",
        "you said",
        "i mean",
        "websearch",
        "search for",
    };
    for (needles) |n| {
        if (containsIgnoreCase(query, n)) return true;
    }
    return false;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0 or needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i..][0..needle.len], needle)) return true;
    }
    return false;
}

fn trimToBudget(
    system: *std.ArrayList(u8),
    messages: []const llm.Message,
    max_chars: usize,
) ContextError!void {
    var total = system.items.len;
    for (messages) |m| total += m.content.len;
    if (total <= max_chars) return;

    // Drop [session_recall] block first, then trim summary, then truncate oldest raw message content.
    if (std.mem.indexOf(u8, system.items, "\n\n[session_recall]\n")) |idx| {
        system.shrinkRetainingCapacity(idx);
        total = system.items.len;
        for (messages) |m| total += m.content.len;
        if (total <= max_chars) return;
    }

    if (std.mem.indexOf(u8, system.items, "\n\n[session_summary]\n")) |idx| {
        system.shrinkRetainingCapacity(idx);
    }
}

fn freeContents(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |c| allocator.free(c);
    list.deinit(allocator);
}
