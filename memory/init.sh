#!/usr/bin/env bash
# Initialize .tars/tars.db with base schema (+ optional sqlite-vector)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB_PATH="${TARS_DB_PATH:-$ROOT/.tars/tars.db}"
VECTOR_EXT="${TARS_VECTOR_EXT:-}"

mkdir -p "$(dirname "$DB_PATH")"

echo "Initializing tars memory at: $DB_PATH"

sqlite3 "$DB_PATH" < "$ROOT/memory/schema.sql"
sqlite3 "$DB_PATH" < "$ROOT/memory/schema_session.sql"
sqlite3 "$DB_PATH" "ALTER TABLE sessions ADD COLUMN summary TEXT NOT NULL DEFAULT '';" 2>/dev/null || true
sqlite3 "$DB_PATH" < "$ROOT/memory/schema_metrics.sql"
sqlite3 "$DB_PATH" < "$ROOT/memory/schema_executor.sql"

if [[ -n "$VECTOR_EXT" && -f "$VECTOR_EXT" ]]; then
  echo "Loading sqlite-vector from: $VECTOR_EXT"
  sqlite3 "$DB_PATH" <<SQL
SELECT load_extension('$VECTOR_EXT');
.read $ROOT/memory/schema_vector.sql
SQL
  echo "Vector search enabled."
else
  echo "Skipping vector setup (set TARS_VECTOR_EXT to enable sqlite-vector)."
  echo "  Example: TARS_VECTOR_EXT=/path/to/vector.so $0"
fi

echo "Done. Schema version:"
sqlite3 "$DB_PATH" "SELECT value FROM schema_meta WHERE key = 'version';"
