-- prasasti connect, migrasi awal
-- users: satu baris per karyawan. pendaftar pertama (tabel kosong)
-- otomatis jadi superadmin di level aplikasi (lihat register handler).

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  username CITEXT UNIQUE NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'staff'
    CHECK (role IN ('staff','manager','superadmin')),
  nik VARCHAR(16) UNIQUE NOT NULL,
  employee_id VARCHAR(16) UNIQUE NOT NULL,
  position TEXT NOT NULL DEFAULT 'Staf',
  division TEXT NOT NULL,
  employment_status TEXT NOT NULL,
  contract_months INT NULL,
  join_date DATE NOT NULL,
  email CITEXT UNIQUE NOT NULL,
  phone TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  manager_username CITEXT NULL REFERENCES users(username) ON DELETE SET NULL,
  active BOOLEAN NOT NULL DEFAULT TRUE,
  gender TEXT NULL,
  birth_place TEXT NULL,
  birth_date DATE NULL,
  address TEXT NULL,
  emergency_name TEXT NULL,
  emergency_relation TEXT NULL,
  emergency_phone TEXT NULL,
  privacy_consented_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS users_username_idx ON users(username);
CREATE INDEX IF NOT EXISTS users_active_role_idx ON users(active, role);

CREATE TABLE IF NOT EXISTS sessions (
  jti UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ NULL
);
CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions(user_id);

CREATE TABLE IF NOT EXISTS password_resets (
  token_hash TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS login_attempts (
  username CITEXT PRIMARY KEY,
  failures INT NOT NULL DEFAULT 0,
  locked_until TIMESTAMPTZ NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
INSERT INTO settings(key, value) VALUES ('registration_open','true')
  ON CONFLICT (key) DO NOTHING;
