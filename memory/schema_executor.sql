-- Executor step checkpoints — backup + retry/rollback metadata per mission step
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS executor_checkpoints (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  mission_id      TEXT NOT NULL,
  step_index      INTEGER NOT NULL,
  action_kind     TEXT NOT NULL,
  action_payload  TEXT NOT NULL,
  backup_dir      TEXT,
  backup_meta     TEXT NOT NULL DEFAULT '{}',
  result_json     TEXT,
  status          TEXT NOT NULL CHECK (status IN ('pending', 'completed', 'failed', 'rolled_back')),
  created_at      INTEGER NOT NULL,
  UNIQUE (mission_id, step_index)
);

CREATE INDEX IF NOT EXISTS idx_executor_ckpt_mission
  ON executor_checkpoints (mission_id, step_index);
