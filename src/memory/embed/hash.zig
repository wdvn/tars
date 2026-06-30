//! Deterministic hash bag-of-words embedding (offline fallback).

const std = @import("std");

pub const dimension: u32 = 384;

pub fn embed(allocator: std.mem.Allocator, text: []const u8) ![]f32 {
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

fn normalize(vec: []f32) void {
    var sum: f32 = 0;
    for (vec) |v| sum += v * v;
    if (sum == 0) return;
    const inv = 1.0 / @sqrt(sum);
    for (vec) |*v| v.* *= inv;
}
