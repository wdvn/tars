//! Persist metrics collector snapshot to SQLite.

const std = @import("std");
const collector = @import("collector.zig");
const registry = @import("registry.zig");
const store_mod = @import("../memory/store.zig");

pub fn flush(m: *const collector.Metrics, st: *const store_mod.Store, io: std.Io) !void {
    // Write one metric_runs row then fan out all in-memory counter buckets.
    const finished_at: i64 = 0;
    try st.beginMetricRun(io, m.run_id, m.command, m.started_at, m.meta_json);

    var it = m.totals.iterator();
    while (it.next()) |entry| {
        const parts = splitKey(entry.key_ptr.*);
        const def = registry.find(parts.metric) orelse continue;
        try st.writeMetricSample(io, m.run_id, parts.metric, entry.value_ptr.*, def.unit.name(), parts.tags, finished_at);
    }

    try st.finishMetricRun(io, m.run_id, finished_at);
}

fn splitKey(key: []const u8) struct { metric: []const u8, tags: []const u8 } {
    if (std.mem.indexOfScalar(u8, key, '|')) |n| {
        return .{ .metric = key[0..n], .tags = key[n + 1 ..] };
    }
    return .{ .metric = key, .tags = "{}" };
}
