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

pub fn recall(
    allocator: std.mem.Allocator,
    st: *const store_mod.Store,
    io: std.Io,
    query_text: []const u8,
    k: usize,
) RecallError![]Hit {
    metrics.gInc("memory.recall.queries", 1);
    const query_vec = embed.embed(allocator, query_text) catch return RecallError.OutOfMemory;
    defer allocator.free(query_vec);

    const rows_json = st.queryAllEpisodes(io) catch return RecallError.SqliteFailed;
    defer allocator.free(rows_json);

    return rankLocal(allocator, rows_json, query_vec, k);
}

fn rankLocal(allocator: std.mem.Allocator, rows_json: []const u8, query_vec: []const f32, k: usize) RecallError![]Hit {
    var hits: std.ArrayList(Hit) = .empty;
    errdefer {
        for (hits.items) |h| {
            allocator.free(h.content);
            allocator.free(h.meta_json);
        }
        hits.deinit(allocator);
    }

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

    std.sort.pdq(Hit, hits.items, {}, hitLess);

    const take = @min(k, hits.items.len);
    metrics.gInc("memory.recall.hits", @floatFromInt(take));
    if (take > 0) metrics.gGauge("memory.recall.top_score", hits.items[0].score);
    const out = allocator.alloc(Hit, take) catch return RecallError.OutOfMemory;
    for (0..take) |i| out[i] = hits.items[i];
    hits.items.len = 0;
    hits.deinit(allocator);
    return out;
}

fn hitLess(_: void, a: Hit, b: Hit) bool {
    return a.score > b.score;
}
