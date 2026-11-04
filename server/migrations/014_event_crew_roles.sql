-- Bagian crew event menjadi master data: Super Admin dapat menambah dan
-- menghapus bagian. Kode tetap disimpan di event_crew agar data lama tidak
-- berubah saat label diedit.
--
-- Hanya mengisi tabel yang masih kosong: runner migrasi menjalankan ulang
-- semua berkas setiap server mulai, jadi bagian yang sudah dihapus tidak
-- boleh ditanam kembali.
CREATE TABLE IF NOT EXISTS event_crew_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL,
  note_hint TEXT NOT NULL DEFAULT 'Tambahkan keterangan bila perlu',
  requires_note BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO event_crew_roles(code, label, note_hint, requires_note, sort_order)
SELECT v.code, v.label, v.note_hint, v.requires_note, v.sort_order
FROM (VALUES
  ('crew', 'Crew', 'mis. Crew panggung, crew logistik', FALSE, 1),
  ('pic', 'PIC', 'mis. PIC Venue, PIC Talent, PIC Konsumsi', TRUE, 2),
  ('pm', 'PM', 'mis. Project manager utama', FALSE, 3),
  ('sla', 'SLA', 'Tambahkan keterangan bila perlu', FALSE, 4),
  ('slb', 'SLB', 'Tambahkan keterangan bila perlu', FALSE, 5),
  ('slc', 'SLC', 'Tambahkan keterangan bila perlu', FALSE, 6),
  ('design', 'Design', 'mis. Desain panggung, materi publikasi', FALSE, 7)
) AS v(code, label, note_hint, requires_note, sort_order)
WHERE NOT EXISTS (SELECT 1 FROM event_crew_roles);
