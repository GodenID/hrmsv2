-- fase 3: absensi (lokasi, records, koreksi, luar-area)

CREATE TABLE IF NOT EXISTS attendance_locations (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  latitude DOUBLE PRECISION NOT NULL CHECK (latitude BETWEEN -90 AND 90),
  longitude DOUBLE PRECISION NOT NULL CHECK (longitude BETWEEN -180 AND 180),
  radius_meters INT NOT NULL CHECK (radius_meters BETWEEN 25 AND 1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS attendance_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  clock_in TIMESTAMPTZ NULL,
  clock_in_location TEXT NULL,
  clock_out TIMESTAMPTZ NULL,
  clock_out_location TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id, date)
);
CREATE INDEX IF NOT EXISTS attendance_records_user_date_idx
  ON attendance_records(user_id, date);

CREATE TABLE IF NOT EXISTS attendance_corrections (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  clock_in TIMESTAMPTZ NOT NULL,
  clock_out TIMESTAMPTZ NOT NULL,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_by TEXT NULL,
  reviewed_at TIMESTAMPTZ NULL,
  reviewer_note TEXT NULL
);
CREATE INDEX IF NOT EXISTS corrections_user_date_idx
  ON attendance_corrections(user_id, date);

CREATE TABLE IF NOT EXISTS out_of_area_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  kind TEXT NOT NULL CHECK (kind IN ('clockIn','clockOut')),
  requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  accuracy_meters DOUBLE PRECISION NULL,
  nearest_location TEXT NOT NULL,
  distance_meters DOUBLE PRECISION NOT NULL,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','cancelled')),
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewed_by TEXT NULL,
  reviewed_at TIMESTAMPTZ NULL,
  reviewer_note TEXT NULL
);
CREATE INDEX IF NOT EXISTS ooa_user_date_idx
  ON out_of_area_requests(user_id, date);
