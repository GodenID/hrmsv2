import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/app_exception.dart';
import '../../data/attendance_repository.dart';
import '../../data/employee_repository.dart';
import '../../data/event_repository.dart';
import '../../data/leave_repository.dart';
import 'report_workbook.dart';

/// Laporan & ekspor Super Admin: rekap otomatis + pratinjau + berkas
/// Excel all-in-one (Ringkasan + tiap kategori). Absensi mengikuti
/// periode buku 26–25.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool _initialized = false;
  ReportKind _kind = ReportKind.all;
  late DateTime _periodStart;

  /// Bulan kalender untuk event (1–akhir bulan), terpisah dari periode buku.
  late DateTime _eventMonth;

  List<EmployeeAccount>? _employees;
  Map<String, List<AttendanceDay>> _attendance = {};
  List<EventItem>? _events;
  Map<String, List<LeaveRequest>> _leaves = {};
  Map<String, List<OvertimeRequest>> _overtimes = {};
  List<CorrectionReviewItem>? _corrections;
  List<OutOfAreaReviewItem>? _outOfAreas;

  bool _isLoading = true;
  String? _error;
  String _progress = 'Menyiapkan data…';
  bool _isExporting = false;

  bool get _needsAttendance =>
      _kind == ReportKind.all || _kind == ReportKind.attendance;
  bool get _needsEvents =>
      _kind == ReportKind.all || _kind == ReportKind.events;
  bool get _needsRequests =>
      _kind == ReportKind.all || _kind == ReportKind.requests;
  bool get _needsEmployees => true;

  /// Rekap butuh cuti & lembur walau antrean persetujuan tidak dibutuhkan.
  bool get _needsLeaveData =>
      _needsRequests || _kind == ReportKind.attendance;

  DateTime get _periodEnd =>
      DateTime(_periodStart.year, _periodStart.month + 1, 25);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _periodStart = WorkCalendar.periodStartFor(DateTime.now());
    final now = DateTime.now();
    _eventMonth = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _progress = 'Menyiapkan data…';
    });
    try {
      final deps = AppScope.of(context);
      final user = SessionScope.userOf(context);
      final employees = await deps.employees.fetchEmployees(user);
      if (!mounted) return;
      setState(() {
        _employees = employees;
        _progress = 'Memuat absensi & pengajuan…';
      });

      final attendance = <String, List<AttendanceDay>>{};
      if (_needsAttendance) {
        final months = {
          DateTime(_periodStart.year, _periodStart.month),
          DateTime(_periodEnd.year, _periodEnd.month),
        };
        await Future.wait([
          for (final e in employees)
            () async {
              final parts = await Future.wait([
                for (final m in months)
                  deps.attendance.fetchMonth(
                    user,
                    year: m.year,
                    month: m.month,
                  ),
              ]);
              bool inRange(AttendanceDay d) =>
                  !d.date.isBefore(_periodStart) &&
                  !d.date.isAfter(_periodEnd);
              attendance[e.username] = [
                for (final list in parts.reversed)
                  for (final d in list)
                    if (inRange(d)) d,
              ];
            }(),
        ]);
      }
      if (!mounted) return;

      List<EventItem> events = const [];
      if (_needsEvents) {
        events = await deps.events.fetchEvents(user);
        if (!mounted) return;
      }
      final leaves = <String, List<LeaveRequest>>{};
      final overtimes = <String, List<OvertimeRequest>>{};
      List<CorrectionReviewItem> corrections = const [];
      List<OutOfAreaReviewItem> outOfAreas = const [];
      if (_needsLeaveData) {
        // Cuti & lembur diambil per karyawan agar lengkap (termasuk yang
        // dibatalkan); koreksi & luar-area lewat antrean reviewer.
        await Future.wait([
          Future.wait([
            for (final e in employees)
              () async {
                leaves[e.username] = await deps.leave.fetchRequests(user);
                overtimes[e.username] = await deps.overtime.fetchRequests(
                  user,
                );
              }(),
          ]),
          deps.attendance
              .fetchCorrectionQueue(user)
              .then((v) => corrections = v),
          deps.attendance
              .fetchOutOfAreaQueue(user)
              .then((v) => outOfAreas = v),
        ]);
      }
      if (!mounted) return;
      setState(() {
        _attendance = attendance;
        _events = events;
        _leaves = leaves;
        _overtimes = overtimes;
        _corrections = corrections;
        _outOfAreas = outOfAreas;
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Data laporan gagal dimuat. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, EmployeeAccount> get _directory => {
    for (final e in _employees ?? const <EmployeeAccount>[]) e.username: e,
  };

  /// Periode buku yang dipakai semua sheet, kecuali master karyawan
  /// (tanpa filter) dan event (ikut bulan kalender).
  /// null = tanpa filter (jenis Karyawan).
  DateTime? get _filterStart =>
      _kind == ReportKind.employees ? null : _periodStart;
  DateTime? get _filterEnd =>
      _kind == ReportKind.employees ? null : _periodEnd;

  /// Batas bulan kalender untuk event (1–akhir bulan).
  DateTime get _eventStart => DateTime(_eventMonth.year, _eventMonth.month);
  DateTime get _eventEnd =>
      DateTime(_eventMonth.year, _eventMonth.month + 1, 0);

  bool _inPeriod(DateTime date) {
    final start = _filterStart;
    final end = _filterEnd;
    if (start == null || end == null) return true;
    final d = WorkCalendar.dateOnly(date);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  bool _overlaps(DateTime start, DateTime end) {
    final ps = _filterStart;
    final pe = _filterEnd;
    if (ps == null || pe == null) return true;
    return !WorkCalendar.dateOnly(end).isBefore(ps) &&
        !WorkCalendar.dateOnly(start).isAfter(pe);
  }

  List<ReportSheetData> _buildSheets() {
    final employees = _employees ?? const [];
    final periodLabel = DateFormatId.dateRange(_periodStart, _periodEnd);
    final now = DateTime.now();
    final user = SessionScope.userOf(context);
    final events = [
      for (final e in _events ?? const <EventItem>[])
        if (overlapsPeriod(e.startDate, e.endDate, _eventStart, _eventEnd))
          e,
    ];
    final leaves = [
      for (final list in _leaves.values)
        for (final r in list)
          if (_overlaps(r.start, r.end)) r,
    ];
    final overtimes = [
      for (final list in _overtimes.values)
        for (final r in list)
          if (_inPeriod(r.date)) r,
    ];
    final corrections = [
      for (final i in _corrections ?? const <CorrectionReviewItem>[])
        if (_inPeriod(i.correction.date)) i,
    ];
    final outOfAreas = [
      for (final i in _outOfAreas ?? const <OutOfAreaReviewItem>[])
        if (_inPeriod(i.request.date)) i,
    ];
    int countStatus(RequestStatus s) =>
        leaves.where((r) => r.status == s).length +
        overtimes.where((r) => r.status == s).length +
        corrections.where((i) => i.correction.status == s).length +
        outOfAreas.where((i) => i.request.status == s).length;
    final summary = summarySheet(
      periodLabel: periodLabel,
      generatedAt: now,
      generatedBy: user.fullName,
      activeEmployees: employees.where((e) => e.active).length,
      totalEmployees: employees.length,
      events: events.length,
      pendingRequests: countStatus(RequestStatus.pending),
      approvedRequests: countStatus(RequestStatus.approved),
      rejectedRequests: countStatus(RequestStatus.rejected),
    );
    // Map terfilter untuk builder sheet (periode buku).
    final leaveMap = <String, List<LeaveRequest>>{
      for (final entry in _leaves.entries)
        entry.key: [
          for (final r in entry.value)
            if (_overlaps(r.start, r.end)) r,
        ],
    };
    final overtimeMap = <String, List<OvertimeRequest>>{
      for (final entry in _overtimes.entries)
        entry.key: [
          for (final r in entry.value)
            if (_inPeriod(r.date)) r,
        ],
    };
    final sheets = [summary];
    if (_needsAttendance) {
      sheets.add(
        employeeRecapSheet(
          employees: employees,
          daysByUsername: _attendance,
          leaveByUser: leaveMap,
          overtimeByUser: overtimeMap,
          start: _periodStart,
          end: _periodEnd,
        ),
      );
      sheets.add(
        attendanceSheet(
          employees: employees,
          daysByUsername: _attendance,
          overtimeByUser: overtimeMap,
          start: _periodStart,
          end: _periodEnd,
        ),
      );
    }
    if (_needsEmployees) sheets.add(employeeSheet(employees));
    if (_needsEvents) {
      sheets.add(
        eventRecapSheet(events, start: _eventStart, end: _eventEnd),
      );
      sheets.add(eventSheet(events, start: _eventStart, end: _eventEnd));
      sheets.add(eventCrewSheet(events, start: _eventStart, end: _eventEnd));
    }
    if (_needsRequests) {
      sheets.add(
        leaveSheet(_directory, leaveMap, start: _filterStart, end: _filterEnd),
      );
      sheets.add(
        overtimeSheet(
          _directory,
          overtimeMap,
          start: _filterStart,
          end: _filterEnd,
        ),
      );
    }
    return sheets;
  }

  String _two(int v) => v.toString().padLeft(2, '0');

  String get _fileName {
    // Absensi & pengajuan memakai periode buku; event memakai bulan kalender.
    final book =
        '${_periodStart.year}-${_two(_periodStart.month)}';
    final month = '${_eventMonth.year}-${_two(_eventMonth.month)}';
    final kind = switch (_kind) {
      ReportKind.all => 'semua-$book',
      ReportKind.attendance => 'absensi-$book',
      ReportKind.events => 'event-$month',
      ReportKind.requests => 'pengajuan-$book',
      ReportKind.employees => 'karyawan',
    };
    return 'Prasasti-Connect-Laporan-$kind.xlsx';
  }

  Future<void> _export() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final bytes = buildWorkbookBytes(_buildSheets());
      if (bytes == null) throw const AppException('Berkas gagal dibuat.');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], subject: 'Laporan HRMS'),
      );
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Berbagi tidak didukung di perangkat ini.',
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

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

  /// Dialog pilih bulan event (nama bulan + tahun, tanpa batas).
  Future<void> _pickEventMonth() async {
    var year = _eventMonth.year;
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: const Text('Pilih bulan event'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton.outlined(
                      tooltip: 'Tahun sebelumnya',
                      onPressed: () => setDialog(() => year--),
                      icon: const Icon(Icons.chevron_left, size: 20),
                    ),
                    Expanded(
                      child: Text(
                        '$year',
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: 'Tahun berikutnya',
                      onPressed: () => setDialog(() => year++),
                      icon: const Icon(Icons.chevron_right, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.4,
                  children: [
                    for (var m = 1; m <= 12; m++)
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(
                          DateTime(year, m),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor:
                              _eventMonth.year == year &&
                                  _eventMonth.month == m
                              ? context.accentSubtle
                              : null,
                          padding: EdgeInsets.zero,
                        ),
                        child: Text(
                          DateFormatId.monthName(m),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: context.inkSecondary,
              ),
              child: const Text('Batal'),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _eventMonth = picked);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PageScaffold(
      title: 'Laporan',
      maxWidth: 880,
      onRefresh: _load,
      actions: [
        FilledButton.icon(
          onPressed: _isLoading || _isExporting || _error != null
              ? null
              : _export,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          icon: _isExporting
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.file_download_outlined, size: 18),
          label: Text(_isExporting ? 'Membuat…' : 'Ekspor Excel'),
        ),
      ],
      child: AsyncBody(
        isLoading: _isLoading,
        error: _error,
        hasData: _employees != null,
        onRetry: _load,
        loadingLabel: _progress,
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ReportKind>(
                    initialValue: _kind,
                    items: [
                      for (final k in ReportKind.values)
                        DropdownMenuItem(value: k, child: Text(k.label)),
                    ],
                    onChanged: (k) {
                      if (k == null) return;
                      setState(() => _kind = k);
                      _load();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Jenis laporan',
                      prefixIcon: Icon(Icons.assessment_outlined, size: 20),
                    ),
                  ),
                ),
              ],
            ),
            if (_kind == ReportKind.all ||
                _kind == ReportKind.attendance ||
                _kind == ReportKind.requests) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Periode buku '
                      '${DateFormatId.dateRange(_periodStart, _periodEnd)}',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Periode sebelumnya',
                    onPressed: () => _goToPeriod(
                      DateTime(
                        _periodStart.year,
                        _periodStart.month - 1,
                        WorkCalendar.periodOpeningDay,
                      ),
                    ),
                    icon: const Icon(Icons.chevron_left, size: 20),
                  ),
                  const SizedBox(width: 6),
                  IconButton.outlined(
                    tooltip: 'Periode berikutnya',
                    onPressed: () => _goToPeriod(
                      DateTime(
                        _periodStart.year,
                        _periodStart.month + 1,
                        WorkCalendar.periodOpeningDay,
                      ),
                    ),
                    icon: const Icon(Icons.chevron_right, size: 20),
                  ),
                ],
              ),
            ],
            if (_kind == ReportKind.all || _kind == ReportKind.events) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: 'Ketuk untuk pilih bulan',
                      child: InkWell(
                        onTap: _pickEventMonth,
                        borderRadius: BorderRadius.circular(
                          AppRadius.control,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  'Bulan event '
                                  '${DateFormatId.monthYear(_eventMonth)}',
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.calendar_month_outlined,
                                size: 18,
                                color: context.inkSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Bulan sebelumnya',
                    onPressed: () => setState(
                      () => _eventMonth = DateTime(
                        _eventMonth.year,
                        _eventMonth.month - 1,
                      ),
                    ),
                    icon: const Icon(Icons.chevron_left, size: 20),
                  ),
                  const SizedBox(width: 6),
                  IconButton.outlined(
                    tooltip: 'Bulan berikutnya',
                    onPressed: () => setState(
                      () => _eventMonth = DateTime(
                        _eventMonth.year,
                        _eventMonth.month + 1,
                      ),
                    ),
                    icon: const Icon(Icons.chevron_right, size: 20),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _SummaryCards(sheets: _buildSheets()),
            const SizedBox(height: AppSpacing.lg),
            _SampleTable(sheets: _buildSheets()),
          ],
        ),
      ),
    );
  }
}

/// Kartu angka ringkasan: karyawan, event, menunggu, disetujui.
class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.sheets});

  final List<ReportSheetData> sheets;

  @override
  Widget build(BuildContext context) {
    String value(String title, int row, int col) {
      for (final s in sheets) {
        if (s.title != title) continue;
        if (row < s.rows.length && col < s.rows[row].length) {
          return '${s.rows[row][col]}';
        }
      }
      return '—';
    }

    final cards = [
      ('Karyawan aktif', value('Ringkasan', 4, 1), Icons.people_outline),
      ('Event', value('Ringkasan', 6, 1), Icons.festival_outlined),
      (
        'Menunggu',
        value('Ringkasan', 7, 1),
        Icons.hourglass_bottom_outlined,
      ),
      ('Disetujui', value('Ringkasan', 8, 1), Icons.check_circle_outline),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 560;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final (label, number, icon) in cards)
              SizedBox(
                width: wide
                    ? (constraints.maxWidth - AppSpacing.md * 3) / 4
                    : (constraints.maxWidth - AppSpacing.md) / 2,
                child: Panel(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 20, color: context.accentText),
                      const SizedBox(height: 8),
                      Text(
                        number,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Tabel contoh: 8 baris pertama sheet data pertama (selain Ringkasan).
class _SampleTable extends StatelessWidget {
  const _SampleTable({required this.sheets});

  final List<ReportSheetData> sheets;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final data = [
      for (final s in sheets)
        if (s.title != 'Ringkasan') s,
    ];
    if (data.isEmpty) return const SizedBox.shrink();
    final sheet = data.first;
    final shown = sheet.rows.take(8).toList();
    final rest = sheet.rows.length - shown.length;

    Widget cell(Object? value, {bool header = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(
          '$value',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: header
              ? textTheme.labelSmall
              : textTheme.bodySmall?.copyWith(fontSize: 12.5),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel('Pratinjau · ${sheet.title}'),
        const SizedBox(height: AppSpacing.sm),
        Panel(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 40,
              columns: [
                for (final h in sheet.header) DataColumn(label: cell(h, header: true)),
              ],
              rows: [
                for (final r in shown)
                  DataRow(
                    cells: [for (final v in r) DataCell(cell(v))],
                  ),
              ],
            ),
          ),
        ),
        if (rest > 0) ...[
          const SizedBox(height: 6),
          Text(
            '…dan $rest baris lainnya di berkas Excel.',
            style: textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}
