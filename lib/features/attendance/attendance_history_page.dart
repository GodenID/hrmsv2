import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/push_notifications.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/app_exception.dart';
import '../../data/attendance_repository.dart';
import '../../data/leave_repository.dart';
import '../shell/shell_routes.dart';
import 'widgets/attendance_calendar.dart';
import 'widgets/attendance_day_sheet.dart';

/// Menu Absensi: kalender bulanan berwarna + ringkasan + koreksi.
///
/// Kalender ikut berubah begitu ada clock in/out, koreksi, atau pengajuan
/// cuti / izin / sakit (termasuk yang masih menunggu persetujuan).
class AttendanceHistoryPage extends StatefulWidget {
  const AttendanceHistoryPage({super.key});

  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  late AttendanceRepository _repo;
  late Listenable _changes;
  bool _initialized = false;

  /// Awal periode buku yang tampil (selalu tanggal 26).
  late DateTime _periodStart;

  /// Awal periode pertama yang boleh dibuka (dari bulan mulai bekerja).
  DateTime? _firstPeriod;
  List<AttendanceDay>? _days;
  bool _isLoading = false;
  String? _error;

  /// Mencegah hasil muat periode lama menimpa periode yang baru dipilih.
  int _requestId = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final deps = AppScope.of(context);
    _repo = deps.attendance;
    // Pengajuan cuti / izin / sakit juga mengubah warna kalender.
    _changes = Listenable.merge([deps.attendance.changes, deps.leave.changes]);
    _changes.addListener(_onChanged);
    AppRefresh.attendance.addListener(_onChanged);
    _periodStart = WorkCalendar.periodStartFor(DateTime.now());
    _loadFirstPeriod();
    _load();
  }

  @override
  void dispose() {
    _changes.removeListener(_onChanged);
    AppRefresh.attendance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _loadFirstPeriod() async {
    try {
      final first = await _repo.fetchFirstMonth(SessionScope.userOf(context));
      if (mounted) {
        setState(
          () => _firstPeriod = WorkCalendar.periodStartFor(
            DateTime(first.year, first.month),
          ),
        );
      }
    } catch (_) {
      // Tidak fatal: tombol periode sebelumnya tetap aktif.
    }
  }

  Future<void> _load({bool silent = false}) async {
    final id = ++_requestId;
    setState(() {
      _isLoading = true;
      _error = null;
      if (!silent) _days = null;
    });
    try {
      // Satu periode 26–25 selalu mencakup dua bulan kalender.
      final start = _periodStart;
      final end = DateTime(start.year, start.month + 1, 25);
      final user = SessionScope.userOf(context);
      final results = await Future.wait([
        _repo.fetchMonth(user, year: start.year, month: start.month),
        _repo.fetchMonth(user, year: end.year, month: end.month),
      ]);
      if (mounted && id == _requestId) {
        bool inRange(AttendanceDay d) =>
            !d.date.isBefore(start) && !d.date.isAfter(end);
        // Keduanya sudah terbaru-dulu; periode akhir lebih baru.
        final days = [
          for (final d in results[1])
            if (inRange(d)) d,
          for (final d in results[0])
            if (inRange(d)) d,
        ];
        setState(() => _days = days);
      }
    } on AppException catch (e) {
      if (mounted && id == _requestId) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && id == _requestId) {
        setState(() => _error = 'Data absensi gagal dimuat. Coba lagi.');
      }
    } finally {
      if (mounted && id == _requestId) setState(() => _isLoading = false);
    }
  }

  DateTime get _today => WorkCalendar.dateOnly(DateTime.now());

  DateTime get _currentPeriod =>
      WorkCalendar.periodStartFor(DateTime.now());

  DateTime get _periodEnd =>
      DateTime(_periodStart.year, _periodStart.month + 1, 25);

  /// Periode terjauh yang bisa memuat pengajuan cuti.
  DateTime get _lastPeriod => WorkCalendar.periodStartFor(
    _today.add(const Duration(days: LeaveRules.maxDaysAhead)),
  );

  bool get _canGoPrev =>
      _firstPeriod == null || _periodStart.isAfter(_firstPeriod!);
  bool get _canGoNext => _periodStart.isBefore(_lastPeriod);
  bool get _isCurrentPeriod => _periodStart == _currentPeriod;

  void _goToPeriod(DateTime periodStart) {
    setState(
      () => _periodStart = DateTime(
        periodStart.year,
        periodStart.month,
        WorkCalendar.periodOpeningDay,
      ),
    );
    _load();
  }

  Future<void> _openDay(AttendanceDay day) async {
    final navigator = Navigator.of(context);
    final action = await showAttendanceDaySheet(context, day);
    if (!mounted) return;
    switch (action) {
      case DaySheetAction.requestCorrection:
        final sent = await navigator.pushNamed<bool>(
          ShellRoutes.attendanceCorrection,
          arguments: day,
        );
        // Lembar sukses sudah tampil di formulir; daftar memuat ulang
        // otomatis lewat listener perubahan data.
        if (sent == true && mounted) {
          await _load();
        }
      case DaySheetAction.openLeave:
        final leave = day.leave;
        if (leave != null) {
          await navigator.pushNamed(ShellRoutes.leaveDetail, arguments: leave);
        }
      case DaySheetAction.cancelCorrection:
        await _cancelRequest(
          () => AppScope.of(context).attendance.cancelCorrection(
            SessionScope.userOf(context),
            id: day.correction!.id,
          ),
          'Pengajuan koreksi dibatalkan.',
        );
      case DaySheetAction.cancelOutOfArea:
        await _cancelRequest(
          () => AppScope.of(context).attendance.cancelOutOfArea(
            SessionScope.userOf(context),
            id: day.outOfArea!.id,
          ),
          'Pengajuan luar area dibatalkan.',
        );
      case null:
        break;
    }
  }

  /// Membatalkan pengajuan milik sendiri dari lembar hari, lalu memuat ulang.
  Future<void> _cancelRequest(
    Future<void> Function() action,
    String okMessage,
  ) async {
    try {
      await action();
      if (!mounted) return;
      showAppSnackBar(context, okMessage);
      await _load();
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Gagal membatalkan. Coba lagi.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    final textTheme = Theme.of(context).textTheme;

    return PageScaffold(
      title: 'Absensi',
      onRefresh: () => _load(silent: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PeriodSwitcher(
            start: _periodStart,
            end: _periodEnd,
            showToday: !_isCurrentPeriod,
            onToday: () => _goToPeriod(_currentPeriod),
            onPrev: _canGoPrev
                ? () => _goToPeriod(
                    DateTime(
                      _periodStart.year,
                      _periodStart.month - 1,
                      WorkCalendar.periodOpeningDay,
                    ),
                  )
                : null,
            onNext: _canGoNext
                ? () => _goToPeriod(
                    DateTime(
                      _periodStart.year,
                      _periodStart.month + 1,
                      WorkCalendar.periodOpeningDay,
                    ),
                  )
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          if (_error != null && days == null) ...[
            FormErrorBanner(message: _error!),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Coba lagi'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Garis progres tipis agar kalender tidak "melompat" saat
                // berganti periode.
                SizedBox(
                  height: 2,
                  child: _isLoading
                      ? Semantics(
                          label: 'Memuat data absensi',
                          liveRegion: true,
                          child: const LinearProgressIndicator(minHeight: 2),
                        )
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                  child: AttendanceCalendar(
                    start: _periodStart,
                    end: _periodEnd,
                    today: _today,
                    days: days,
                    onTapDay: _openDay,
                  ),
                ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: AttendanceCalendarLegend(),
                ),
              ],
            ),
          ),
          if (days != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _SummaryStrip(days: days),
            if (days.any((d) => d.needsAttention)) ...[
              const SizedBox(height: AppSpacing.md),
              _AttentionNote(count: days.where((d) => d.needsAttention).length),
            ],
          ],
          const SizedBox(height: AppSpacing.md),
          Text(
            'Ketuk tanggal untuk melihat jam clock in & clock out atau detail '
            'cuti/izin/sakit. Jam masuk paling lambat '
            '${WorkPolicy.latestOnTimeHour.toString().padLeft(2, '0')}.'
            '${WorkPolicy.latestOnTimeMinute.toString().padLeft(2, '0')}. '
            'Pengajuan yang masih menunggu ditandai berarsir.',
            style: textTheme.bodySmall?.copyWith(fontSize: 12.5, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// Pindah periode buku 26–25.
class _PeriodSwitcher extends StatelessWidget {
  const _PeriodSwitcher({
    required this.start,
    required this.end,
    required this.showToday,
    required this.onToday,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime start;
  final DateTime end;
  final bool showToday;
  final VoidCallback onToday;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    ButtonStyle style() => IconButton.styleFrom(
      fixedSize: const Size(40, 40),
      foregroundColor: context.ink,
      disabledForegroundColor: context.borderStrong,
      side: BorderSide(color: context.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Periode buku',
          style: textTheme.labelSmall,
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  DateFormatId.dateRange(start, end),
                  style: textTheme.titleMedium?.copyWith(fontSize: 18),
                ),
              ),
            ),
            if (showToday) ...[
              TextButton(onPressed: onToday, child: const Text('Hari ini')),
              const SizedBox(width: 4),
            ],
            IconButton.outlined(
              tooltip: 'Periode sebelumnya',
              onPressed: onPrev,
              style: style(),
              icon: const Icon(Icons.chevron_left, size: 20),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: 'Periode berikutnya',
              onPressed: onNext,
              style: style(),
              icon: const Icon(Icons.chevron_right, size: 20),
            ),
          ],
        ),
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.days});

  final List<AttendanceDay> days;

  @override
  Widget build(BuildContext context) {
    final present = days.where((d) => d.clockIn != null).length;
    final late = days.where((d) => d.status == AttendanceDayStatus.late).length;
    final leaveDays = days
        .where((d) => d.leave != null && d.leave!.type != LeaveType.sick)
        .length;
    final sickDays = days.where((d) => d.leave?.type == LeaveType.sick).length;
    final attention = days.where((d) => d.needsAttention).length;
    // Hari kerja periode berjalan yang belum ada absensinya.
    final notYet = days
        .where((d) => d.status == AttendanceDayStatus.absent)
        .length;

    final metrics = [
      _Metric(value: '$present', unit: 'hari', label: 'Hadir'),
      _Metric(value: '$late', unit: 'hari', label: 'Terlambat'),
      _Metric(value: '$leaveDays', unit: 'hari', label: 'Cuti & izin'),
      _Metric(value: '$sickDays', unit: 'hari', label: 'Sakit'),
      _Metric(
        value: '$notYet',
        unit: 'hari',
        label: 'Belum absen',
        highlight: notYet > 0,
      ),
      _Metric(
        value: '$attention',
        unit: 'hari',
        label: 'Perlu koreksi',
        highlight: attention > 0,
      ),
    ];

    return Panel(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final perRow = constraints.maxWidth >= 640
              ? 5
              : constraints.maxWidth >= 420
              ? 3
              : 2;
          final rows = <Widget>[];
          for (var i = 0; i < metrics.length; i += perRow) {
            if (i > 0) {
              rows.add(
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(),
                ),
              );
            }
            rows.add(
              IntrinsicHeight(
                child: Row(
                  children: [
                    for (var j = i; j < i + perRow; j++) ...[
                      if (j > i) const VerticalDivider(width: 1),
                      Expanded(
                        child: j < metrics.length
                            ? metrics[j]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          return Column(children: rows);
        },
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.unit,
    required this.label,
    this.highlight = false,
  });

  final String value;
  final String unit;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      label: '$label: $value $unit',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: textTheme.bodySmall?.copyWith(fontSize: 12.5)),
            const SizedBox(height: 4),
            Text.rich(
              TextSpan(
                text: value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: highlight ? context.danger : context.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                children: [
                  TextSpan(
                    text: ' $unit',
                    style: textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttentionNote extends StatelessWidget {
  const _AttentionNote({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: context.warningSubtle,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: const Color(0xFFF7D9A8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline,
              size: 18,
              color: context.warning,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ada $count hari tanpa catatan lengkap (titik merah di '
              'kalender). Ketuk tanggalnya lalu ajukan koreksi agar durasi '
              'kerja Anda dihitung dengan benar.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: context.warning, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}
