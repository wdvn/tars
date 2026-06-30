//! Render operational metrics — current run + DB aggregates.

const std = @import("std");
const registry = @import("registry.zig");
const collector = @import("collector.zig");
const store_mod = @import("../memory/store.zig");

pub const DbTotals = struct {
    artifacts: i64 = 0,
    audit_log: i64 = 0,
    episodic_memory: i64 = 0,
    session_turns: i64 = 0,
    agent_events: i64 = 0,
    metric_samples: i64 = 0,
    metric_runs: i64 = 0,
};

/// Count rows in core SQLite tables for end-of-run operational report.
pub fn loadDbTotals(st: *const store_mod.Store, io: std.Io, allocator: std.mem.Allocator) !DbTotals {
    var t: DbTotals = .{};
    t.artifacts = try queryCount(st, io, "SELECT COUNT(*) FROM artifacts;");
    t.audit_log = try queryCount(st, io, "SELECT COUNT(*) FROM audit_log;");
    t.episodic_memory = try queryCount(st, io, "SELECT COUNT(*) FROM episodic_memory;");
    t.session_turns = try queryCount(st, io, "SELECT COUNT(*) FROM session_turns;");
    t.agent_events = try queryCount(st, io, "SELECT COUNT(*) FROM agent_events;");
    t.metric_samples = try queryCount(st, io, "SELECT COUNT(*) FROM metric_samples;");
    t.metric_runs = try queryCount(st, io, "SELECT COUNT(*) FROM metric_runs;");
    _ = allocator;
    return t;
}

/// Parse single-cell COUNT(*) result; returns 0 on query/parse failure.
fn queryCount(st: *const store_mod.Store, io: std.Io, sql: []const u8) !i64 {
    const out = st.querySql(io, sql) catch return 0;
    defer st.allocator.free(out);
    const trimmed = std.mem.trim(u8, out, " \r\n");
    return std.fmt.parseInt(i64, trimmed, 10) catch 0;
}

/// Pretty-print full metric catalog for current run plus database totals.
pub fn printHuman(
    w: *std.Io.Writer,
    m: *const collector.Metrics,
    db: DbTotals,
) !void {
    try w.print("T.A.R.S. operational report\n", .{});
    try w.print("  run_id:   {s}\n", .{m.run_id});
    try w.print("  command:  {s}\n\n", .{m.command});

    var last_sub: []const u8 = "";
    for (registry.all) |def| {
        if (!std.mem.eql(u8, def.subsystem, last_sub)) {
            last_sub = def.subsystem;
            try w.print("[{s}]\n", .{def.subsystem});
        }
        const val = m.value(def.name);
        try w.print("  {s}: {d:.3} {s}  — {s}\n", .{ def.name, val, def.unit.name(), def.description });
    }

    try w.print("\n[database totals]\n", .{});
    try w.print("  artifacts:       {d}\n", .{db.artifacts});
    try w.print("  audit_log:       {d}\n", .{db.audit_log});
    try w.print("  episodic_memory: {d}\n", .{db.episodic_memory});
    try w.print("  session_turns:   {d}\n", .{db.session_turns});
    try w.print("  agent_events:    {d}\n", .{db.agent_events});
    try w.print("  metric_runs:     {d}\n", .{db.metric_runs});
    try w.print("  metric_samples:  {d}\n", .{db.metric_samples});
}

/// Machine-readable report: run metadata, all metrics (including zeros), DB totals.
pub fn printJson(
    allocator: std.mem.Allocator,
    w: *std.Io.Writer,
    m: *const collector.Metrics,
    db: DbTotals,
) !void {
    try w.print("{{\"run_id\":\"{s}\",\"command\":\"{s}\",\"metrics\":[", .{ m.run_id, m.command });
    var first = true;
    for (registry.all) |def| {
        if (!first) try w.print(",", .{});
        first = false;
        const val = m.value(def.name);
        try w.print(
            "{{\"name\":\"{s}\",\"subsystem\":\"{s}\",\"unit\":\"{s}\",\"value\":{d},\"description\":\"{s}\"}}",
            .{ def.name, def.subsystem, def.unit.name(), val, def.description },
        );
    }
    try w.print(
        "],\"database\":{{\"artifacts\":{d},\"audit_log\":{d},\"episodic_memory\":{d},\"session_turns\":{d},\"agent_events\":{d},\"metric_runs\":{d},\"metric_samples\":{d}}}}}",
        .{ db.artifacts, db.audit_log, db.episodic_memory, db.session_turns, db.agent_events, db.metric_runs, db.metric_samples },
    );
    _ = allocator;
}

/// Summarize last 20 persisted metric runs from SQLite (id, command, sample stats).
pub fn printHistory(st: *const store_mod.Store, io: std.Io, w: *std.Io.Writer) !void {
    const sql =
        \\SELECT r.id, r.command, COUNT(s.id), COALESCE(SUM(s.value), 0)
        \\FROM metric_runs r
        \\LEFT JOIN metric_samples s ON s.run_id = r.id
        \\GROUP BY r.id
        \\ORDER BY r.started_at DESC
        \\LIMIT 20;
    ;
    const out = st.querySql(io, sql) catch return;
    defer st.allocator.free(out);

    try w.print("\n[metric run history — last 20]\n", .{});
    var lines = std.mem.splitScalar(u8, out, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var parts = std.mem.splitScalar(u8, line, '|');
        const id = parts.next() orelse continue;
        const cmd = parts.next() orelse continue;
        const samples = parts.next() orelse "0";
        const sum = parts.next() orelse "0";
        try w.print("  {s}  {s}  samples={s} sum={s}\n", .{ id, cmd, samples, sum });
    }
}
