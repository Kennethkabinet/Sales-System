-- ============================================================
-- Migration: Collaboration V2
-- Adds edit_requests table, extends audit_logs with sheet/cell
-- context, role, and department for full traceability.
-- Run once against the live database.
-- ============================================================

-- 1. Extend audit_logs with sheet-level context columns
--    (safe: all columns are nullable, no existing rows break)
ALTER TABLE audit_logs
  ADD COLUMN IF NOT EXISTS sheet_id        INTEGER REFERENCES sheets(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cell_reference  VARCHAR(20),   -- e.g. "B4"
  ADD COLUMN IF NOT EXISTS role            VARCHAR(50),   -- role at time of action
  ADD COLUMN IF NOT EXISTS department_name VARCHAR(100);  -- dept at time of action

-- Index for fast sheet-audit queries
CREATE INDEX IF NOT EXISTS idx_audit_logs_sheet_id ON audit_logs(sheet_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_cell_ref  ON audit_logs(cell_reference);

-- 2. Edit requests table
--    Editors submit a request to unlock a historically-locked inventory cell.
--    Admins approve/reject in real time.
CREATE TABLE IF NOT EXISTS edit_requests (
  id               SERIAL PRIMARY KEY,
  sheet_id         INTEGER NOT NULL REFERENCES sheets(id) ON DELETE CASCADE,
  row_number       INTEGER NOT NULL,
  column_name      VARCHAR(100) NOT NULL,
  cell_reference   VARCHAR(20),           -- e.g. "B4"
  current_value    TEXT,
  proposed_value   TEXT,
  requested_by     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  requester_role   VARCHAR(50),
  requester_dept   VARCHAR(100),
  requested_at     TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  status           VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending | approved | rejected
  reviewed_by      INTEGER REFERENCES users(id),
  reviewed_at      TIMESTAMP WITH TIME ZONE,
  reject_reason    TEXT,
  expires_at       TIMESTAMP WITH TIME ZONE, -- set when approved; auto-re-locks after
  -- Prevent duplicate pending requests for the same cell by the same user
  CONSTRAINT uq_edit_request_pending UNIQUE NULLS NOT DISTINCT
    (sheet_id, row_number, column_name, requested_by, status)
);

CREATE INDEX IF NOT EXISTS idx_edit_requests_sheet    ON edit_requests(sheet_id);
CREATE INDEX IF NOT EXISTS idx_edit_requests_status   ON edit_requests(status);
CREATE INDEX IF NOT EXISTS idx_edit_requests_requester ON edit_requests(requested_by);
