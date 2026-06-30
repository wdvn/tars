//! Multi-turn operator sessions — persisted in SQLite.

const std = @import("std");
const memory = @import("../memory/mod.zig");
const metrics = @import("../metrics/collector.zig");

pub const Session = struct {
    id: []const u8,
    store: memory.store.Store,
    io: std.Io,

    pub fn create(
        allocator: std.mem.Allocator,
        store: memory.store.Store,
        io: std.Io,
        label: []const u8,
    ) !Session {
        const id = try std.fmt.allocPrint(allocator, "sess-{s}-{d}", .{ label, hashLabel(label) });
        const now: i64 = 0;
        try store.createSession(io, id, now);
        return .{ .id = id, .store = store, .io = io };
    }

    pub fn deinit(self: *Session, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
    }

    pub fn appendOperator(self: *const Session, content: []const u8) !void {
        try self.appendTurn("operator", content);
    }

    pub fn appendAgent(self: *const Session, agent: []const u8, content: []const u8) !void {
        try self.appendTurn(agent, content);
    }

    pub fn appendTurn(self: *const Session, role: []const u8, content: []const u8) !void {
        const now: i64 = 0;
        try self.store.appendSessionTurn(self.io, self.id, role, content, now);
        metrics.gInc("session.turns.total", 1);
        if (std.mem.eql(u8, role, "operator")) {
            metrics.gInc("session.turns.operator", 1);
        } else {
            metrics.gInc("session.turns.agent", 1);
        }
    }

    pub fn recentContext(self: *const Session, _: std.mem.Allocator, limit: usize) ![]const u8 {
        return self.store.recentSessionTurns(self.io, self.id, limit);
    }
};

fn hashLabel(label: []const u8) u64 {
    return std.hash.Wyhash.hash(0, label);
}
