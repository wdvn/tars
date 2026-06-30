const std = @import("std");
const types = @import("../../../types.zig");
const memory = @import("../../../memory/mod.zig");
const metrics = @import("../../../metrics/collector.zig");

pub const Writer = struct {
    pub fn log(
        store: *const memory.store.Store,
        io: std.Io,
        mission_id: []const u8,
        event: []const u8,
        detail_json: []const u8,
        created_at: i64,
    ) !void {
        try store.appendAudit(io, mission_id, types.Agent.monitor.name(), event, detail_json, created_at);
        metrics.gInc("monitor.audit.events", 1);
    }
};
