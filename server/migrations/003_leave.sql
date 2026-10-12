-- fase 4: cuti & lembur

CREATE TABLE IF NOT EXISTS leave_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type TEXT NOT NULL CHECK (type IN ('annual','permission','sick','maternity')),
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  working_days INT NOT NULL,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_by TEXT NULL,
  reviewed_at TIMESTAMPTZ NULL,
  reviewer_note TEXT NULL,
  attachment_name TEXT NULL,
  attachment_size INT NULL
);
CREATE INDEX IF NOT EXISTS leave_user_idx ON leave_requests(user_id);
CREATE INDEX IF NOT EXISTS leave_user_status_idx ON leave_requests(user_id, status);

CREATE TABLE IF NOT EXISTS overtime_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  start_time TIMESTAMPTZ NOT NULL,
  end_time TIMESTAMPTZ NOT NULL,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_by TEXT NULL,
  reviewed_at TIMESTAMPTZ NULL,
  reviewer_note TEXT NULL
);
CREATE INDEX IF NOT EXISTS overtime_user_idx ON overtime_requests(user_id);
