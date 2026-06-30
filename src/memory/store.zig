//! Memory store — SQLite + sqlite-vector (file-based).
//! SQL lives in memory/; runtime via sqlite3 CLI until native bindings land.

const std = @import("std");

pub const schema_path = "memory/schema.sql";
pub const schema_vector_path = "memory/schema_vector.sql";
pub const schema_session_path = "memory/schema_session.sql";
pub const schema_metrics_path = "memory/schema_metrics.sql";
pub const query_recall_path = "memory/queries/recall.sql";
pub const query_recall_fts_path = "memory/queries/recall_fts.sql";
pub const query_write_path = "memory/queries/write.sql";
pub const query_read_path = "memory/queries/read.sql";

pub const embedding_dimension: u32 = 384;

pub const StoreError = error{
    SqliteFailed,
    SchemaApplyFailed,
    OutOfMemory,
};

pub const Store = struct {
    db_path: []const u8,
    allocator: std.mem.Allocator,

    /// Own a copy of db_path so callers can pass stack literals safely.
    pub fn init(allocator: std.mem.Allocator, db_path: []const u8) !Store {
        return .{
            .db_path = try allocator.dupe(u8, db_path),
            .allocator = allocator,
        };
    }

    /// Release heap-owned db_path; SQLite file is left on disk.
    pub fn deinit(self: *Store) void {
        self.allocator.free(self.db_path);
    }

    /// Apply base schema via memory/init.sh (same as `zig build init-db`).
    pub fn applySchema(self: *const Store, io: std.Io) StoreError!void {
        const result = std.process.run(self.allocator, io, .{
            .argv = &.{ "bash", "memory/init.sh" },
        }) catch return StoreError.SchemaApplyFailed;
        defer {
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
        }
        switch (result.term) {
            .exited => |code| if (code != 0) return StoreError.SchemaApplyFailed,
            else => return StoreError.SchemaApplyFailed,
        }
    }

    /// Fire-and-forget SQL — discards stdout for INSERT/UPDATE paths.
    fn runSqlite(self: *const Store, io: std.Io, sql: []const u8) StoreError!void {
        _ = try self.querySql(io, sql);
    }

const metrics = @import("../metrics/collector.zig");

    /// Run SQL and return stdout (empty string if no rows).
    pub fn querySql(self: *const Store, io: std.Io, sql: []const u8) StoreError![]const u8 {
        metrics.gInc("storage.sql.queries", 1);
        const result = std.process.run(self.allocator, io, .{
            .argv = &.{ "sqlite3", self.db_path, sql },
        }) catch {
            metrics.gInc("storage.sql.errors", 1);
            return StoreError.SqliteFailed;
        };
        defer self.allocator.free(result.stderr);
        switch (result.term) {
            .exited => |code| {
                if (code != 0) {
                    metrics.gInc("storage.sql.errors", 1);
                    self.allocator.free(result.stdout);
                    return StoreError.SqliteFailed;
                }
                return result.stdout;
            },
            else => {
                metrics.gInc("storage.sql.errors", 1);
                self.allocator.free(result.stdout);
                return StoreError.SqliteFailed;
            },
        }
    }

    /// Double single-quotes so user content survives string interpolation in SQL.
    fn escapeSql(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        for (text) |c| {
            if (c == '\'') try out.appendSlice(allocator, "''") else try out.append(allocator, c);
        }
        return out.toOwnedSlice(allocator);
    }

    /// Persist an agent reasoning/execution artifact keyed by mission phase.
    pub fn writeArtifact(
        self: *const Store,
        io: std.Io,
        mission_id: []const u8,
        phase: []const u8,
        agent: []const u8,
        kind: []const u8,
        payload_json: []const u8,
        created_at: i64,
    ) StoreError!void {
        const sql = std.fmt.allocPrint(self.allocator,
            \\INSERT INTO artifacts (mission_id, phase, agent, kind, payload, created_at)
            \\VALUES ('{s}', '{s}', '{s}', '{s}', '{s}', {d});
        , .{ mission_id, phase, agent, kind, payload_json, created_at }) catch return StoreError.SqliteFailed;
        defer self.allocator.free(sql);
        try self.runSqlite(io, sql);
    }

    /// Append an immutable audit row for operator traceability and Monitor reports.
    pub fn appendAudit(
        self: *const Store,
        io: std.Io,
        mission_id: []const u8,
        agent: []const u8,
        event: []const u8,
        detail_json: []const u8,
        created_at: i64,
    ) StoreError!void {
        const sql = std.fmt.allocPrint(self.allocator,
            \\INSERT INTO audit_log (mission_id, agent, event, detail, created_at)
            \\VALUES ('{s}', '{s}', '{s}', '{s}', {d});
        , .{ mission_id, agent, event, detail_json, created_at }) catch return StoreError.SqliteFailed;
        defer self.allocator.free(sql);
        try self.runSqlite(io, sql);
    }

    /// Record inter-agent bus traffic (from → to) for replay and debugging.
    pub fn publishBusEvent(
        self: *const Store,
        io: std.Io,
        mission_id: []const u8,
        from_agent: []const u8,
        to_agent: []const u8,
        event_type: []const u8,
        payload_json: []const u8,
        created_at: i64,
    ) StoreError!void {
        const sql = std.fmt.allocPrint(self.allocator,
            \\INSERT INTO agent_events (mission_id, from_agent, to_agent, event_type, payload, created_at)
            \\VALUES ('{s}', '{s}', '{s}', '{s}', '{s}', {d});
        , .{ mission_id, from_agent, to_agent, event_type, payload_json, created_at }) catch return StoreError.SqliteFailed;
        defer self.allocator.free(sql);
        try self.runSqlite(io, sql);
    }

    /// Path to external recall SQL template (vector search when extension loaded).
    pub fn recallQueryPath() []const u8 {
        return query_recall_path;
    }

    /// Persist episodic memory with embedding stored in meta JSON for local cosine recall.
    pub fn writeEpisode(
        self: *const Store,
        io: std.Io,
        mission_id: ?[]const u8,
        agent: []const u8,
        content: []const u8,
        meta_json: []const u8,
        created_at: i64,
    ) StoreError!void {
        const esc_content = escapeSql(self.allocator, content) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_content);
        const esc_meta = escapeSql(self.allocator, meta_json) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_meta);

        const sql = if (mission_id) |mid| blk: {
            const esc_mid = escapeSql(self.allocator, mid) catch return StoreError.SqliteFailed;
            defer self.allocator.free(esc_mid);
            break :blk try std.fmt.allocPrint(self.allocator,
                \\INSERT INTO episodic_memory (mission_id, agent, content, meta, created_at)
                \\VALUES ('{s}', '{s}', '{s}', '{s}', {d});
            , .{ esc_mid, agent, esc_content, esc_meta, created_at });
        } else try std.fmt.allocPrint(self.allocator,
            \\INSERT INTO episodic_memory (agent, content, meta, created_at)
            \\VALUES ('{s}', '{s}', '{s}', {d});
        , .{ agent, esc_content, esc_meta, created_at });
        defer self.allocator.free(sql);
        try self.runSqlite(io, sql);
    }

    /// Tab-separated rows: id, content, meta, embedding_json (from meta.embedding).
    pub fn queryAllEpisodes(self: *const Store, io: std.Io) StoreError![]const u8 {
        const sql =
            \\SELECT id, content, COALESCE(meta, '{}'), COALESCE(json_extract(meta, '$.embedding'), '[]')
            \\FROM episodic_memory
            \\WHERE json_extract(meta, '$.embedding') IS NOT NULL
            \\ORDER BY created_at DESC;
        ;
        return self.querySql(io, sql);
    }

    /// Idempotent session row — INSERT OR IGNORE avoids duplicate operator sessions.
    pub fn createSession(self: *const Store, io: std.Io, session_id: []const u8, created_at: i64) StoreError!void {
        const esc_id = escapeSql(self.allocator, session_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_id);
        const sql = try std.fmt.allocPrint(self.allocator,
            \\INSERT OR IGNORE INTO sessions (id, created_at, updated_at) VALUES ('{s}', {d}, {d});
        , .{ esc_id, created_at, created_at });
        defer self.allocator.free(sql);
        try self.runSqlite(io, sql);
    }

    /// Append one chat turn and bump session updated_at in the same transaction batch.
    pub fn appendSessionTurn(
        self: *const Store,
        io: std.Io,
        session_id: []const u8,
        role: []const u8,
        content: []const u8,
        created_at: i64,
    ) StoreError!void {
        const esc_sid = escapeSql(self.allocator, session_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_sid);
        const esc_role = escapeSql(self.allocator, role) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_role);
        const esc_content = escapeSql(self.allocator, content) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_content);

        const sql = try std.fmt.allocPrint(self.allocator,
            \\INSERT INTO session_turns (session_id, role, content, created_at)
            \\VALUES ('{s}', '{s}', '{s}', {d});
            \\UPDATE sessions SET updated_at = {d} WHERE id = '{s}';
        , .{ esc_sid, esc_role, esc_content, created_at, created_at, esc_sid });
        defer self.allocator.free(sql);
        try self.runSqlite(io, sql);
    }

    /// Returns lines: role|content (sqlite default sep; legacy helper).
    pub fn recentSessionTurns(
        self: *const Store,
        io: std.Io,
        session_id: []const u8,
        limit: usize,
    ) StoreError![]const u8 {
        const esc_sid = escapeSql(self.allocator, session_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_sid);
        const sql = try std.fmt.allocPrint(self.allocator,
            \\SELECT role, content FROM session_turns
            \\WHERE session_id = '{s}'
            \\ORDER BY created_at ASC
            \\LIMIT {d};
        , .{ esc_sid, limit });
        defer self.allocator.free(sql);
        return self.querySql(io, sql);
    }

    /// Count turns in a session (for summary fold triggers).
    pub fn countSessionTurns(self: *const Store, io: std.Io, session_id: []const u8) StoreError!usize {
        const esc_sid = escapeSql(self.allocator, session_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_sid);
        const sql = try std.fmt.allocPrint(self.allocator,
            \\SELECT COUNT(*) FROM session_turns WHERE session_id = '{s}';
        , .{esc_sid});
        defer self.allocator.free(sql);
        const out = try self.querySql(io, sql);
        defer self.allocator.free(out);
        const trimmed = std.mem.trim(u8, out, " \r\n");
        return std.fmt.parseInt(usize, trimmed, 10) catch 0;
    }

    /// Rolling session summary (compressed older turns for LLM context).
    /// Caller owns returned slice (trimmed copy — safe to free with store allocator).
    pub fn getSessionSummary(self: *const Store, io: std.Io, session_id: []const u8) StoreError![]const u8 {
        const esc_sid = escapeSql(self.allocator, session_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_sid);
        const sql = try std.fmt.allocPrint(self.allocator,
            \\SELECT COALESCE(summary, '') FROM sessions WHERE id = '{s}';
        , .{esc_sid});
        defer self.allocator.free(sql);
        const out = try self.querySql(io, sql);
        defer self.allocator.free(out);
        const trimmed = std.mem.trim(u8, out, " \r\n");
        return self.allocator.dupe(u8, trimmed) catch return StoreError.OutOfMemory;
    }

    pub fn setSessionSummary(
        self: *const Store,
        io: std.Io,
        session_id: []const u8,
        summary: []const u8,
    ) StoreError!void {
        const esc_sid = escapeSql(self.allocator, session_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_sid);
        const esc_sum = escapeSql(self.allocator, summary) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_sum);
        const sql = try std.fmt.allocPrint(self.allocator,
            \\UPDATE sessions SET summary = '{s}', updated_at = 0 WHERE id = '{s}';
        , .{ esc_sum, esc_sid });
        defer self.allocator.free(sql);
        try self.runSqlite(io, sql);
    }

    /// Last N turns as one JSON object per line: {"role":"…","content":"…"} (ASC order).
    pub fn loadSessionTurnsJson(
        self: *const Store,
        io: std.Io,
        session_id: []const u8,
        limit: usize,
    ) StoreError![]const u8 {
        const esc_sid = escapeSql(self.allocator, session_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_sid);
        const sql = try std.fmt.allocPrint(self.allocator,
            \\SELECT json_object('role', role, 'content', content) FROM (
            \\  SELECT role, content, created_at, id FROM session_turns
            \\  WHERE session_id = '{s}'
            \\  ORDER BY created_at DESC, id DESC
            \\  LIMIT {d}
            \\) AS sub ORDER BY sub.created_at ASC, sub.id ASC;
        , .{ esc_sid, limit });
        defer self.allocator.free(sql);
        return self.querySql(io, sql);
    }

    /// Open a metric run row before samples are flushed (upsert by run_id).
    pub fn beginMetricRun(
        self: *const Store,
        io: std.Io,
        run_id: []const u8,
        command: []const u8,
        started_at: i64,
        meta_json: []const u8,
    ) StoreError!void {
        const esc_id = escapeSql(self.allocator, run_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_id);
        const esc_cmd = escapeSql(self.allocator, command) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_cmd);
        const esc_meta = escapeSql(self.allocator, meta_json) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_meta);
        const sql = try std.fmt.allocPrint(self.allocator,
            \\INSERT OR REPLACE INTO metric_runs (id, command, started_at, meta) VALUES ('{s}', '{s}', {d}, '{s}');
        , .{ esc_id, esc_cmd, started_at, esc_meta });
        defer self.allocator.free(sql);
        try self.runSqlite(io, sql);
    }

    /// Mark run end time so history queries can compute duration.
    pub fn finishMetricRun(self: *const Store, io: std.Io, run_id: []const u8, finished_at: i64) StoreError!void {
        const esc_id = escapeSql(self.allocator, run_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_id);
        const sql = try std.fmt.allocPrint(self.allocator,
            \\UPDATE metric_runs SET finished_at = {d} WHERE id = '{s}';
        , .{ finished_at, esc_id });
        defer self.allocator.free(sql);
        try self.runSqlite(io, sql);
    }

    /// Insert one numeric sample with optional JSON tags for dimensional drill-down.
    pub fn writeMetricSample(
        self: *const Store,
        io: std.Io,
        run_id: []const u8,
        metric: []const u8,
        value: f64,
        unit: []const u8,
        tags_json: []const u8,
        created_at: i64,
    ) StoreError!void {
        const esc_id = escapeSql(self.allocator, run_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_id);
        const esc_metric = escapeSql(self.allocator, metric) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_metric);
        const esc_unit = escapeSql(self.allocator, unit) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_unit);
        const esc_tags = escapeSql(self.allocator, tags_json) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_tags);
        const sql = try std.fmt.allocPrint(self.allocator,
            \\INSERT INTO metric_samples (run_id, metric, value, unit, tags, created_at)
            \\VALUES ('{s}', '{s}', {d}, '{s}', '{s}', {d});
        , .{ esc_id, esc_metric, value, esc_unit, esc_tags, created_at });
        defer self.allocator.free(sql);
        try self.runSqlite(io, sql);
    }

    /// Upsert a pending executor checkpoint before a step runs (enables retry/rollback).
    pub fn upsertExecutorCheckpoint(
        self: *const Store,
        io: std.Io,
        mission_id: []const u8,
        step_index: usize,
        action_kind: []const u8,
        action_payload: []const u8,
        backup_dir: ?[]const u8,
        backup_meta_json: []const u8,
        created_at: i64,
    ) StoreError!void {
        const esc_mid = escapeSql(self.allocator, mission_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_mid);
        const esc_kind = escapeSql(self.allocator, action_kind) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_kind);
        const esc_payload = escapeSql(self.allocator, action_payload) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_payload);
        const esc_meta = escapeSql(self.allocator, backup_meta_json) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_meta);

        const esc_dir = if (backup_dir) |d| blk: {
            const e = escapeSql(self.allocator, d) catch return StoreError.SqliteFailed;
            break :blk e;
        } else null;
        defer if (esc_dir) |d| self.allocator.free(d);

        const sql = if (esc_dir) |dir| blk: {
            break :blk try std.fmt.allocPrint(self.allocator,
                \\INSERT INTO executor_checkpoints
                \\(mission_id, step_index, action_kind, action_payload, backup_dir, backup_meta, status, created_at)
                \\VALUES ('{s}', {d}, '{s}', '{s}', '{s}', '{s}', 'pending', {d})
                \\ON CONFLICT(mission_id, step_index) DO UPDATE SET
                \\  action_kind = excluded.action_kind,
                \\  action_payload = excluded.action_payload,
                \\  backup_dir = excluded.backup_dir,
                \\  backup_meta = excluded.backup_meta,
                \\  result_json = NULL,
                \\  status = 'pending',
                \\  created_at = excluded.created_at;
            , .{ esc_mid, step_index, esc_kind, esc_payload, dir, esc_meta, created_at });
        } else try std.fmt.allocPrint(self.allocator,
            \\INSERT INTO executor_checkpoints
            \\(mission_id, step_index, action_kind, action_payload, backup_dir, backup_meta, status, created_at)
            \\VALUES ('{s}', {d}, '{s}', '{s}', NULL, '{s}', 'pending', {d})
            \\ON CONFLICT(mission_id, step_index) DO UPDATE SET
            \\  action_kind = excluded.action_kind,
            \\  action_payload = excluded.action_payload,
            \\  backup_dir = NULL,
            \\  backup_meta = excluded.backup_meta,
            \\  result_json = NULL,
            \\  status = 'pending',
            \\  created_at = excluded.created_at;
        , .{ esc_mid, step_index, esc_kind, esc_payload, esc_meta, created_at });
        defer self.allocator.free(sql);
        try self.runSqlite(io, sql);
    }

    /// Mark checkpoint completed or failed after step execution.
    pub fn finishExecutorCheckpoint(
        self: *const Store,
        io: std.Io,
        mission_id: []const u8,
        step_index: usize,
        status: []const u8,
        result_json: ?[]const u8,
    ) StoreError!void {
        const esc_mid = escapeSql(self.allocator, mission_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_mid);
        const esc_status = escapeSql(self.allocator, status) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_status);

        const sql = if (result_json) |rj| blk: {
            const esc_result = escapeSql(self.allocator, rj) catch return StoreError.SqliteFailed;
            defer self.allocator.free(esc_result);
            break :blk try std.fmt.allocPrint(self.allocator,
                \\UPDATE executor_checkpoints
                \\SET status = '{s}', result_json = '{s}'
                \\WHERE mission_id = '{s}' AND step_index = {d};
            , .{ esc_status, esc_result, esc_mid, step_index });
        } else try std.fmt.allocPrint(self.allocator,
            \\UPDATE executor_checkpoints
            \\SET status = '{s}', result_json = NULL
            \\WHERE mission_id = '{s}' AND step_index = {d};
        , .{ esc_status, esc_mid, step_index });
        defer self.allocator.free(sql);
        try self.runSqlite(io, sql);
    }

    /// Mark checkpoint rolled back after restore.
    pub fn markExecutorCheckpointRolledBack(
        self: *const Store,
        io: std.Io,
        mission_id: []const u8,
        step_index: usize,
    ) StoreError!void {
        const esc_mid = escapeSql(self.allocator, mission_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_mid);
        const sql = try std.fmt.allocPrint(self.allocator,
            \\UPDATE executor_checkpoints SET status = 'rolled_back'
            \\WHERE mission_id = '{s}' AND step_index = {d};
        , .{ esc_mid, step_index });
        defer self.allocator.free(sql);
        try self.runSqlite(io, sql);
    }

    /// Return payload JSON of the newest artifact for mission + kind.
    pub fn queryLatestArtifactPayload(
        self: *const Store,
        io: std.Io,
        mission_id: []const u8,
        kind: []const u8,
    ) StoreError![]const u8 {
        const esc_mid = escapeSql(self.allocator, mission_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_mid);
        const esc_kind = escapeSql(self.allocator, kind) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_kind);
        const sql = try std.fmt.allocPrint(self.allocator,
            \\SELECT payload FROM artifacts
            \\WHERE mission_id = '{s}' AND kind = '{s}'
            \\ORDER BY id DESC
            \\LIMIT 1;
        , .{ esc_mid, esc_kind });
        defer self.allocator.free(sql);
        return self.querySql(io, sql);
    }

    /// Return backup_meta JSON for one executor step checkpoint.
    pub fn queryExecutorCheckpointMeta(
        self: *const Store,
        io: std.Io,
        mission_id: []const u8,
        step_index: usize,
    ) StoreError![]const u8 {
        const esc_mid = escapeSql(self.allocator, mission_id) catch return StoreError.SqliteFailed;
        defer self.allocator.free(esc_mid);
        const sql = try std.fmt.allocPrint(self.allocator,
            \\SELECT COALESCE(backup_meta, '{{}}')
            \\FROM executor_checkpoints
            \\WHERE mission_id = '{s}' AND step_index = {d}
            \\LIMIT 1;
        , .{ esc_mid, step_index });
        defer self.allocator.free(sql);
        return self.querySql(io, sql);
    }
};
