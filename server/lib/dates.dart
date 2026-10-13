// Cermin WorkCalendar Flutter (periode & hari kerja Senin–Jumat).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
bool isWeekend(DateTime d) => d.weekday == 6 || d.weekday == 7;

int workingDaysBetween(DateTime s, DateTime e) {
  var day = dateOnly(s);
  final last = dateOnly(e);
  if (last.isBefore(day)) return 0;
  var n = 0;
  while (!day.isAfter(last)) {
    if (!isWeekend(day)) n++;
    day = DateTime(day.year, day.month, day.day + 1);
  }
  return n;
}

DateTime addMonths(DateTime date, int months) {
  final total = (date.month - 1) + months;
  final year = date.year + total ~/ 12;
  final month = total % 12 + 1;
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, date.day.clamp(1, lastDay));
}

/// Jam server dipakai sebagai WIB.
DateTime nowWib() => DateTime.now().toUtc().add(const Duration(hours: 7));

/// Emit waktu ke JSON: SELALU bertanda UTC. Driver Postgres mengembalikan
/// waktu lokal-naif (jam UTC tanpa 'Z'); tanpa toUtc(), Flutter membaca
/// jam UTC sebagai jam lokal (WIB) sehingga semua tampil 7 jam lebih awal.
String isoUtc(DateTime d) => d.toUtc().toIso8601String();

String? isoUtcOpt(DateTime? d) => d?.toUtc().toIso8601String();

/// Terlambat = clock in lewat 09.00 WIB. Selalu konversi ke WIB dulu:
/// container server berjalan di UTC sehingga .hour langsung / .toLocal()
/// SALAH (tidak ada yang pernah terlambat).
bool isLate(DateTime clockIn) {
  final wib = clockIn.toUtc().add(const Duration(hours: 7));
  return wib.hour > 9 ||
      (wib.hour == 9 && (wib.minute > 0 || wib.second > 0));
}
