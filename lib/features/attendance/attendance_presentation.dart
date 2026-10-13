import 'package:flutter/material.dart';

import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/panel.dart';
import '../../data/attendance_repository.dart';
import '../../data/leave_repository.dart';

/// Tampilan status harian. Hari normal (tepat waktu) sengaja tanpa chip
/// agar hari yang bermasalah lebih menonjol.
StatusChip? attendanceChipFor(AttendanceDay day) {
  final correction = day.correction;
  if (correction != null && correction.status == RequestStatus.pending) {
    return const StatusChip(label: 'Koreksi diajukan', tone: ChipTone.neutral);
  }
  final leave = day.leave;
  if (leave != null) {
    return StatusChip(label: leave.type.label, tone: ChipTone.accent);
  }
  return switch (day.status) {
    AttendanceDayStatus.onTime => null,
    AttendanceDayStatus.late => const StatusChip(
      label: 'Terlambat',
      tone: ChipTone.warning,
    ),
    AttendanceDayStatus.incomplete => const StatusChip(
      label: 'Tidak clock out',
      tone: ChipTone.danger,
    ),
    AttendanceDayStatus.absent => const StatusChip(
      label: 'Tidak hadir',
      tone: ChipTone.danger,
    ),
    AttendanceDayStatus.leave => StatusChip(
      label: day.leaveLabel ?? 'Cuti',
      tone: ChipTone.accent,
    ),
    AttendanceDayStatus.inProgress => const StatusChip(
      label: 'Sedang bekerja',
      tone: ChipTone.accent,
    ),
    AttendanceDayStatus.notYet => const StatusChip(
      label: 'Belum clock in',
      tone: ChipTone.neutral,
    ),
    AttendanceDayStatus.upcoming => const StatusChip(
      label: 'Akan datang',
      tone: ChipTone.neutral,
    ),
    AttendanceDayStatus.dayOff => const StatusChip(
      label: 'Libur',
      tone: ChipTone.neutral,
    ),
  };
}

ChipTone requestTone(RequestStatus status) => switch (status) {
  RequestStatus.pending => ChipTone.warning,
  RequestStatus.approved => ChipTone.success,
  RequestStatus.rejected => ChipTone.danger,
  RequestStatus.cancelled => ChipTone.neutral,
};

// -----------------------------------------------------------------------------
// Kalender
// -----------------------------------------------------------------------------

/// Palet kalender absensi (sengaja terpisah dari palet aplikasi: hanya
/// empat warna status).
abstract final class _CalendarPalette {
  static const Color green = Color(0xFF22C55E);
  static const Color greenFill = Color(0xFFD9F5E3);
  static const Color greenInk = Color(0xFF14632F);
  static const Color greenInkDark = Color(0xFF86EFAC);

  static const Color blue = Color(0xFF3B82F6);
  static const Color blueFill = Color(0xFFDCE9FE);
  static const Color blueInk = Color(0xFF1E429F);
  static const Color blueInkDark = Color(0xFF93C5FD);

  static const Color red = Color(0xFFEF4444);
  static const Color redFill = Color(0xFFFDE0E0);
  static const Color redInk = Color(0xFF9B1C1C);
  static const Color redInkDark = Color(0xFFFCA5A5);

  static const Color grey = Color(0xFF94A3B8);
  static const Color greyFill = Color(0xFFE8ECF1);
  static const Color greyInk = Color(0xFF475569);
  static const Color greyInkDark = Color(0xFFCBD5E1);
}
/// Kategori warna satu tanggal di kalender absensi.
enum CalendarTone {
  present('Hadir'),
  annualLeave('Cuti'),
  permission('Izin'),
  sick('Sakit'),
  missing('Belum absen'),
  upcoming('Akan datang'),
  off('Libur');

  const CalendarTone(this.label);

  final String label;

  /// Warna dasar (aksen) tiap kategori. Kalender hanya memakai empat warna:
  /// hijau = hadir, biru = cuti / izin, merah = sakit, abu-abu = belum absen.
  Color accentOf(BuildContext context) => switch (this) {
    present => _CalendarPalette.green,
    annualLeave || permission => _CalendarPalette.blue,
    sick => _CalendarPalette.red,
    missing => _CalendarPalette.grey,
    upcoming || off => context.borderStrong,
  };

  Color fillOf(BuildContext context) {
    final dark = context.isDark;
    return switch (this) {
      present => dark ? _CalendarPalette.green.withValues(alpha: 0.24) : _CalendarPalette.greenFill,
      annualLeave ||
      permission => dark ? _CalendarPalette.blue.withValues(alpha: 0.26) : _CalendarPalette.blueFill,
      sick => dark ? _CalendarPalette.red.withValues(alpha: 0.26) : _CalendarPalette.redFill,
      missing => dark ? _CalendarPalette.grey.withValues(alpha: 0.22) : _CalendarPalette.greyFill,
      upcoming || off => Colors.transparent,
    };
  }

  /// Garis tepi hanya dipakai untuk pengajuan yang masih menunggu.
  Color borderOf(BuildContext context) => switch (this) {
    upcoming || off => Colors.transparent,
    _ => accentOf(context).withValues(alpha: 0.35),
  };

  Color inkOf(BuildContext context) {
    final dark = context.isDark;
    return switch (this) {
      present => dark ? _CalendarPalette.greenInkDark : _CalendarPalette.greenInk,
      annualLeave ||
      permission => dark ? _CalendarPalette.blueInkDark : _CalendarPalette.blueInk,
      sick => dark ? _CalendarPalette.redInkDark : _CalendarPalette.redInk,
      missing => dark ? _CalendarPalette.greyInkDark : _CalendarPalette.greyInk,
      upcoming => context.ink,
      off => context.inkTertiary,
    };
  }
  static CalendarTone forLeave(LeaveType type) => switch (type) {
    LeaveType.annual || LeaveType.maternity => annualLeave,
    LeaveType.permission => permission,
    LeaveType.sick => sick,
  };
}

/// Penanda kecil di sudut tanggal. Tidak punya warna sendiri: memakai warna
/// kategori tanggalnya.
enum CalendarFlag {
  late('Terlambat'),
  overtime('Lembur'),
  needsCorrection('Perlu koreksi');

  const CalendarFlag(this.label);

  final String label;
}
/// Cara satu tanggal digambar di kalender.
class CalendarLook {
  const CalendarLook({
    required this.tone,
    this.pending = false,
    this.caption,
    this.flags = const [],
  });

  final CalendarTone tone;

  /// Pengajuan masih menunggu persetujuan (digambar berarsir).
  final bool pending;

  /// Keterangan singkat di sel lebar, mis. "08:05–17:12" / "Cuti tahunan".
  final String? caption;
  final List<CalendarFlag> flags;
}

/// [day] null = tidak ada data (akhir pekan, tanggal mendatang tanpa
/// pengajuan, atau sebelum tanggal bergabung).
CalendarLook calendarLookFor(
  AttendanceDay? day, {
  required DateTime date,
  required DateTime today,
}) {
  if (day == null) {
    final future = date.isAfter(today);
    final weekend =
        date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
    return CalendarLook(
      tone: future && !weekend ? CalendarTone.upcoming : CalendarTone.off,
    );
  }

  // Hanya satu penanda (tanpa warna tambahan): hari tanpa catatan lengkap.
  final flags = [if (day.needsAttention) CalendarFlag.needsCorrection];

  final leave = day.leave;
  if (leave != null) {
    final pending = leave.status == RequestStatus.pending;
    return CalendarLook(
      tone: CalendarTone.forLeave(leave.type),
      pending: pending,
      caption: pending ? '${leave.type.label} · menunggu' : leave.type.label,
    );
  }

  final clockIn = day.clockIn;
  if (clockIn != null) {
    final out = day.clockOut;
    return CalendarLook(
      tone: CalendarTone.present,
      caption:
          '${DateFormatId.time(clockIn)}–'
          '${out == null ? '…' : DateFormatId.time(out)}',
      flags: flags,
    );
  }

  return switch (day.status) {
    AttendanceDayStatus.upcoming => const CalendarLook(
      tone: CalendarTone.upcoming,
    ),
    AttendanceDayStatus.dayOff => const CalendarLook(tone: CalendarTone.off),
    AttendanceDayStatus.notYet => const CalendarLook(
      tone: CalendarTone.missing,
      caption: 'Belum absen',
    ),
    _ => CalendarLook(
      tone: CalendarTone.missing,
      caption: 'Belum absen',
      flags: flags,
    ),
  };
}

/// Kalimat untuk pembaca layar, mis.
/// "Senin, 5 Oktober 2026. Hadir 08:05 sampai 17:12. Terlambat."
String calendarSemanticsLabel(DateTime date, CalendarLook look) {
  final parts = <String>[DateFormatId.longDate(date)];
  final caption = look.caption;
  switch (look.tone) {
    case CalendarTone.present:
      final c = caption ?? '';
      parts.add(
        c.endsWith('…')
            ? 'Hadir sejak ${c.split('–').first}, belum clock out'
            : 'Hadir ${c.replaceAll('–', ' sampai ')}',
      );
    case CalendarTone.annualLeave:
    case CalendarTone.permission:
    case CalendarTone.sick:
      parts.add(
        look.pending
            ? '${look.tone.label}, menunggu persetujuan'
            : '${look.tone.label}, disetujui',
      );
    case CalendarTone.missing:
      parts.add(caption ?? 'Belum absen');
    case CalendarTone.upcoming:
      parts.add('Belum ada catatan');
    case CalendarTone.off:
      parts.add('Libur');
  }
  for (final f in look.flags) {
    parts.add(f.label);
  }
  return '${parts.join('. ')}.';
}
