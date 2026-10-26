-- fase 8: rilis APK Android untuk pembaruan otomatis di dalam aplikasi.
-- Satu baris = satu versi yang sudah terbit. Versi terbaru = version_code
-- terbesar. APK disimpan di S3 (privat) dan diunduh lewat presigned GET.

CREATE TABLE IF NOT EXISTS app_releases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  version_code INT NOT NULL CHECK (version_code > 0),
  version_name TEXT NOT NULL,
  min_version_code INT NOT NULL DEFAULT 0 CHECK (min_version_code >= 0),
  apk_key TEXT NOT NULL,
  sha256 TEXT NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  size_bytes BIGINT NOT NULL DEFAULT 0 CHECK (size_bytes >= 0),
  notes TEXT NOT NULL DEFAULT '',
  published_by CITEXT NOT NULL,
  published_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS app_releases_version_idx
  ON app_releases(version_code);
