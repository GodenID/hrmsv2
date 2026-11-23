-- Partisipan event multi-hari bisa memilih hari yang diikuti.
-- Tanpa baris di tabel ini berarti mengikuti semua hari event (data lama).
CREATE TABLE IF NOT EXISTS event_crew_dates (
  event_id UUID NOT NULL,
  username TEXT NOT NULL,
  date DATE NOT NULL,
  PRIMARY KEY (event_id, username, date),
  FOREIGN KEY (event_id, username)
    REFERENCES event_crew(event_id, username) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS event_crew_dates_event_idx
  ON event_crew_dates(event_id);
