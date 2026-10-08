// Package metrics provides canonical metric definitions, in-memory collection, instrumentation, and reporting.
package metrics

// Unit represents the measurement unit for a metric.
type Unit string

const (
	UnitCount        Unit = "count"
	UnitBytes        Unit = "bytes"
	UnitTokens       Unit = "tokens"
	UnitMilliseconds Unit = "milliseconds"
	UnitScore        Unit = "score"
	UnitRatio        Unit = "ratio"
)

func (u Unit) Name() string {
	return string(u)
}

// Def is a canonical metric definition.
type Def struct {
	Name        string `json:"name"`
	Unit        Unit   `json:"unit"`
	Subsystem   string `json:"subsystem"`
	Description string `json:"description"`
}

// All contains the full catalog of canonical metrics tracked by TARS.
var All = []Def{
	// --- LLM ---
	{Name: "llm.requests.total", Unit: UnitCount, Subsystem: "llm", Description: "LLM completion requests (stream + non-stream)"},
	{Name: "llm.requests.errors", Unit: UnitCount, Subsystem: "llm", Description: "LLM request failures"},
	{Name: "llm.tokens.total", Unit: UnitTokens, Subsystem: "llm", Description: "Tokens reported by provider"},
	{Name: "llm.latency_ms.total", Unit: UnitMilliseconds, Subsystem: "llm", Description: "Cumulative LLM request latency"},
	{Name: "llm.stream.chunks", Unit: UnitCount, Subsystem: "llm", Description: "Stream tokens/chunks emitted"},

	// --- Mission / loop ---
	{Name: "mission.iterations", Unit: UnitCount, Subsystem: "mission", Description: "Autonomous loop iterations"},
	{Name: "mission.phase.entered", Unit: UnitCount, Subsystem: "mission", Description: "Phase transitions (ORIENT…VERIFY)"},
	{Name: "mission.loop_back", Unit: UnitCount, Subsystem: "mission", Description: "Monitor loop-back events"},
	{Name: "mission.verify.pass", Unit: UnitCount, Subsystem: "mission", Description: "Verify phase passed"},
	{Name: "mission.verify.fail", Unit: UnitCount, Subsystem: "mission", Description: "Verify phase failed"},

	// --- Analyst ---
	{Name: "analyst.blocks.invoked", Unit: UnitCount, Subsystem: "analyst", Description: "Reasoning blocks executed"},
	{Name: "analyst.artifacts.written", Unit: UnitCount, Subsystem: "analyst", Description: "Artifacts persisted by Analyst"},

	// --- Executor ---
	{Name: "executor.actions.total", Unit: UnitCount, Subsystem: "executor", Description: "Action steps attempted"},
	{Name: "executor.actions.success", Unit: UnitCount, Subsystem: "executor", Description: "Actions completed successfully"},
	{Name: "executor.actions.failed", Unit: UnitCount, Subsystem: "executor", Description: "Actions failed (non-zero exit)"},
	{Name: "executor.actions.denied", Unit: UnitCount, Subsystem: "executor", Description: "Actions blocked by Safety Guard"},
	{Name: "executor.artifacts.written", Unit: UnitCount, Subsystem: "executor", Description: "Artifacts persisted by Executor"},

	// --- Monitor ---
	{Name: "monitor.verify.checks", Unit: UnitCount, Subsystem: "monitor", Description: "Verify commands run"},
	{Name: "monitor.verify.pass", Unit: UnitCount, Subsystem: "monitor", Description: "Individual verify checks passed"},
	{Name: "monitor.verify.fail", Unit: UnitCount, Subsystem: "monitor", Description: "Individual verify checks failed"},
	{Name: "monitor.watchdog.failures", Unit: UnitCount, Subsystem: "monitor", Description: "Health watchdog failure count"},
	{Name: "monitor.audit.events", Unit: UnitCount, Subsystem: "monitor", Description: "Audit log entries written"},

	// --- Memory ---
	{Name: "memory.episodes.written", Unit: UnitCount, Subsystem: "memory", Description: "Episodic memory rows inserted"},
	{Name: "memory.recall.queries", Unit: UnitCount, Subsystem: "memory", Description: "Semantic recall queries"},
	{Name: "memory.recall.hits", Unit: UnitCount, Subsystem: "memory", Description: "Recall hits returned"},
	{Name: "memory.recall.top_score", Unit: UnitScore, Subsystem: "memory", Description: "Best cosine score in last recall (gauge)"},

	// --- Session ---
	{Name: "session.turns.total", Unit: UnitCount, Subsystem: "session", Description: "Session turns appended"},
	{Name: "session.turns.operator", Unit: UnitCount, Subsystem: "session", Description: "Operator turns"},
	{Name: "session.turns.agent", Unit: UnitCount, Subsystem: "session", Description: "Agent turns"},

	// --- Perception ---
	{Name: "perception.files.read", Unit: UnitCount, Subsystem: "perception", Description: "Files read for evidence"},
	{Name: "perception.bytes.read", Unit: UnitBytes, Subsystem: "perception", Description: "Bytes read from codebase"},
	{Name: "perception.grep.queries", Unit: UnitCount, Subsystem: "perception", Description: "Grep/rg searches"},
	{Name: "perception.grep.bytes", Unit: UnitBytes, Subsystem: "perception", Description: "Grep result bytes"},

	// --- MCP ---
	{Name: "mcp.tool.calls", Unit: UnitCount, Subsystem: "mcp", Description: "MCP tool invocations"},
	{Name: "mcp.tool.errors", Unit: UnitCount, Subsystem: "mcp", Description: "MCP tool failures"},
	{Name: "mcp.rpc.requests", Unit: UnitCount, Subsystem: "mcp", Description: "JSON-RPC requests sent to MCP server"},

	// --- Skills ---
	{Name: "executor.skills.invoked", Unit: UnitCount, Subsystem: "executor", Description: "Skill action invocations"},
	{Name: "executor.skills.errors", Unit: UnitCount, Subsystem: "executor", Description: "Skill load/list failures"},

	// --- Stream ---
	{Name: "stream.chunks.emitted", Unit: UnitCount, Subsystem: "stream", Description: "Output chunks to operator"},
	{Name: "stream.sse.frames", Unit: UnitCount, Subsystem: "stream", Description: "SSE frames emitted"},
	{Name: "stream.ndjson.lines", Unit: UnitCount, Subsystem: "stream", Description: "NDJSON lines emitted"},

	// --- Safety ---
	{Name: "safety.guard.evaluations", Unit: UnitCount, Subsystem: "safety", Description: "Safety Guard evaluations"},
	{Name: "safety.guard.denials", Unit: UnitCount, Subsystem: "safety", Description: "Safety Guard denials"},

	// --- Storage / transport ---
	{Name: "storage.sql.queries", Unit: UnitCount, Subsystem: "storage", Description: "SQLite queries executed"},
	{Name: "storage.sql.errors", Unit: UnitCount, Subsystem: "storage", Description: "SQLite query failures"},
	{Name: "http.requests.total", Unit: UnitCount, Subsystem: "http", Description: "HTTP requests (LLM transport)"},
	{Name: "http.requests.errors", Unit: UnitCount, Subsystem: "http", Description: "HTTP request failures"},

	// --- Bus ---
	{Name: "bus.events.published", Unit: UnitCount, Subsystem: "bus", Description: "Agent bus events published"},
}

// Find locates a metric definition by its exact name.
func Find(name string) *Def {
	for i := range All {
		if All[i].Name == name {
			return &All[i]
		}
	}
	return nil
}

// UnitFor returns the unit for the metric name or UnitCount as fallback.
func UnitFor(name string) Unit {
	if def := Find(name); def != nil {
		return def.Unit
	}
	return UnitCount
}
