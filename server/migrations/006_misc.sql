-- fase 5: pengumuman, event, surat peringatan

CREATE TABLE IF NOT EXISTS announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  author_username CITEXT NOT NULL,
  author_name TEXT NOT NULL,
  published_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NULL,
  expires_at TIMESTAMPTZ NULL,
  pinned BOOLEAN NOT NULL DEFAULT FALSE,
  target_divisions TEXT NOT NULL DEFAULT '',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS announcement_attachments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  announcement_id UUID NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  size_bytes INT NOT NULL,
  s3_key TEXT NULL
);
CREATE INDEX IF NOT EXISTS ann_att_ann_idx ON announcement_attachments(announcement_id);

CREATE TABLE IF NOT EXISTS announcement_views (
  announcement_id UUID NOT NULL REFERENCES announcements(id) ON DELETE CASCADE,
  username CITEXT NOT NULL,
  viewed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (announcement_id, username)
);

CREATE TABLE IF NOT EXISTS event_categories (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE
);
INSERT INTO event_categories(id, name) VALUES
  ('EC-1','Employee Gathering'),
  ('EC-2','Family Gathering'),
  ('EC-3','Product Launch'),
  ('EC-4','Pernikahan'),
  ('EC-5','Festival'),
  ('EC-6','Workshop')
  ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  company TEXT NOT NULL,
  category_id TEXT NOT NULL REFERENCES event_categories(id),
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  location TEXT NOT NULL,
  po_value BIGINT NOT NULL,
  created_by TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS event_crew (
  event_id UUID NOT NULL REFERENCES events(id) ON DELETE CASCADE,
  username CITEXT NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT NOT NULL,
  note TEXT NOT NULL DEFAULT '',
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (event_id, username)
);

CREATE TABLE IF NOT EXISTS warnings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  violation_name TEXT NOT NULL,
  severity TEXT NOT NULL CHECK (severity IN ('ringan','sedang','berat')),
  level INT NOT NULL CHECK (level BETWEEN 1 AND 3),
  incident_date DATE NOT NULL,
  description TEXT NOT NULL,
  article_ref TEXT NOT NULL,
  issued_by CITEXT NOT NULL,
  issued_by_name TEXT NOT NULL,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  acknowledged_at TIMESTAMPTZ NULL,
  acknowledged_by TEXT NULL,
  refused BOOLEAN NOT NULL DEFAULT FALSE,
  witness1 TEXT NULL,
  witness2 TEXT NULL,
  appeal TEXT NULL,
  appeal_at TIMESTAMPTZ NULL,
  appeal_accepted BOOLEAN NULL,
  appeal_response_note TEXT NULL,
  appeal_responded_at TIMESTAMPTZ NULL
);
CREATE INDEX IF NOT EXISTS warnings_user_idx ON warnings(employee_user_id);
