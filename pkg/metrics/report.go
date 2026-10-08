package metrics

import (
	"encoding/json"
	"fmt"
	"io"
	"strconv"
	"strings"
)

// DbTotals stores table record counts.
type DbTotals struct {
	Artifacts      int64 `json:"artifacts"`
	AuditLog       int64 `json:"audit_log"`
	EpisodicMemory int64 `json:"episodic_memory"`
	SessionTurns   int64 `json:"session_turns"`
	AgentEvents    int64 `json:"agent_events"`
	MetricRuns     int64 `json:"metric_runs"`
	MetricSamples  int64 `json:"metric_samples"`
}

// LoadDbTotals counts rows in core SQLite tables.
func LoadDbTotals(st Store) (DbTotals, error) {
	var t DbTotals
	if st == nil {
		return t, nil
	}

	t.Artifacts = queryCount(st, "SELECT COUNT(*) FROM artifacts;")
	t.AuditLog = queryCount(st, "SELECT COUNT(*) FROM audit_log;")
	t.EpisodicMemory = queryCount(st, "SELECT COUNT(*) FROM episodic_memory;")
	t.SessionTurns = queryCount(st, "SELECT COUNT(*) FROM session_turns;")
	t.AgentEvents = queryCount(st, "SELECT COUNT(*) FROM agent_events;")
	t.MetricSamples = queryCount(st, "SELECT COUNT(*) FROM metric_samples;")
	t.MetricRuns = queryCount(st, "SELECT COUNT(*) FROM metric_runs;")

	return t, nil
}

func queryCount(st Store, sql string) int64 {
	out, err := st.QuerySQL(sql)
	if err != nil {
		return 0
	}
	val, err := strconv.ParseInt(strings.TrimSpace(out), 10, 64)
	if err != nil {
		return 0
	}
	return val
}

// PrintHuman formats operational metrics and database totals for the terminal.
func PrintHuman(w io.Writer, m *Metrics, db DbTotals) error {
	runID := ""
	cmd := ""
	if m != nil {
		runID = m.RunID
		cmd = m.Command
	}

	_, _ = fmt.Fprintf(w, "T.A.R.S. operational report\n")
	_, _ = fmt.Fprintf(w, "  run_id:   %s\n", runID)
	_, _ = fmt.Fprintf(w, "  command:  %s\n\n", cmd)

	lastSub := ""
	for _, def := range All {
		if def.Subsystem != lastSub {
			lastSub = def.Subsystem
			_, _ = fmt.Fprintf(w, "[%s]\n", def.Subsystem)
		}
		val := 0.0
		if m != nil {
			val = m.Value(def.Name)
		}
		_, _ = fmt.Fprintf(w, "  %s: %.3f %s  — %s\n", def.Name, val, def.Unit.Name(), def.Description)
	}

	_, _ = fmt.Fprintf(w, "\n[database totals]\n")
	_, _ = fmt.Fprintf(w, "  artifacts:       %d\n", db.Artifacts)
	_, _ = fmt.Fprintf(w, "  audit_log:       %d\n", db.AuditLog)
	_, _ = fmt.Fprintf(w, "  episodic_memory: %d\n", db.EpisodicMemory)
	_, _ = fmt.Fprintf(w, "  session_turns:   %d\n", db.SessionTurns)
	_, _ = fmt.Fprintf(w, "  agent_events:    %d\n", db.AgentEvents)
	_, _ = fmt.Fprintf(w, "  metric_runs:     %d\n", db.MetricRuns)
	_, _ = fmt.Fprintf(w, "  metric_samples:  %d\n", db.MetricSamples)

	return nil
}

type reportJSONMetric struct {
	Name        string  `json:"name"`
	Subsystem   string  `json:"subsystem"`
	Unit        string  `json:"unit"`
	Value       float64 `json:"value"`
	Description string  `json:"description"`
}

type reportJSONPayload struct {
	RunID    string             `json:"run_id"`
	Command  string             `json:"command"`
	Metrics  []reportJSONMetric `json:"metrics"`
	Database DbTotals           `json:"database"`
}

// PrintJSON prints machine-readable operational report.
func PrintJSON(w io.Writer, m *Metrics, db DbTotals) error {
	runID := ""
	cmd := ""
	if m != nil {
		runID = m.RunID
		cmd = m.Command
	}

	metricsList := make([]reportJSONMetric, 0, len(All))
	for _, def := range All {
		val := 0.0
		if m != nil {
			val = m.Value(def.Name)
		}
		metricsList = append(metricsList, reportJSONMetric{
			Name:        def.Name,
			Subsystem:   def.Subsystem,
			Unit:        def.Unit.Name(),
			Value:       val,
			Description: def.Description,
		})
	}

	payload := reportJSONPayload{
		RunID:    runID,
		Command:  cmd,
		Metrics:  metricsList,
		Database: db,
	}

	data, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	_, err = fmt.Fprint(w, string(data))
	return err
}

// PrintHistory renders the last 20 persisted metric runs.
func PrintHistory(st Store, w io.Writer) error {
	if st == nil {
		return nil
	}

	sql := `SELECT r.id || '  ' || r.command || '  samples=' || COUNT(s.id) || ' sum=' || COALESCE(SUM(s.value), 0)
FROM metric_runs r
LEFT JOIN metric_samples s ON s.run_id = r.id
GROUP BY r.id
ORDER BY r.started_at DESC
LIMIT 20;`

	out, err := st.QuerySQL(sql)
	if err != nil {
		return nil
	}

	_, _ = fmt.Fprintf(w, "\n[metric run history — last 20]\n")
	for _, line := range strings.Split(out, "\n") {
		trimmed := strings.TrimSpace(line)
		if trimmed != "" {
			_, _ = fmt.Fprintf(w, "  %s\n", trimmed)
		}
	}
	return nil
}
