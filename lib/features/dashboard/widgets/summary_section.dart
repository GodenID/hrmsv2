import 'package:flutter/material.dart';

import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/date_format_id.dart';
import '../../../core/utils/work_calendar.dart';
import '../../../core/widgets/brand_loading.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/attendance_repository.dart';
import '../../../data/auth_repository.dart';
import '../../../data/event_repository.dart';
import '../../../data/leave_repository.dart';
import '../../shell/shell_controller.dart';

/// Menghitung hari hadir dalam rentang tutup buku (bukan bulan kalender).
int countPresentInRange(
  Iterable<AttendanceDay> days,
  DateTime start,
  DateTime end,
) {
  final s = WorkCalendar.dateOnly(start);
  final e = WorkCalendar.dateOnly(end);
  return days
      .where(
        (d) =>
            (d.status == AttendanceDayStatus.onTime ||
                d.status == AttendanceDayStatus.late) &&
            !WorkCalendar.dateOnly(d.date).isBefore(s) &&
            !WorkCalendar.dateOnly(d.date).isAfter(e),
      )
      .length;
}

/// Event terdekat yang belum selesai (diurut tanggal mulai).
EventItem? nearestUpcomingEvent(List<EventItem> events, DateTime now) {
  final today = WorkCalendar.dateOnly(now);
  final upcoming = [
    for (final e in events)
      if (!WorkCalendar.dateOnly(e.endDate).isBefore(today)) e,
  ]..sort((a, b) => a.startDate.compareTo(b.startDate));
  return upcoming.firstOrNull;
}

/// Satu kartu ringkasan di Beranda: hadir bulan ini, cuti tersisa, dan
/// event terdekat dalam tiga baris yang masing-masing bisa diketuk menuju
/// menu terkait. Gagal memuat = seksi disembunyikan agar Beranda tetap
/// tampil.
class SummarySection extends StatefulWidget {
  const SummarySection({
    super.key,
    required this.user,
    required this.attendance,
    required this.leave,
    required this.events,
  });

  final AuthUser user;
  final AttendanceRepository attendance;
  final LeaveRepository leave;
  final EventRepository events;

  @override
  State<SummarySection> createState() => _SummarySectionState();
}

class _SummaryData {
  const _SummaryData({
    required this.presentThisMonth,
    required this.periodLabel,
    required this.balance,
    required this.nearestEvent,
  });

  final int presentThisMonth;

  /// Mis. "26 Sep–25 Okt" (periode tutup buku yang dipakai).
  final String periodLabel;
  final LeaveBalance? balance;
  final EventItem? nearestEvent;
}

class _SummarySectionState extends State<SummarySection> {
  _SummaryData? _data;
  bool _failed = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Muat ulang otomatis saat cuti/absensi/event berubah (mis. habis
    // mengajukan atau dipotong cuti bersama) agar angka selalu sinkron.
    if (_listening) return;
    _listening = true;
    widget.attendance.changes.addListener(_reload);
    widget.leave.changes.addListener(_reload);
    widget.events.changes.addListener(_reload);
  }

  @override
  void dispose() {
    widget.attendance.changes.removeListener(_reload);
    widget.leave.changes.removeListener(_reload);
    widget.events.changes.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    try {
      final now = DateTime.now();
      // Periode tutup buku 26–25 (bukan bulan kalender) agar angka hadir
      // sama dengan yang dipakai laporan & penggajian.
      final periodStart = WorkCalendar.periodStartFor(now);
      final periodEnd = WorkCalendar.periodEndFor(now);
      final months = {
        DateTime(periodStart.year, periodStart.month),
        DateTime(periodEnd.year, periodEnd.month),
      };
      final results = await Future.wait([
        for (final m in months)
          widget.attendance.fetchMonth(
            widget.user,
            year: m.year,
            month: m.month,
          ),
        widget.leave.fetchBalance(widget.user),
        widget.events.fetchEvents(widget.user),
      ]);
      if (!mounted) return;
      final days = [
        for (var i = 0; i < months.length; i++)
          ...(results[i] as List<AttendanceDay>),
      ];
      setState(() {
        _data = _SummaryData(
          presentThisMonth: countPresentInRange(days, periodStart, periodEnd),
          periodLabel:
              '${periodStart.day} ${DateFormatId.monthShort(periodStart)}'
              '–${periodEnd.day} ${DateFormatId.monthShort(periodEnd)}',
          balance: results[months.length] as LeaveBalance,
          nearestEvent: nearestUpcomingEvent(
            results[months.length + 1] as List<EventItem>,
            now,
          ),
        );
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _go(ShellTab tab) => ShellController.maybeOf(context)?.openTab(tab);

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    final data = _data;
    if (data == null) {
      return const SkeletonBox(widthFactor: 1, height: 196);
    }
    final balance = data.balance;
    final event = data.nearestEvent;
    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _SummaryRow(
            icon: Icons.check_circle_outline,
            iconColor: context.success,
            title: '${data.presentThisMonth} hari',
            subtitle: 'Hadir periode ${data.periodLabel}',
            onTap: () => _go(ShellTab.attendance),
          ),
          const Divider(height: 1),
          _SummaryRow(
            icon: Icons.beach_access_outlined,
            iconColor: context.accentText,
            title: balance == null
                ? 'Cuti tersisa'
                : '${balance.remaining} dari ${balance.quota} hari',
            subtitle: 'Cuti tersisa',
            onTap: () => _go(ShellTab.leave),
          ),
          const Divider(height: 1),
          _SummaryRow(
            icon: Icons.festival_outlined,
            iconColor: context.accentText,
            title: event?.name ?? 'Tidak ada event',
            subtitle: event == null
                ? 'Event terdekat'
                : 'Event terdekat · '
                      '${DateFormatId.dateRange(event.startDate, event.endDate)}',
            onTap: () => _go(ShellTab.events),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: context.surfaceMuted,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: iconColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: textTheme.bodySmall?.copyWith(fontSize: 12.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: context.inkTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
