//! Mission lifecycle helpers — create mission row, write episodes after verify.

const std = @import("std");
const types = @import("../types.zig");
const memory = @import("../memory/mod.zig");
const embed = @import("../memory/embed.zig");
const metrics = @import("../metrics/collector.zig");

pub fn writeEpisodeFromOutcome(
    allocator: std.mem.Allocator,
    store: *const memory.store.Store,
    io: std.Io,
    mission_id: []const u8,
    agent: []const u8,
    content: []const u8,
    tags: []const []const u8,
) !void {
    // Embed content locally and store vector + tags inside meta JSON.
    const vec = try embed.embed(allocator, content);
    defer allocator.free(vec);
    const emb_json = try embed.serializeJson(allocator, vec);
    defer allocator.free(emb_json);

    const tags_str = try joinTags(allocator, tags);
    defer allocator.free(tags_str);
    const meta = try std.fmt.allocPrint(allocator,
        \\{{"embedding":{s},"tags":[{s}]}}
    , .{ emb_json, tags_str });
    defer allocator.free(meta);

    const now: i64 = 0;
    try store.writeEpisode(io, mission_id, agent, content, meta, now);
    metrics.gInc("memory.episodes.written", 1);
}

fn joinTags(allocator: std.mem.Allocator, tags: []const []const u8) ![]const u8 {
    // Build a JSON string array fragment for episode meta.
    var buf: std.ArrayList(u8) = .empty;
    errdefer buf.deinit(allocator);
    for (tags, 0..) |t, i| {
        if (i > 0) try buf.appendSlice(allocator, ",");
        try buf.append(allocator, '"');
        for (t) |c| {
            if (c == '"') {
                try buf.appendSlice(allocator, "\\\"");
            } else {
                try buf.append(allocator, c);
            }
        }
        try buf.append(allocator, '"');
    }
    return buf.toOwnedSlice(allocator);
}

pub fn defaultContext(mission_id: []const u8, goal: []const u8) types.MissionContext {
    return .{
        .mission_id = mission_id,
        .goal = goal,
        .phase = .orient,
        .status = .orient,
        .priority = .normal,
        .evidence = "{}",
    };
}
