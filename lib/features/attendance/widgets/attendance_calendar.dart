import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/work_calendar.dart';
import '../../../data/attendance_repository.dart';
import '../attendance_presentation.dart';

/// Kalender absensi per rentang tanggal (Senin–Minggu), mengikuti periode
/// buku 26–25. Warna tiap tanggal:
/// hijau = hadir, biru = cuti, ungu = izin, merah muda = sakit,
/// abu-abu = belum absen / tidak hadir. Pengajuan yang masih menunggu
/// digambar berarsir.
///
/// Lebar sel >= 92: tampil jam clock in–out / jenis cuti di dalam sel.
/// Lebih sempit (HP): hanya angka tanggal + penanda.
class AttendanceCalendar extends StatelessWidget {
  const AttendanceCalendar({
    super.key,
    required this.start,
    required this.end,
    required this.today,
    required this.days,
    required this.onTapDay,
  });

  /// Batas rentang (inklusif), mis. 26 Sep – 25 Okt.
  final DateTime start;
  final DateTime end;
  final DateTime today;

  /// null = sedang memuat (semua sel netral, tidak bisa diketuk).
  /// Hanya tanggal sampai [today] yang bisa diketuk; tanggal mendatang tidak.
  final List<AttendanceDay>? days;
  final ValueChanged<AttendanceDay> onTapDay;

  static const _weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  static const double _gap = 4;

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
        final cellHeight = detailed ? 78.0 : 48.0;

        final rows = <Widget>[];
        for (var start = 0; start < cellCount; start += 7) {
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: start == 0 ? 0 : _gap),
              child: Row(
                children: [
                  for (var i = start; i < start + 7; i++) ...[
                    if (i > start) const SizedBox(width: _gap),
                    Expanded(
                      child: SizedBox(
                        height: cellHeight,
                        child: _cellAt(
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
                        padding: EdgeInsets.only(left: detailed ? 8 : 0),
                        child: Text(
                          _weekdays[i],
                          textAlign: detailed
                              ? TextAlign.left
                              : TextAlign.center,
                          style: textTheme.labelSmall?.copyWith(
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
    // Tanggal yang sudah lewat (dan hari ini) bisa diketuk — termasuk akhir
    // pekan/libur — untuk melihat catatan atau mengajukan absensi bila lupa.
    // Tanggal mendatang tidak bisa diketuk.
    final tappable =
        !loading && day != null && !WorkCalendar.dateOnly(date).isAfter(today);
    return _DayCell(
      date: date,
      look: look,
      isToday: WorkCalendar.isSameDay(date, today),
      detailed: detailed,
      onTap: tappable ? () => onTapDay(day) : null,
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

  @override
  Widget build(BuildContext context) {
    final tone = look.tone;
    final radius = BorderRadius.circular(AppRadius.control);
    final pending = look.pending;

    final number = Text(
      '${date.day}',
      style: TextStyle(
        fontSize: detailed ? 14 : 13.5,
        height: 1.1,
        fontWeight: isToday || tone != CalendarTone.upcoming
            ? FontWeight.w700
            : FontWeight.w500,
        color: tone.inkOf(context),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    final flags = look.flags.isEmpty
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in look.flags)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(left: 3),
                  decoration: BoxDecoration(
                    color: f.colorOf(context),
                    shape: BoxShape.circle,
                    border: Border.all(color: context.surface, width: 0.8),
                  ),
                ),
            ],
          );

    final Widget content;
    if (detailed) {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(8, 7, 7, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [number, const Spacer(), ?flags]),
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
                  color: tone.inkOf(context),
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
          if (flags != null) Positioned(top: 4, right: 3, child: flags),
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
          color: pending ? context.surface : tone.fillOf(context),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: pending
                  ? tone.inkOf(context).withValues(alpha: 0.55)
                  : tone.borderOf(context),
              width: pending ? 1.4 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: pending
                ? CustomPaint(
                    painter: HatchPainter(tone.fillOf(context)),
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
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontSize: 12.5);

    Widget item(Widget swatch, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        swatch,
        const SizedBox(width: 6),
        Text(label, style: style),
      ],
    );

    Widget box(CalendarTone tone, {bool pending = false}) => Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: pending ? context.surface : tone.fillOf(context),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: pending
              ? tone.inkOf(context).withValues(alpha: 0.55)
              : tone.borderOf(context),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: pending
          ? CustomPaint(painter: HatchPainter(tone.fillOf(context)))
          : null,
    );

    Widget dot(Color color) => Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    return Wrap(
      spacing: AppSpacing.lg,
      runSpacing: AppSpacing.sm,
      children: [
        for (final tone in [
          CalendarTone.present,
          CalendarTone.annualLeave,
          CalendarTone.permission,
          CalendarTone.sick,
          CalendarTone.missing,
        ])
          item(box(tone), tone.label),
        item(
          box(CalendarTone.annualLeave, pending: true),
          'Menunggu persetujuan',
        ),
        for (final f in CalendarFlag.values)
          item(dot(f.colorOf(context)), f.label),
        item(
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: context.ink, width: 2),
            ),
          ),
          'Hari ini',
        ),
      ],
    );
  }
}
