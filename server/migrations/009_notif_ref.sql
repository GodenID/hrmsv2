-- fase 6b: tautan notifikasi -> pengajuan spesifik (deep link)

ALTER TABLE notifications ADD COLUMN IF NOT EXISTS ref_type TEXT;
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS ref_id TEXT;
