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

bool isLate(DateTime clockIn) =>
    clockIn.hour > 9 || (clockIn.hour == 9 && (clockIn.minute > 0 || clockIn.second > 0));
