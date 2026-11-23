-- Produksi Mutiari boleh mengajukan lembur pagi dan malam untuk tanggal
-- yang sama. Divisi lain tetap memakai satu pengajuan biasa.
ALTER TABLE overtime_requests
  ADD COLUMN IF NOT EXISTS slot TEXT NOT NULL DEFAULT 'single'
  CHECK (slot IN ('single', 'morning', 'evening'));
