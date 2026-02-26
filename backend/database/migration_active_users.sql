-- Active users heartbeat table for per-sheet presence polling
CREATE TABLE IF NOT EXISTS active_users (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sheet_id INTEGER NOT NULL REFERENCES sheets(id) ON DELETE CASCADE,
  last_active_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE (user_id, sheet_id)
);

CREATE INDEX IF NOT EXISTS idx_active_users_sheet_last_active
ON active_users (sheet_id, last_active_timestamp DESC);
