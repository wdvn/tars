//! Approved plan helpers — load rollback script from Analyst planner artifacts.

const std = @import("std");
const memory = @import("../memory/mod.zig");

/// Extract `"rollback":"..."` from planner JSON (flat string field).
pub fn extractRollbackField(allocator: std.mem.Allocator, plan_json: []const u8) !?[]u8 {
    const trimmed = std.mem.trim(u8, plan_json, " \r\n");
    if (trimmed.len == 0) return null;

    const needle = "\"rollback\":\"";
    const start = std.mem.indexOf(u8, trimmed, needle) orelse return null;
    const value_start = start + needle.len;
    const end = std.mem.indexOfPos(u8, trimmed, value_start, "\"") orelse return null;
    const value = trimmed[value_start..end];
    if (value.len == 0) return null;
    return try allocator.dupe(u8, value);
}

/// Load rollback command from the latest Analyst `plan` artifact for a mission.
pub fn loadLatestRollback(
    allocator: std.mem.Allocator,
    store: memory.store.Store,
    io: std.Io,
    mission_id: []const u8,
) !?[]u8 {
    const payload = store.queryLatestArtifactPayload(io, mission_id, "plan") catch return null;
    defer store.allocator.free(payload);
    if (std.mem.trim(u8, payload, " \r\n").len == 0) return null;
    return extractRollbackField(allocator, payload);
}
