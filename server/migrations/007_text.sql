-- fase 5b: CITEXT -> TEXT di semua tabel. Driver Postgres Dart tidak bisa
-- decode tipe citext (dikembalikan mentah sebagai UndecodedBytes) sehingga
-- semua baca username/email crash. Aplikasi selalu lower-case di semua
-- batas, jadi TEXT + UNIQUE setara dan aman.
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_manager_username_fkey;
ALTER TABLE users
  ALTER COLUMN username TYPE TEXT,
  ALTER COLUMN email TYPE TEXT,
  ALTER COLUMN manager_username TYPE TEXT;
ALTER TABLE users ADD CONSTRAINT users_manager_username_fkey
  FOREIGN KEY (manager_username) REFERENCES users(username) ON DELETE SET NULL;
ALTER TABLE login_attempts ALTER COLUMN username TYPE TEXT;
ALTER TABLE notifications ALTER COLUMN username TYPE TEXT;
ALTER TABLE announcements ALTER COLUMN author_username TYPE TEXT;
ALTER TABLE announcement_views ALTER COLUMN username TYPE TEXT;
ALTER TABLE event_crew ALTER COLUMN username TYPE TEXT;
ALTER TABLE warnings ALTER COLUMN issued_by TYPE TEXT;
