/// Aturan kerja Prasasti Group (sementara di frontend; nantinya dari
/// Pengaturan Perusahaan / server).
abstract final class WorkPolicy {
  /// Jam kerja mulai 09.00; datang setelahnya dihitung terlambat.
  static const int latestOnTimeHour = 9;
  static const int latestOnTimeMinute = 0;

  /// Koreksi absensi hanya untuk N hari ke belakang.
  static const int correctionWindowDays = 30;
}

abstract final class WorkCalendar {
  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool isWeekend(DateTime d) =>
      d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Hari buka buku: periode absensi berjalan tiap tanggal 26–25
  /// (buka tanggal 26, tutup tanggal 25 bulan berikut).
  static const int periodOpeningDay = 26;

  /// Awal periode (tanggal 26) yang memuat [date].
  static DateTime periodStartFor(DateTime date) {
    final d = dateOnly(date);
    if (d.day >= periodOpeningDay) {
      return DateTime(d.year, d.month, periodOpeningDay);
    }
    return DateTime(d.year, d.month - 1, periodOpeningDay);
  }

  /// Akhir periode (tanggal 25 bulan berikut) yang memuat [date].
  static DateTime periodEndFor(DateTime date) {
    final s = periodStartFor(date);
    return DateTime(s.year, s.month + 1, 25);
  }

  /// Menambah [months] bulan kalender. Tanggal dijepit ke akhir bulan bila
  /// meluap (31 Jan + 1 bulan = 28/29 Feb). Dipakai menghitung akhir
  /// kontrak dari tanggal bergabung + durasi bulan.
  static DateTime addMonths(DateTime date, int months) {
    final total = (date.month - 1) + months;
    final year = date.year + total ~/ 12;
    final month = total % 12 + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, date.day.clamp(1, lastDay));
  }

  /// Jumlah hari kerja (Senin–Jumat) dari [start] s.d. [end], inklusif.
  /// Hari libur nasional belum diperhitungkan.
  static int workingDaysBetween(DateTime start, DateTime end) {
    var day = dateOnly(start);
    final last = dateOnly(end);
    if (last.isBefore(day)) return 0;
    var count = 0;
    while (!day.isAfter(last)) {
      if (!isWeekend(day)) count++;
      day = DateTime(day.year, day.month, day.day + 1);
    }
    return count;
  }
}
