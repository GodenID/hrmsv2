-- fase 9: divisi & jabatan jadi master data, kuota cuti bisa disesuaikan
-- per karyawan, dan field "atasan langsung" dihapus.
--
-- Catatan: persetujuan TIDAK memakai manager_username. Wewenang menyetujui
-- ditentukan oleh role (manager menyetujui staff), jadi menghapus kolom ini
-- tidak mengubah alur persetujuan.

CREATE TABLE IF NOT EXISTS divisions (
  code TEXT PRIMARY KEY
    CHECK (code ~ '^[a-z][A-Za-z0-9]{1,39}$'),
  label TEXT NOT NULL
    CHECK (char_length(btrim(label)) BETWEEN 2 AND 60),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO divisions(code, label) VALUES
  ('financeAccounting', 'Finance & Accounting'),
  ('hrIt', 'HR & IT'),
  ('businessDevelopment', 'Business Development'),
  ('produksiPrasasti', 'Produksi Prasasti'),
  ('produksiMutiari', 'Produksi Mutiari')
ON CONFLICT (code) DO NOTHING;

-- Divisi lama di luar daftar resmi tetap dipertahankan agar data karyawan
-- tidak kehilangan rujukan. Nilai yang tidak memenuhi format kode dilewati
-- agar migrasi tidak gagal; server memakai nilai mentah sebagai label.
INSERT INTO divisions(code, label)
SELECT DISTINCT division, division FROM users
WHERE btrim(division) <> '' AND division ~ '^[a-z][A-Za-z0-9]{1,39}$'
ON CONFLICT (code) DO NOTHING;

CREATE TABLE IF NOT EXISTS positions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 2 AND 60),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS positions_name_idx ON positions(lower(btrim(name)));

-- Jabatan yang sudah dipakai karyawan otomatis jadi isi awal master.
INSERT INTO positions(name) VALUES ('Staf') ON CONFLICT DO NOTHING;
INSERT INTO positions(name)
SELECT DISTINCT btrim(position) FROM users WHERE btrim(position) <> ''
ON CONFLICT DO NOTHING;

-- Penyesuaian kuota cuti tahunan per karyawan per tahun.
-- Hanya pengurangan (days < 0); kuota dasar tetap 12 hari di kode.
CREATE TABLE IF NOT EXISTS leave_quota_adjustments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  year INT NOT NULL CHECK (year BETWEEN 2000 AND 2100),
  days INT NOT NULL CHECK (days < 0 AND days >= -365),
  note TEXT NOT NULL CHECK (char_length(btrim(note)) >= 5),
  created_by CITEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS leave_quota_adjustment_user_idx
  ON leave_quota_adjustments(user_id, year);

-- Atasan langsung dihapus: wewenang menyetujui murni berbasis role.
ALTER TABLE users DROP COLUMN IF EXISTS manager_username;
