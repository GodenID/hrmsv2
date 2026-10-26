-- fase 10: entity event jadi master data ringan yang bisa ditambah Manager
-- dan Super Admin langsung dari formulir event.

CREATE TABLE IF NOT EXISTS event_entities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL CHECK (char_length(btrim(name)) BETWEEN 2 AND 80),
  active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS event_entities_name_idx
  ON event_entities(lower(btrim(name)));

-- Event lama boleh tanpa entity; event baru wajib memilih (ditegakkan di
-- formulir & server).
ALTER TABLE events ADD COLUMN IF NOT EXISTS entity_id UUID
  REFERENCES event_entities(id);

CREATE INDEX IF NOT EXISTS events_entity_idx ON events(entity_id);
