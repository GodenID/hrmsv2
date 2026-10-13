import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/work_calendar.dart';
import '../../../data/attendance_repository.dart';
import '../attendance_presentation.dart';

/// Kalender absensi per rentang tanggal (Senin-Minggu), mengikuti periode
/// buku 26-25. Hanya empat warna:
/// hijau = hadir, biru = cuti / izin, merah = sakit, abu-abu = belum absen.
/// Pengajuan yang masih menunggu digambar berarsir dengan garis tepi.
///
/// Lebar sel >= 92: tampil jam clock in-out / jenis cuti di dalam sel.
/// Lebih sempit (HP): angka tanggal saja.
class AttendanceCalendar extends StatelessWidget {
  const AttendanceCalendar({
    super.key,
    required this.start,
    required this.end,
    required this.today,
    required this.days,
    required this.onTapDay,
  });

  /// Batas rentang (inklusif), mis. 26 Sep - 25 Okt.
  final DateTime start;
  final DateTime end;
  final DateTime today;

  /// null = sedang memuat (semua sel netral, tidak bisa diketuk).
  /// Hanya tanggal sampai [today] yang bisa diketuk; tanggal mendatang tidak.
  final List<AttendanceDay>? days;
  final ValueChanged<AttendanceDay> onTapDay;

  static const _weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  static const double _gap = 6;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final byDate = <DateTime, AttendanceDay>{
      for (final d in days ?? const <AttendanceDay>[])
        WorkCalendar.dateOnly(d.date): d,
    };
    final first = WorkCalendar.dateOnly(start);
    final totalDays = WorkCalendar.dateOnly(end).difference(first).inDays + 1;
    final leading = first.weekday - 1; // Senin = 0
    final cellCount = ((leading + totalDays) / 7).ceil() * 7;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellWidth = (constraints.maxWidth - _gap * 6) / 7;
        final detailed = cellWidth >= 92;
        final cellHeight = detailed ? 80.0 : 46.0;

        final rows = <Widget>[];
        for (var rowStart = 0; rowStart < cellCount; rowStart += 7) {
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: rowStart == 0 ? 0 : _gap),
              child: Row(
                children: [
                  for (var i = rowStart; i < rowStart + 7; i++) ...[
                    if (i > rowStart) const SizedBox(width: _gap),
                    Expanded(
                      child: SizedBox(
                        height: cellHeight,
                        child: _cellAt(
                          context,
                          i - leading,
                          totalDays,
                          byDate,
                          detailed,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: detailed ? 10 : 0),
                        child: Text(
                          _weekdays[i].toUpperCase(),
                          textAlign: detailed
                              ? TextAlign.left
                              : TextAlign.center,
                          style: textTheme.labelSmall?.copyWith(
                            fontSize: 10.5,
                            letterSpacing: 0.6,
                            fontWeight: FontWeight.w600,
                            color: i >= 5
                                ? context.inkTertiary
                                : context.inkSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ...rows,
          ],
        );
      },
    );
  }

  Widget _cellAt(
    BuildContext context,
    int offset,
    int totalDays,
    Map<DateTime, AttendanceDay> byDate,
    bool detailed,
  ) {
    if (offset < 0 || offset >= totalDays) {
      return const SizedBox.shrink();
    }
    final date = WorkCalendar.dateOnly(start).add(Duration(days: offset));
    final loading = days == null;
    final day = byDate[date];
    final look = loading
        ? const CalendarLook(tone: CalendarTone.upcoming)
        : calendarLookFor(day, date: date, today: today);
    // Semua tanggal sampai hari ini bisa diketuk - termasuk akhir pekan/libur
    // dan tanggal yang tidak ada datanya dari server (mis. sebelum akun
    // dibuat) - untuk melihat catatan atau mengajukan absensi bila lupa.
    // Tanggal mendatang tidak bisa diketuk.
    final tappable =
        !loading &&
        !WorkCalendar.dateOnly(date).isAfter(WorkCalendar.dateOnly(today));
    final target =
        day ??
        AttendanceDay(
          date: date,
          status: WorkCalendar.isWeekend(date)
              ? AttendanceDayStatus.dayOff
              : AttendanceDayStatus.absent,
        );
    return _DayCell(
      date: date,
      look: look,
      isToday: WorkCalendar.isSameDay(date, today),
      detailed: detailed,
      onTap: tappable ? () => onTapDay(target) : null,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.look,
    required this.isToday,
    required this.detailed,
    required this.onTap,
  });

  final DateTime date;
  final CalendarLook look;
  final bool isToday;
  final bool detailed;
  final VoidCallback? onTap;

  static const double _radius = 14;

  @override
  Widget build(BuildContext context) {
    final tone = look.tone;
    final radius = BorderRadius.circular(_radius);
    final pending = look.pending;
    final ink = tone.inkOf(context);
    final colored =
        tone != CalendarTone.upcoming && tone != CalendarTone.off;

    final number = Text(
      '${date.day}',
      style: TextStyle(
        fontSize: detailed ? 15 : 14,
        height: 1.1,
        fontWeight: colored || isToday ? FontWeight.w700 : FontWeight.w500,
        color: ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    // Penanda "perlu koreksi": ikon kecil seinduk warna tanggalnya.
    final marker = look.flags.contains(CalendarFlag.needsCorrection)
        ? Icon(Icons.error_outline, size: detailed ? 14 : 11, color: ink)
        : null;

    final Widget content;
    if (detailed) {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [number, const Spacer(), ?marker]),
            const Spacer(),
            if (look.caption != null)
              Text(
                look.caption!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      );
    } else {
      content = Stack(
        children: [
          Center(child: number),
          if (marker != null) Positioned(top: 4, right: 4, child: marker),
        ],
      );
    }

    return Semantics(
      button: onTap != null,
      label: calendarSemanticsLabel(date, look),
      excludeSemantics: true,
      onTap: onTap,
      child: Container(
        // Cincin "hari ini" di atas warna status.
        foregroundDecoration: isToday
            ? BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: context.ink, width: 2),
              )
            : null,
        child: Material(
          color: pending ? Colors.transparent : tone.fillOf(context),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: pending
                ? BorderSide(color: tone.accentOf(context), width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: onTap,
            child: pending
                ? CustomPaint(
                    painter: HatchPainter(
                      tone.accentOf(context).withValues(alpha: 0.16),
                    ),
                    child: content,
                  )
                : content,
          ),
        ),
      ),
    );
  }
}

/// Arsir diagonal untuk pengajuan yang masih menunggu persetujuan.
class HatchPainter extends CustomPainter {
  const HatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.2;
    const spacing = 7.0;
    for (var x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(HatchPainter oldDelegate) => oldDelegate.color != color;
}

/// Keterangan warna kalender.
class AttendanceCalendarLegend extends StatelessWidget {
  const AttendanceCalendarLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontSize: 12.5,
    );

    Widget item(Widget swatch, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: 7),
        Text(label, style: style),
      ],
    );

    Widget box(CalendarTone tone) => Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: tone.fillOf(context),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: tone.accentOf(context), width: 1.2),
      ),
    );

    final pendingTone = CalendarTone.annualLeave;

    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: [
        item(box(CalendarTone.present), 'Hadir'),
        item(box(CalendarTone.annualLeave), 'Cuti / izin'),
        item(box(CalendarTone.sick), 'Sakit'),
        item(box(CalendarTone.missing), 'Belum absen'),
        item(
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: pendingTone.accentOf(context),
                width: 1.5,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: CustomPaint(
              painter: HatchPainter(
                pendingTone.accentOf(context).withValues(alpha: 0.2),
              ),
            ),
          ),
          'Menunggu persetujuan',
        ),
        item(
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: context.ink, width: 2),
            ),
          ),
          'Hari ini',
        ),
      ],
    );
  }
}
