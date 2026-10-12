-- fase 4b: file ke S3 (surat dokter + foto profil)

ALTER TABLE leave_requests ADD COLUMN IF NOT EXISTS attachment_key TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_key TEXT;
