// Waktu dari API SELALU dikonversi ke zona lokal perangkat (WIB untuk
// pengguna di Indonesia). Server mengirim instant bertanda UTC; tanpa
// toLocal(), jam tampil mentah UTC (7 jam lebih awal).
DateTime apiDateTime(Object? v, [DateTime? fallback]) {
  DateTime? parsed;
  if (v != null && v.toString().isNotEmpty) {
    parsed = DateTime.tryParse(v.toString());
  }
  return parsed?.toLocal() ?? fallback ?? DateTime.now();
}

DateTime? apiDateTimeOpt(Object? v) {
  if (v == null || v.toString().isEmpty) return null;
  return DateTime.tryParse(v.toString())?.toLocal();
}
