//! Semantic recall — local cosine (always) + sqlite-vector (when extension loaded).

const std = @import("std");
const embed = @import("embed.zig");
const store_mod = @import("store.zig");
const metrics = @import("../metrics/collector.zig");

pub const Hit = struct {
    id: i64,
    content: []const u8,
    score: f32,
    meta_json: []const u8,
};

pub const RecallError = error{
    SqliteFailed,
    OutOfMemory,
};

/// Query episodic memory and return top-k hits by cosine similarity.
pub fn recall(
    allocator: std.mem.Allocator,
    st: *const store_mod.Store,
    io: std.Io,
    query_text: []const u8,
    k: usize,
) RecallError![]Hit {
    metrics.gInc("memory.recall.queries", 1);

    // Embed the query text into the same vector space as stored episodes.
    const query_vec = embed.embed(allocator, query_text) catch return RecallError.OutOfMemory;
    defer allocator.free(query_vec);

    // Load all episodes that have embeddings in meta JSON.
    const rows_json = st.queryAllEpisodes(io) catch return RecallError.SqliteFailed;
    defer allocator.free(rows_json);

    return rankLocal(allocator, rows_json, query_vec, k);
}

/// Parse sqlite rows, score each episode, return top-k (caller owns Hit slices).
fn rankLocal(allocator: std.mem.Allocator, rows_json: []const u8, query_vec: []const f32, k: usize) RecallError![]Hit {
    var hits: std.ArrayList(Hit) = .empty;
    errdefer freeHitList(allocator, &hits);

    // Each line: id|content|meta|embedding_json
    var lines = std.mem.splitScalar(u8, rows_json, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, '|');
        const id_str = parts.next() orelse continue;
        const content = parts.next() orelse continue;
        const meta = parts.next() orelse "{}";
        const emb_json = parts.next() orelse continue;

        const id = std.fmt.parseInt(i64, id_str, 10) catch continue;
        const emb_vec = embed.parseJson(allocator, emb_json) catch continue;
        defer allocator.free(emb_vec);

        const score = embed.cosineSimilarity(query_vec, emb_vec);

        // Own content/meta so hits survive after rows_json is freed.
        const content_owned = allocator.dupe(u8, content) catch continue;
        errdefer allocator.free(content_owned);
        const meta_owned = allocator.dupe(u8, meta) catch {
            allocator.free(content_owned);
            continue;
        };

        try hits.append(allocator, .{
            .id = id,
            .content = content_owned,
            .score = score,
            .meta_json = meta_owned,
        });
    }

    // Highest similarity first.
    std.sort.pdq(Hit, hits.items, {}, hitLess);

    const take = @min(k, hits.items.len);
    metrics.gInc("memory.recall.hits", @floatFromInt(take));
    if (take > 0) metrics.gGauge("memory.recall.top_score", hits.items[0].score);

    const out = allocator.alloc(Hit, take) catch return RecallError.OutOfMemory;
    for (0..take) |i| out[i] = hits.items[i];

    // Drop episodes that did not make top-k — they are not returned to the caller.
    for (hits.items[take..]) |h| {
        allocator.free(h.content);
        allocator.free(h.meta_json);
    }
    hits.deinit(allocator);

    return out;
}

/// Release content and meta owned by each Hit (slice elements only, not the slice itself).
pub fn freeHits(allocator: std.mem.Allocator, hits: []const Hit) void {
    for (hits) |h| {
        allocator.free(h.content);
        allocator.free(h.meta_json);
    }
}

/// Free Hit payloads then the slice returned by recall().
pub fn freeHitsSlice(allocator: std.mem.Allocator, hits: []const Hit) void {
    freeHits(allocator, hits);
    allocator.free(hits);
}

/// Roll back a partial rankLocal on error — free all hits and destroy the list.
fn freeHitList(allocator: std.mem.Allocator, list: *std.ArrayList(Hit)) void {
    for (list.items) |h| {
        allocator.free(h.content);
        allocator.free(h.meta_json);
    }
    list.deinit(allocator);
}

/// Sort comparator: higher cosine score ranks first.
fn hitLess(_: void, a: Hit, b: Hit) bool {
    return a.score > b.score;
}
