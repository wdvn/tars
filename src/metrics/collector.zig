//! In-process metrics collector (in-memory only; see persist.zig for SQLite).

const std = @import("std");
const registry = @import("registry.zig");

pub const Sample = struct {
    metric: []const u8,
    value: f64,
    unit: registry.Unit,
    tags_json: []const u8,
};

pub const Metrics = struct {
    run_id: []const u8,
    command: []const u8,
    meta_json: []const u8,
    started_at: i64,
    allocator: std.mem.Allocator,

    /// key = metric + "\0" + tags_json
    totals: std.StringHashMap(f64),
    gauges: std.StringHashMap(f64),

    pub fn init(allocator: std.mem.Allocator, command: []const u8, label: []const u8) !Metrics {
        // Stable run id for SQLite persistence and human-readable labels.
        const run_id = try std.fmt.allocPrint(allocator, "run-{s}-{x}", .{ label, std.hash.Wyhash.hash(0, command) });
        const cmd = try allocator.dupe(u8, command);
        const meta = try std.fmt.allocPrint(allocator, "{{\"label\":\"{s}\"}}", .{label});
        return .{
            .run_id = run_id,
            .command = cmd,
            .meta_json = meta,
            .started_at = 0,
            .allocator = allocator,
            .totals = std.StringHashMap(f64).init(allocator),
            .gauges = std.StringHashMap(f64).init(allocator),
        };
    }

    pub fn deinit(self: *Metrics) void {
        // Free every owned hash-map key before destroying the maps.
        var it = self.totals.iterator();
        while (it.next()) |entry| self.allocator.free(entry.key_ptr.*);
        self.totals.deinit();
        var git = self.gauges.iterator();
        while (git.next()) |entry| self.allocator.free(entry.key_ptr.*);
        self.gauges.deinit();
        self.allocator.free(self.run_id);
        self.allocator.free(self.command);
        self.allocator.free(self.meta_json);
    }

    pub fn inc(self: *Metrics, name: []const u8, delta: f64) !void {
        // Untagged counter increment — tags default to empty JSON object.
        try self.record(name, delta, "{}");
    }

    /// Increment a counter with dimensional tags (stored in the map key).
    pub fn incTags(self: *Metrics, name: []const u8, delta: f64, tags_json: []const u8) !void {
        try self.record(name, delta, tags_json);
    }

    pub fn setGauge(self: *Metrics, name: []const u8, val: f64) !void {
        // Gauges are keyed by metric name only (no tag dimension).
        const name_owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_owned);
        const gop = try self.gauges.getOrPut(name_owned);
        if (gop.found_existing) {
            // Key already in map — discard duplicate we just allocated.
            self.allocator.free(name_owned);
        } else {
            gop.key_ptr.* = name_owned;
        }
        gop.value_ptr.* = val;
    }

    fn record(self: *Metrics, name: []const u8, delta: f64, tags_json: []const u8) !void {
        // Totals are keyed by metric name + tags so the same metric can fan out.
        const key = try self.makeKey(name, tags_json);
        errdefer self.allocator.free(key);
        const gop = try self.totals.getOrPut(key);
        if (gop.found_existing) {
            self.allocator.free(key);
        } else {
            gop.key_ptr.* = key;
        }
        gop.value_ptr.* += delta;
    }

    fn makeKey(self: *Metrics, name: []const u8, tags_json: []const u8) ![]const u8 {
        // Pipe separator lets value() split metric name from tag JSON without extra structs.
        return std.fmt.allocPrint(self.allocator, "{s}|{s}", .{ name, tags_json });
    }

    /// Sum all counter buckets that share the same metric name (any tags).
    pub fn value(self: *const Metrics, name: []const u8) f64 {
        var total: f64 = 0;
        var it = self.totals.iterator();
        while (it.next()) |entry| {
            const parts = splitKey(entry.key_ptr.*);
            if (std.mem.eql(u8, parts.metric, name)) total += entry.value_ptr.*;
        }
        return total;
    }

    /// Build a full registry snapshot (zeros for metrics never incremented this run).
    pub fn snapshot(self: *const Metrics, allocator: std.mem.Allocator) ![]Sample {
        var out: std.ArrayList(Sample) = .empty;
        errdefer {
            for (out.items) |s| {
                allocator.free(s.metric);
                allocator.free(s.tags_json);
            }
            out.deinit(allocator);
        }

        for (registry.all) |def| {
            const val = self.value(def.name);
            const metric = try allocator.dupe(u8, def.name);
            errdefer allocator.free(metric);
            const tags = try allocator.dupe(u8, "{}");
            try out.append(allocator, .{
                .metric = metric,
                .value = val,
                .unit = def.unit,
                .tags_json = tags,
            });
        }
        return out.toOwnedSlice(allocator);
    }
};

const KeyParts = struct {
    metric: []const u8,
    tags: []const u8,
};

/// Split composite map key back into metric name and tags JSON.
fn splitKey(key: []const u8) KeyParts {
    if (std.mem.indexOfScalar(u8, key, '|')) |n| {
        return .{ .metric = key[0..n], .tags = key[n + 1 ..] };
    }
    return .{ .metric = key, .tags = "{}" };
}

// --- Global handle for cross-module instrumentation ---

var global_ptr: ?*Metrics = null;

/// Register the active run so gInc/gGauge work from any module without threading Metrics.
pub fn setGlobal(m: ?*Metrics) void {
    global_ptr = m;
}

pub fn global() ?*Metrics {
    return global_ptr;
}

/// Best-effort untagged increment — ignores errors when metrics are disabled.
pub fn gInc(name: []const u8, delta: f64) void {
    if (global_ptr) |m| {
        m.inc(name, delta) catch {};
    }
}

/// Best-effort tagged increment for dimensional metrics.
pub fn gIncTags(name: []const u8, delta: f64, tags: []const u8) void {
    if (global_ptr) |m| {
        m.incTags(name, delta, tags) catch {};
    }
}

/// Best-effort gauge update (e.g. recall top_score).
pub fn gGauge(name: []const u8, value: f64) void {
    if (global_ptr) |m| {
        m.setGauge(name, value) catch {};
    }
}
