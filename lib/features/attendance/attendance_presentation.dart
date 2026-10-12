import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
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

  Color fillOf(BuildContext context) {
    if (!context.isDark) {
      return switch (this) {
        present => AppColors.presentFill,
        annualLeave => AppColors.annualLeaveFill,
        permission => AppColors.permissionFill,
        sick => AppColors.sickFill,
        missing => AppColors.missingFill,
        upcoming || off => Colors.white,
      };
    }
    return switch (this) {
      present => context.presentFill,
      annualLeave => context.leaveFill,
      permission => context.permitFill,
      sick => context.sickFill,
      missing => context.missingFill,
      upcoming || off => context.surface,
    };
  }

  Color borderOf(BuildContext context) {
    if (!context.isDark) {
      return switch (this) {
        present => AppColors.presentBorder,
        annualLeave => AppColors.annualLeaveBorder,
        permission => AppColors.permissionBorder,
        sick => AppColors.sickBorder,
        missing => AppColors.missingBorder,
        upcoming => AppColors.border,
        off => Colors.transparent,
      };
    }
    return switch (this) {
      present => context.success.withValues(alpha: 0.55),
      annualLeave => context.accentText.withValues(alpha: 0.55),
      permission => context.accentText.withValues(alpha: 0.55),
      sick => context.danger.withValues(alpha: 0.45),
      missing => context.borderStrong,
      upcoming => context.border,
      off => Colors.transparent,
    };
  }

  Color inkOf(BuildContext context) {
    if (!context.isDark) {
      return switch (this) {
        present => AppColors.presentInk,
        annualLeave => AppColors.annualLeaveInk,
        permission => AppColors.permissionInk,
        sick => AppColors.sickInk,
        missing => AppColors.inkSecondary,
        upcoming => AppColors.ink,
        off => AppColors.inkTertiary,
      };
    }
    return switch (this) {
      present => context.success,
      annualLeave => context.accentText,
      permission => context.accentText,
      sick => context.danger,
      missing => context.inkSecondary,
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

/// Penanda kecil di sudut tanggal.
enum CalendarFlag {
  late('Terlambat'),
  overtime('Lembur'),
  needsCorrection('Perlu koreksi');

  const CalendarFlag(this.label);

  final String label;

  Color colorOf(BuildContext context) => switch (this) {
    CalendarFlag.late => AppColors.warningIndicator,
    CalendarFlag.overtime => context.overtimeTint,
    CalendarFlag.needsCorrection => context.danger,
  };
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

  final flags = [
    if (day.status == AttendanceDayStatus.late) CalendarFlag.late,
    if (day.overtime != null) CalendarFlag.overtime,
    if (day.needsAttention) CalendarFlag.needsCorrection,
  ];

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
      caption: 'Tidak hadir',
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
