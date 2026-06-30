//! Canonical metric catalog — every operational index TARS tracks.

const std = @import("std");

pub const Unit = enum {
    count,
    bytes,
    tokens,
    milliseconds,
    score,
    ratio,

    pub fn name(self: Unit) []const u8 {
        return @tagName(self);
    }
};

pub const Def = struct {
    name: []const u8,
    unit: Unit,
    subsystem: []const u8,
    description: []const u8,
};

/// All metrics — report shows every entry (0 if not observed this run).
pub const all: []const Def = &.{
    // --- LLM ---
    .{ .name = "llm.requests.total", .unit = .count, .subsystem = "llm", .description = "LLM completion requests (stream + non-stream)" },
    .{ .name = "llm.requests.errors", .unit = .count, .subsystem = "llm", .description = "LLM request failures" },
    .{ .name = "llm.tokens.total", .unit = .tokens, .subsystem = "llm", .description = "Tokens reported by provider" },
    .{ .name = "llm.latency_ms.total", .unit = .milliseconds, .subsystem = "llm", .description = "Cumulative LLM request latency" },
    .{ .name = "llm.stream.chunks", .unit = .count, .subsystem = "llm", .description = "Stream tokens/chunks emitted" },

    // --- Mission / loop ---
    .{ .name = "mission.iterations", .unit = .count, .subsystem = "mission", .description = "Autonomous loop iterations" },
    .{ .name = "mission.phase.entered", .unit = .count, .subsystem = "mission", .description = "Phase transitions (ORIENT…VERIFY)" },
    .{ .name = "mission.loop_back", .unit = .count, .subsystem = "mission", .description = "Monitor loop-back events" },
    .{ .name = "mission.verify.pass", .unit = .count, .subsystem = "mission", .description = "Verify phase passed" },
    .{ .name = "mission.verify.fail", .unit = .count, .subsystem = "mission", .description = "Verify phase failed" },

    // --- Analyst ---
    .{ .name = "analyst.blocks.invoked", .unit = .count, .subsystem = "analyst", .description = "Reasoning blocks executed" },
    .{ .name = "analyst.artifacts.written", .unit = .count, .subsystem = "analyst", .description = "Artifacts persisted by Analyst" },

    // --- Executor ---
    .{ .name = "executor.actions.total", .unit = .count, .subsystem = "executor", .description = "Action steps attempted" },
    .{ .name = "executor.actions.success", .unit = .count, .subsystem = "executor", .description = "Actions completed successfully" },
    .{ .name = "executor.actions.failed", .unit = .count, .subsystem = "executor", .description = "Actions failed (non-zero exit)" },
    .{ .name = "executor.actions.denied", .unit = .count, .subsystem = "executor", .description = "Actions blocked by Safety Guard" },
    .{ .name = "executor.artifacts.written", .unit = .count, .subsystem = "executor", .description = "Artifacts persisted by Executor" },

    // --- Monitor ---
    .{ .name = "monitor.verify.checks", .unit = .count, .subsystem = "monitor", .description = "Verify commands run" },
    .{ .name = "monitor.verify.pass", .unit = .count, .subsystem = "monitor", .description = "Individual verify checks passed" },
    .{ .name = "monitor.verify.fail", .unit = .count, .subsystem = "monitor", .description = "Individual verify checks failed" },
    .{ .name = "monitor.watchdog.failures", .unit = .count, .subsystem = "monitor", .description = "Health watchdog failure count" },
    .{ .name = "monitor.audit.events", .unit = .count, .subsystem = "monitor", .description = "Audit log entries written" },

    // --- Memory ---
    .{ .name = "memory.episodes.written", .unit = .count, .subsystem = "memory", .description = "Episodic memory rows inserted" },
    .{ .name = "memory.recall.queries", .unit = .count, .subsystem = "memory", .description = "Semantic recall queries" },
    .{ .name = "memory.recall.hits", .unit = .count, .subsystem = "memory", .description = "Recall hits returned" },
    .{ .name = "memory.recall.top_score", .unit = .score, .subsystem = "memory", .description = "Best cosine score in last recall (gauge)" },

    // --- Session ---
    .{ .name = "session.turns.total", .unit = .count, .subsystem = "session", .description = "Session turns appended" },
    .{ .name = "session.turns.operator", .unit = .count, .subsystem = "session", .description = "Operator turns" },
    .{ .name = "session.turns.agent", .unit = .count, .subsystem = "session", .description = "Agent turns" },

    // --- Perception ---
    .{ .name = "perception.files.read", .unit = .count, .subsystem = "perception", .description = "Files read for evidence" },
    .{ .name = "perception.bytes.read", .unit = .bytes, .subsystem = "perception", .description = "Bytes read from codebase" },
    .{ .name = "perception.grep.queries", .unit = .count, .subsystem = "perception", .description = "Grep/rg searches" },
    .{ .name = "perception.grep.bytes", .unit = .bytes, .subsystem = "perception", .description = "Grep result bytes" },

    // --- MCP ---
    .{ .name = "mcp.tool.calls", .unit = .count, .subsystem = "mcp", .description = "MCP tool invocations" },
    .{ .name = "mcp.tool.errors", .unit = .count, .subsystem = "mcp", .description = "MCP tool failures" },

    // --- Safety ---
    .{ .name = "safety.guard.evaluations", .unit = .count, .subsystem = "safety", .description = "Safety Guard evaluations" },
    .{ .name = "safety.guard.denials", .unit = .count, .subsystem = "safety", .description = "Safety Guard denials" },

    // --- Storage / transport ---
    .{ .name = "storage.sql.queries", .unit = .count, .subsystem = "storage", .description = "SQLite queries executed" },
    .{ .name = "storage.sql.errors", .unit = .count, .subsystem = "storage", .description = "SQLite query failures" },
    .{ .name = "http.requests.total", .unit = .count, .subsystem = "http", .description = "HTTP requests (LLM transport)" },
    .{ .name = "http.requests.errors", .unit = .count, .subsystem = "http", .description = "HTTP request failures" },

    // --- Stream ---
    .{ .name = "stream.chunks.emitted", .unit = .count, .subsystem = "stream", .description = "Output chunks to operator" },

    // --- Bus ---
    .{ .name = "bus.events.published", .unit = .count, .subsystem = "bus", .description = "Agent bus events published" },
};

pub fn find(name: []const u8) ?Def {
    for (all) |d| {
        if (std.mem.eql(u8, d.name, name)) return d;
    }
    return null;
}

pub fn unitFor(name: []const u8) Unit {
    return find(name).?.unit;
}
