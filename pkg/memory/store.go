package memory

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/wdvn/tars/pkg/metrics"
)

const (
	DefaultDBPath = ".tars/tars.db"
)

// Store manages SQLite file storage via sqlite3 CLI.
type Store struct {
	dbPath string
}

// NewStore initializes a Store instance.
func NewStore(dbPath string) *Store {
	if dbPath == "" {
		dbPath = DefaultDBPath
	}
	return &Store{dbPath: dbPath}
}

// ApplySchema initializes or updates the database schema via memory/init.sh.
func (s *Store) ApplySchema() error {
	cmd := exec.Command("bash", "memory/init.sh")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("failed to apply schema: %w (output: %s)", err, string(out))
	}
	return nil
}

// QuerySQL runs a SQL statement against SQLite and returns stdout.
func (s *Store) QuerySQL(sql string) (string, error) {
	metrics.GInc("storage.sql.queries", 1)

	cmd := exec.Command("sqlite3", s.dbPath, sql)
	out, err := cmd.Output()
	if err != nil {
		metrics.GInc("storage.sql.errors", 1)
		return "", fmt.Errorf("sqlite3 error: %w", err)
	}
	return string(out), nil
}

// QuerySQLText runs a SQL statement and returns trimmed text output.
func (s *Store) QuerySQLText(sql string) (string, error) {
	out, err := s.QuerySQL(sql)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

// EscapeSQL escapes single quotes for SQL literals.
func EscapeSQL(text string) string {
	return strings.ReplaceAll(text, "'", "''")
}

// WriteArtifact records an Analyst or Executor artifact.
func (s *Store) WriteArtifact(missionID, phase, agent, kind, payloadJSON string, createdAt int64) error {
	sql := fmt.Sprintf(
		"INSERT INTO artifacts (mission_id, phase, agent, kind, payload, created_at) VALUES ('%s', '%s', '%s', '%s', '%s', %d);",
		EscapeSQL(missionID), EscapeSQL(phase), EscapeSQL(agent), EscapeSQL(kind), EscapeSQL(payloadJSON), createdAt,
	)
	_, err := s.QuerySQL(sql)
	return err
}

// AppendAudit records an immutable audit event.
func (s *Store) AppendAudit(missionID, agent, event, detailJSON string, createdAt int64) error {
	sql := fmt.Sprintf(
		"INSERT INTO audit_log (mission_id, agent, event, detail, created_at) VALUES ('%s', '%s', '%s', '%s', %d);",
		EscapeSQL(missionID), EscapeSQL(agent), EscapeSQL(event), EscapeSQL(detailJSON), createdAt,
	)
	_, err := s.QuerySQL(sql)
	return err
}

// PublishBusEvent logs inter-agent messages.
func (s *Store) PublishBusEvent(missionID, fromAgent, toAgent, eventType, payloadJSON string, createdAt int64) error {
	sql := fmt.Sprintf(
		"INSERT INTO agent_events (mission_id, from_agent, to_agent, event_type, payload, created_at) VALUES ('%s', '%s', '%s', '%s', '%s', %d);",
		EscapeSQL(missionID), EscapeSQL(fromAgent), EscapeSQL(toAgent), EscapeSQL(eventType), EscapeSQL(payloadJSON), createdAt,
	)
	_, err := s.QuerySQL(sql)
	return err
}

// WriteEpisode records an episodic memory row with vector/metadata JSON.
func (s *Store) WriteEpisode(missionID *string, agent, content, metaJSON string, createdAt int64) error {
	var sql string
	if missionID != nil && *missionID != "" {
		sql = fmt.Sprintf(
			"INSERT INTO episodic_memory (mission_id, agent, content, meta, created_at) VALUES ('%s', '%s', '%s', '%s', %d);",
			EscapeSQL(*missionID), EscapeSQL(agent), EscapeSQL(content), EscapeSQL(metaJSON), createdAt,
		)
	} else {
		sql = fmt.Sprintf(
			"INSERT INTO episodic_memory (agent, content, meta, created_at) VALUES ('%s', '%s', '%s', %d);",
			EscapeSQL(agent), EscapeSQL(content), EscapeSQL(metaJSON), createdAt,
		)
	}
	_, err := s.QuerySQL(sql)
	return err
}

// QueryAllEpisodes returns lines containing stored episodes with embeddings.
func (s *Store) QueryAllEpisodes() (string, error) {
	sql := `SELECT id || '|' || content || '|' || COALESCE(meta, '{}') || '|' || COALESCE(json_extract(meta, '$.embedding'), '[]')
FROM episodic_memory
WHERE json_extract(meta, '$.embedding') IS NOT NULL
ORDER BY created_at DESC;`
	return s.QuerySQL(sql)
}

// CreateSession ensures a session row exists.
func (s *Store) CreateSession(sessionID string, createdAt int64) error {
	sql := fmt.Sprintf(
		"INSERT OR IGNORE INTO sessions (id, created_at, updated_at) VALUES ('%s', %d, %d);",
		EscapeSQL(sessionID), createdAt, createdAt,
	)
	_, err := s.QuerySQL(sql)
	return err
}

// AppendSessionTurn records a conversation turn and updates session timestamp.
func (s *Store) AppendSessionTurn(sessionID, role, content string, createdAt int64) error {
	sql := fmt.Sprintf(
		"INSERT INTO session_turns (session_id, role, content, created_at) VALUES ('%s', '%s', '%s', %d);\nUPDATE sessions SET updated_at = %d WHERE id = '%s';",
		EscapeSQL(sessionID), EscapeSQL(role), EscapeSQL(content), createdAt, createdAt, EscapeSQL(sessionID),
	)
	_, err := s.QuerySQL(sql)
	return err
}

// RecentSessionTurns returns raw turn lines.
func (s *Store) RecentSessionTurns(sessionID string, limit int) (string, error) {
	sql := fmt.Sprintf(
		"SELECT role || '|' || content FROM session_turns WHERE session_id = '%s' ORDER BY created_at ASC LIMIT %d;",
		EscapeSQL(sessionID), limit,
	)
	return s.QuerySQL(sql)
}

// CountSessionTurns counts turns in a session.
func (s *Store) CountSessionTurns(sessionID string) (int, error) {
	sql := fmt.Sprintf("SELECT COUNT(*) FROM session_turns WHERE session_id = '%s';", EscapeSQL(sessionID))
	txt, err := s.QuerySQLText(sql)
	if err != nil {
		return 0, err
	}
	val, err := strconv.Atoi(txt)
	if err != nil {
		return 0, nil
	}
	return val, nil
}

// GetSessionSummary returns the rolling session summary.
func (s *Store) GetSessionSummary(sessionID string) (string, error) {
	sql := fmt.Sprintf("SELECT COALESCE(summary, '') FROM sessions WHERE id = '%s';", EscapeSQL(sessionID))
	return s.QuerySQLText(sql)
}

// SetSessionSummary updates the session summary.
func (s *Store) SetSessionSummary(sessionID, summary string) error {
	sql := fmt.Sprintf(
		"UPDATE sessions SET summary = '%s', updated_at = 0 WHERE id = '%s';",
		EscapeSQL(summary), EscapeSQL(sessionID),
	)
	_, err := s.QuerySQL(sql)
	return err
}

// LoadSessionTurnsJSON loads the newest limit turns in chronological order as JSON lines.
func (s *Store) LoadSessionTurnsJSON(sessionID string, limit int) (string, error) {
	sql := fmt.Sprintf(`SELECT json_object('role', role, 'content', content) FROM (
  SELECT role, content, created_at, id FROM session_turns
  WHERE session_id = '%s'
  ORDER BY created_at DESC, id DESC
  LIMIT %d
) AS sub ORDER BY sub.created_at ASC, sub.id ASC;`, EscapeSQL(sessionID), limit)
	return s.QuerySQL(sql)
}

// BeginMetricRun registers a metric run.
func (s *Store) BeginMetricRun(runID, command string, startedAt int64, metaJSON string) error {
	sql := fmt.Sprintf(
		"INSERT OR REPLACE INTO metric_runs (id, command, started_at, meta) VALUES ('%s', '%s', %d, '%s');",
		EscapeSQL(runID), EscapeSQL(command), startedAt, EscapeSQL(metaJSON),
	)
	_, err := s.QuerySQL(sql)
	return err
}

// FinishMetricRun sets the run completion timestamp.
func (s *Store) FinishMetricRun(runID string, finishedAt int64) error {
	sql := fmt.Sprintf("UPDATE metric_runs SET finished_at = %d WHERE id = '%s';", finishedAt, EscapeSQL(runID))
	_, err := s.QuerySQL(sql)
	return err
}

// WriteMetricSample records an individual metric value.
func (s *Store) WriteMetricSample(runID, metric string, value float64, unit, tagsJSON string, createdAt int64) error {
	sql := fmt.Sprintf(
		"INSERT INTO metric_samples (run_id, metric, value, unit, tags, created_at) VALUES ('%s', '%s', %f, '%s', '%s', %d);",
		EscapeSQL(runID), EscapeSQL(metric), value, EscapeSQL(unit), EscapeSQL(tagsJSON), createdAt,
	)
	_, err := s.QuerySQL(sql)
	return err
}

// UpsertExecutorCheckpoint records a checkpoint prior to step execution.
func (s *Store) UpsertExecutorCheckpoint(missionID string, stepIndex int, actionKind, actionPayload, backupDir, backupMetaJSON string, createdAt int64) error {
	var dirClause string
	if backupDir != "" {
		dirClause = fmt.Sprintf("'%s'", EscapeSQL(backupDir))
	} else {
		dirClause = "NULL"
	}

	sql := fmt.Sprintf(`INSERT INTO executor_checkpoints
(mission_id, step_index, action_kind, action_payload, backup_dir, backup_meta, status, created_at)
VALUES ('%s', %d, '%s', '%s', %s, '%s', 'pending', %d)
ON CONFLICT(mission_id, step_index) DO UPDATE SET
  action_kind = excluded.action_kind,
  action_payload = excluded.action_payload,
  backup_dir = excluded.backup_dir,
  backup_meta = excluded.backup_meta,
  result_json = NULL,
  status = 'pending',
  created_at = excluded.created_at;`,
		EscapeSQL(missionID), stepIndex, EscapeSQL(actionKind), EscapeSQL(actionPayload), dirClause, EscapeSQL(backupMetaJSON), createdAt)
	_, err := s.QuerySQL(sql)
	return err
}

// FinishExecutorCheckpoint updates status and result upon completion.
func (s *Store) FinishExecutorCheckpoint(missionID string, stepIndex int, status, resultJSON string) error {
	var resClause string
	if resultJSON != "" {
		resClause = fmt.Sprintf("'%s'", EscapeSQL(resultJSON))
	} else {
		resClause = "NULL"
	}
	sql := fmt.Sprintf(
		"UPDATE executor_checkpoints SET status = '%s', result_json = %s WHERE mission_id = '%s' AND step_index = %d;",
		EscapeSQL(status), resClause, EscapeSQL(missionID), stepIndex,
	)
	_, err := s.QuerySQL(sql)
	return err
}

// MarkExecutorCheckpointRolledBack flags a checkpoint as rolled back.
func (s *Store) MarkExecutorCheckpointRolledBack(missionID string, stepIndex int) error {
	sql := fmt.Sprintf(
		"UPDATE executor_checkpoints SET status = 'rolled_back' WHERE mission_id = '%s' AND step_index = %d;",
		EscapeSQL(missionID), stepIndex,
	)
	_, err := s.QuerySQL(sql)
	return err
}

// QueryLatestArtifactPayload retrieves the newest artifact payload for mission + kind.
func (s *Store) QueryLatestArtifactPayload(missionID, kind string) (string, error) {
	sql := fmt.Sprintf(
		"SELECT payload FROM artifacts WHERE mission_id = '%s' AND kind = '%s' ORDER BY id DESC LIMIT 1;",
		EscapeSQL(missionID), EscapeSQL(kind),
	)
	return s.QuerySQL(sql)
}

// QueryExecutorCheckpointMeta returns backup_meta JSON for a checkpoint.
func (s *Store) QueryExecutorCheckpointMeta(missionID string, stepIndex int) (string, error) {
	sql := fmt.Sprintf(
		"SELECT COALESCE(backup_meta, '{}') FROM executor_checkpoints WHERE mission_id = '%s' AND step_index = %d LIMIT 1;",
		EscapeSQL(missionID), stepIndex,
	)
	return s.QuerySQL(sql)
}

// DefaultDBAbsolutePath resolves .tars/tars.db relative to current directory or returns default.
func DefaultDBAbsolutePath() string {
	abs, err := filepath.Abs(DefaultDBPath)
	if err == nil {
		return abs
	}
	return DefaultDBPath
}
