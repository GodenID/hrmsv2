-- Lembur Minggu Produksi Mutiari tidak memakai rentang jam.
ALTER TABLE overtime_requests DROP CONSTRAINT IF EXISTS overtime_requests_slot_check;
ALTER TABLE overtime_requests
  ADD CONSTRAINT overtime_requests_slot_check
  CHECK (slot IN ('single', 'morning', 'evening', 'sunday'));
