-- fase 7: onboarding oleh superadmin (ganti daftar mandiri).
-- Akun bulk/single dibuat tanpa identitas lengkap; NIK/email/telepon
-- boleh kosong sampai karyawan melengkapi saat login pertama.
-- UNIQUE tetap: NULL boleh ganda di Postgres.

ALTER TABLE users ALTER COLUMN nik DROP NOT NULL;
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;
ALTER TABLE users ALTER COLUMN phone DROP NOT NULL;
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS must_change_password BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS profile_complete BOOLEAN NOT NULL DEFAULT TRUE;
