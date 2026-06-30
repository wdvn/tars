-- Operational metrics — time-series samples per process run

CREATE TABLE IF NOT EXISTS metric_runs (
  id          TEXT PRIMARY KEY,
  command     TEXT NOT NULL,
  started_at  INTEGER NOT NULL,
  finished_at INTEGER,
  meta        TEXT DEFAULT '{}'  -- JSON: provider, mission_id, etc.
);

CREATE TABLE IF NOT EXISTS metric_samples (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id      TEXT NOT NULL REFERENCES metric_runs(id) ON DELETE CASCADE,
  metric      TEXT NOT NULL,
  value       REAL NOT NULL,
  unit        TEXT NOT NULL DEFAULT 'count',
  tags        TEXT DEFAULT '{}',
  created_at  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_metric_samples_run ON metric_samples(run_id, metric);
CREATE INDEX IF NOT EXISTS idx_metric_samples_name ON metric_samples(metric, created_at DESC);

INSERT OR REPLACE INTO schema_meta (key, value) VALUES ('metrics_schema', '1');
