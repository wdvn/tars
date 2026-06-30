-- Multi-turn sessions (operator ↔ T.A.R.S. crew)

CREATE TABLE IF NOT EXISTS sessions (
  id          TEXT PRIMARY KEY,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  summary     TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS session_turns (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id  TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
  role        TEXT NOT NULL CHECK (role IN ('operator', 'analyst', 'executor', 'monitor', 'system')),
  content     TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_session_turns_session ON session_turns(session_id, created_at);

INSERT OR REPLACE INTO schema_meta (key, value) VALUES ('session_schema', '1');
