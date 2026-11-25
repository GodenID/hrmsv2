-- Akun testing tidak ikut direktori karyawan & laporan.
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS is_testing BOOLEAN NOT NULL DEFAULT FALSE;
