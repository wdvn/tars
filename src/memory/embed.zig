//! Local embedding for semantic recall (384-dim, deterministic).
//! Replace with API embedding (OpenAI, etc.) in production.

const std = @import("std");

pub const dimension: u32 = 384;

pub fn embed(allocator: std.mem.Allocator, text: []const u8) ![]f32 {
    // Hash tokens into a sparse bag-of-words vector, then L2-normalize.
    var vec = try allocator.alloc(f32, dimension);
    @memset(vec, 0);

    var iter = std.mem.tokenizeAny(u8, text, " \t\n\r.,;:!?\"'()[]{}");
    while (iter.next()) |tok| {
        if (tok.len == 0) continue;
        var h = std.hash.Wyhash.hash(0, tok);
        const idx = h % dimension;
        vec[idx] += 1.0;
        h = std.hash.Wyhash.hash(h, tok);
        const idx2 = h % dimension;
        vec[idx2] += 0.5;
    }

    normalize(vec);
    return vec;
}

pub fn cosineSimilarity(a: []const f32, b: []const f32) f32 {
    // Dot product divided by product of L2 norms (0 when either vector is zero).
    const n = @min(a.len, b.len);
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
    // Minimal parser for episode meta embedding arrays stored in SQLite.
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

fn normalize(vec: []f32) void {
    // Scale vector so sum of squares equals 1 (no-op for zero vectors).
    var sum: f32 = 0;
    for (vec) |v| sum += v * v;
    if (sum == 0) return;
    const inv = 1.0 / @sqrt(sum);
    for (vec) |*v| v.* *= inv;
}
