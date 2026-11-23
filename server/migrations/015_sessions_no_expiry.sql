-- Sesi tidak kedaluwarsa sendiri: hanya logout manual / pencabutan admin.
-- Token lama memang punya klaim exp 30 hari, tetapi verifyJwt melewati
-- pengecekan exp dan baris sessions di DB yang berlaku.
UPDATE sessions
SET expires_at = TIMESTAMPTZ '9999-12-31 23:59:59+00'
WHERE revoked_at IS NULL
  AND expires_at < TIMESTAMPTZ '9999-12-31 23:59:59+00';
