/// Format tanggal/jam Bahasa Indonesia tanpa dependensi tambahan.
abstract final class DateFormatId {
  static const List<String> _days = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  static const List<String> _months = [
    'Januari',
    'Februari',
    'Maret',
    'April',
    'Mei',
    'Juni',
    'Juli',
    'Agustus',
    'September',
    'Oktober',
    'November',
    'Desember',
  ];

  static const List<String> _monthsShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// Contoh: "Oktober 2026"
  static String monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

  /// Nama bulan penuh, mis. monthName(10) = "Oktober".
  static String monthName(int month) => _months[month - 1];

  /// Contoh: "1 Februari 2024"
  static String dayMonthYear(DateTime d) =>
      '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// Contoh: "Rab"
  static String weekdayShort(DateTime d) =>
      _days[d.weekday - 1].substring(0, 3);

  /// Contoh: "Okt"
  static String monthShort(DateTime d) => _monthsShort[d.month - 1];

  /// Contoh: "Rab, 7 Okt"
  static String dayShort(DateTime d) =>
      '${weekdayShort(d)}, ${d.day} ${_monthsShort[d.month - 1]}';

  /// Rentang tanggal ringkas:
  /// "17 Sep 2026", "17–18 Sep 2026", "30 Sep – 2 Okt 2026",
  /// "29 Des 2026 – 2 Jan 2027".
  static String dateRange(DateTime start, DateTime end) {
    if (_sameDay(start, end)) return shortDate(start);
    if (start.year == end.year && start.month == end.month) {
      return '${start.day}–${end.day} ${_monthsShort[end.month - 1]} ${end.year}';
    }
    if (start.year == end.year) {
      return '${start.day} ${_monthsShort[start.month - 1]} – ${shortDate(end)}';
    }
    return '${shortDate(start)} – ${shortDate(end)}';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Contoh: "Rabu, 7 Oktober 2026"
  static String longDate(DateTime d) {
    return '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  /// Contoh: "7 Okt 2026"
  static String shortDate(DateTime d) =>
      '${d.day} ${_monthsShort[d.month - 1]} ${d.year}';

  /// Contoh: "7 Okt 2026, 09:12"
  static String shortDateTime(DateTime d) => '${shortDate(d)}, ${time(d)}';

  /// Contoh: "08:05"
  static String time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  /// Contoh: "08:05:42"
  static String timeWithSeconds(DateTime d) => '${time(d)}:${_two(d.second)}';

  /// Contoh: "7 jam 45 menit", "12 menit", "kurang dari 1 menit"
  static String duration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    if (hours == 0 && minutes == 0) return 'kurang dari 1 menit';
    if (hours == 0) return '$minutes menit';
    if (minutes == 0) return '$hours jam';
    return '$hours jam $minutes menit';
  }

  /// Sapaan sesuai jam lokal.
  static String greeting(DateTime d) {
    final h = d.hour;
    if (h >= 4 && h < 11) return 'Selamat pagi';
    if (h >= 11 && h < 15) return 'Selamat siang';
    if (h >= 15 && h < 18) return 'Selamat sore';
    return 'Selamat malam';
  }
}
