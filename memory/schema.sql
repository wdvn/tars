-- tars memory schema
-- Requires: SQLite 3.45+
-- Vector search: load sqlite-vector extension before schema_vector.sql
-- See: memory/init.sh

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

-- ---------------------------------------------------------------------------
-- Session parameters (optional persistence across restarts)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS session_params (
  key         TEXT PRIMARY KEY,
  value       REAL NOT NULL,
  updated_at  INTEGER NOT NULL
);

-- ---------------------------------------------------------------------------
-- Missions
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS missions (
  id          TEXT PRIMARY KEY,
  goal        TEXT NOT NULL,
  status      TEXT NOT NULL CHECK (status IN (
                'orient', 'assess', 'plan', 'act', 'verify', 'done', 'blocked'
              )),
  priority    TEXT NOT NULL CHECK (priority IN ('critical', 'normal', 'background')),
  constraints TEXT,  -- JSON: scope, deadline, forbidden_actions
  parent_id   TEXT REFERENCES missions(id),
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_missions_status ON missions(status);
CREATE INDEX IF NOT EXISTS idx_missions_updated ON missions(updated_at DESC);

-- ---------------------------------------------------------------------------
-- Phase artifacts (Analyst / Executor / Monitor outputs)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS artifacts (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  mission_id  TEXT NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  phase       TEXT NOT NULL CHECK (phase IN ('orient', 'assess', 'plan', 'act', 'verify')),
  agent       TEXT NOT NULL CHECK (agent IN ('analyst', 'executor', 'monitor')),
  kind        TEXT NOT NULL CHECK (kind IN (
                'problem_statement', 'classification', 'risk_report', 'plan',
                'trade_off', 'action_result', 'blocked_action', 'verify_report', 'handoff'
              )),
  payload     TEXT NOT NULL,  -- JSON
  created_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_artifacts_mission ON artifacts(mission_id, phase);
CREATE INDEX IF NOT EXISTS idx_artifacts_kind ON artifacts(mission_id, kind);

-- ---------------------------------------------------------------------------
-- Episodic memory (semantic recall via sqlite-vector on embedding column)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS episodic_memory (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  mission_id  TEXT REFERENCES missions(id) ON DELETE SET NULL,
  agent       TEXT NOT NULL CHECK (agent IN ('analyst', 'executor', 'monitor')),
  content     TEXT NOT NULL,
  embedding   BLOB,           -- FLOAT32[dimension]; NULL until embedded
  meta        TEXT,           -- JSON: project, tags, file_paths, outcome
  created_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_episodic_mission ON episodic_memory(mission_id);
CREATE INDEX IF NOT EXISTS idx_episodic_agent ON episodic_memory(agent);
CREATE INDEX IF NOT EXISTS idx_episodic_created ON episodic_memory(created_at DESC);

-- ---------------------------------------------------------------------------
-- Audit log (append-only; Monitor Agent)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_log (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  mission_id  TEXT NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  agent       TEXT NOT NULL CHECK (agent IN ('analyst', 'executor', 'monitor')),
  event       TEXT NOT NULL CHECK (event IN (
                'mission_created', 'phase_entered', 'plan_ready', 'operator_approved',
                'action_started', 'action_completed', 'action_denied',
                'verify_pass', 'verify_fail', 'loop_back', 'mission_done', 'mission_blocked'
              )),
  detail      TEXT NOT NULL,  -- JSON
  created_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_audit_mission ON audit_log(mission_id, created_at);
CREATE INDEX IF NOT EXISTS idx_audit_event ON audit_log(event);

-- ---------------------------------------------------------------------------
-- Agent bus (handoffs Analyst → Executor → Monitor)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agent_events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  mission_id  TEXT NOT NULL REFERENCES missions(id) ON DELETE CASCADE,
  from_agent  TEXT NOT NULL CHECK (from_agent IN ('analyst', 'executor', 'monitor', 'operator')),
  to_agent    TEXT NOT NULL CHECK (to_agent IN ('analyst', 'executor', 'monitor', 'operator')),
  event_type  TEXT NOT NULL CHECK (event_type IN (
                'intent_received', 'plan_ready', 'operator_approved', 'action_done',
                'verify_pass', 'verify_fail', 'loop_back', 'blocked', 'handoff'
              )),
  payload     TEXT NOT NULL,  -- JSON
  created_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_agent_events_mission ON agent_events(mission_id, created_at);

-- ---------------------------------------------------------------------------
-- Schema version
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

INSERT OR REPLACE INTO schema_meta (key, value) VALUES ('version', '1');
INSERT OR REPLACE INTO schema_meta (key, value) VALUES ('embedding_dimension', '384');
INSERT OR REPLACE INTO schema_meta (key, value) VALUES ('embedding_distance', 'COSINE');
