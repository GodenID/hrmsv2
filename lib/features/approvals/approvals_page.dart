import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/push_notifications.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/app_haptics.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/initials_avatar.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/segment_toggle.dart';
import '../../data/attendance_repository.dart';
import '../../data/auth_repository.dart';
import '../../data/leave_repository.dart';
import '../../data/overtime_repository.dart';
import '../attendance/attendance_presentation.dart';
import '../shell/shell_routes.dart';
import 'widgets/review_widgets.dart';

/// Persetujuan (Manager & Super Admin): cuti/izin/sakit dan koreksi absensi
/// karyawan. Manager memproses pengajuan Staff; Super Admin semua karyawan.
class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key});

  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  late LeaveRepository _leave;
  late AttendanceRepository _attendance;
  late OvertimeRepository _overtime;
  bool _initialized = false;

  List<LeaveReviewItem>? _leaveItems;
  List<CorrectionReviewItem>? _correctionItems;
  List<OutOfAreaReviewItem>? _outOfAreaItems;
  List<OvertimeReviewItem>? _overtimeItems;
  bool _isLoading = false;
  String? _error;
  int _tab = 0;
  int _requestId = 0;
  int _historyPane = 0;
  int _historyLimit = 20;
  DateTime? _historyFrom;
  DateTime? _historyTo;
  final _searchController = TextEditingController();

  /// Mode pilih banyak (khusus Super Admin) + id yang dipilih.
  bool _selecting = false;
  final Set<String> _selected = {};
  bool _isProcessing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final deps = AppScope.of(context);
    _leave = deps.leave;
    _attendance = deps.attendance;
    _overtime = deps.overtime;
    _leave.changes.addListener(_onChanged);
    _attendance.changes.addListener(_onChanged);
    _overtime.changes.addListener(_onChanged);
    AppRefresh.leave.addListener(_onChanged);
    AppRefresh.attendance.addListener(_onChanged);
    AppRefresh.overtime.addListener(_onChanged);
    _searchController.addListener(() => setState(() {}));
    _historyFrom ??= DateTime.now().subtract(const Duration(days: 30));
    _historyTo ??= DateTime.now();
    _load();
  }

  @override
  void dispose() {
    _leave.changes.removeListener(_onChanged);
    _attendance.changes.removeListener(_onChanged);
    _overtime.changes.removeListener(_onChanged);
    AppRefresh.leave.removeListener(_onChanged);
    AppRefresh.attendance.removeListener(_onChanged);
    AppRefresh.overtime.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  bool get _canBulk =>
      SessionScope.userOf(context).role == UserRole.superadmin;

  bool get _canDeleteHistory =>
      SessionScope.userOf(context).role == UserRole.superadmin;

  bool _matchesName(String fullName, String q) {
    if (q.isEmpty) return true;
    return fullName.toLowerCase().contains(q);
  }

  bool _inHistoryRange(DateTime at) {
    final d = at.toLocal();
    if (_historyFrom != null) {
      final from = DateTime(
        _historyFrom!.year,
        _historyFrom!.month,
        _historyFrom!.day,
      );
      if (d.isBefore(from)) return false;
    }
    if (_historyTo != null) {
      final to = DateTime(
        _historyTo!.year,
        _historyTo!.month,
        _historyTo!.day,
        23,
        59,
        59,
      );
      if (d.isAfter(to)) return false;
    }
    return true;
  }

  void _onChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    final id = ++_requestId;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final user = SessionScope.userOf(context);
      final results = await Future.wait([
        _leave.fetchReviewQueue(user),
        _attendance.fetchCorrectionQueue(user),
        _attendance.fetchOutOfAreaQueue(user),
        _overtime.fetchReviewQueue(user),
      ]);
      if (!mounted || id != _requestId) return;
      setState(() {
        _leaveItems = results[0] as List<LeaveReviewItem>;
        _correctionItems = results[1] as List<CorrectionReviewItem>;
        _outOfAreaItems = results[2] as List<OutOfAreaReviewItem>;
        _overtimeItems = results[3] as List<OvertimeReviewItem>;
      });
    } on AppException catch (e) {
      if (mounted && id == _requestId) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && id == _requestId) {
        setState(() => _error = 'Data persetujuan gagal dimuat. Coba lagi.');
      }
    } finally {
      if (mounted && id == _requestId) setState(() => _isLoading = false);
    }
  }

  void _showResult(RequestStatus? status) {
    if (status == null || !mounted) return;
    showAppSnackBar(
      context,
      status == RequestStatus.approved
          ? 'Pengajuan disetujui. Karyawan sudah diberi notifikasi.'
          : 'Pengajuan ditolak. Karyawan sudah diberi notifikasi.',
    );
  }

  Future<void> _openLeave(LeaveReviewItem item) async {
    if (_isProcessing) return;
    final status = await Navigator.of(context)
        .pushNamed<RequestStatus>(ShellRoutes.leaveReview, arguments: item);
    _showResult(status);
  }

  Future<void> _openCorrection(CorrectionReviewItem item) async {
    if (_isProcessing) return;
    final status = await Navigator.of(
      context,
    ).pushNamed<RequestStatus>(ShellRoutes.correctionReview, arguments: item);
    _showResult(status);
  }

  Future<void> _openOutOfArea(OutOfAreaReviewItem item) async {
    if (_isProcessing) return;
    final status = await Navigator.of(
      context,
    ).pushNamed<RequestStatus>(ShellRoutes.outOfAreaReview, arguments: item);
    _showResult(status);
  }

  void _toggleSelect(String id, bool? checked) {
    if (_isProcessing) return;
    setState(() {
      if (checked ?? false) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
  }

  void _selectAllPending() {
    if (_isProcessing) return;
    setState(() => _selected.addAll(_currentPendingIds));
  }

  Future<void> _openOvertime(OvertimeReviewItem item) async {
    if (_isProcessing) return;
    final status = await Navigator.of(context).pushNamed<RequestStatus>(
      ShellRoutes.overtimeReview,
      arguments: item,
    );
    _showResult(status);
  }

  void _enterSelecting() {
    setState(() {
      _selecting = true;
      _selected.clear();
    });
  }

  void _exitSelecting() {
    if (!_selecting && _selected.isEmpty) return;
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<RequestStatus> _reviewOne(
    String id, {
    required bool approve,
    required String note,
  }) async {
    final user = SessionScope.userOf(context);
    switch (_tab) {
      case 0:
        return (await _leave.review(
          user,
          id: id,
          approve: approve,
          note: note,
        )).request.status;
      case 1:
        return (await _attendance.reviewCorrection(
          user,
          id: id,
          approve: approve,
          note: note,
        )).correction.status;
      case 2:
        return (await _attendance.reviewOutOfArea(
          user,
          id: id,
          approve: approve,
          note: note,
        )).request.status;
      default:
        return (await _overtime.review(
          user,
          id: id,
          approve: approve,
          note: note,
        )).request.status;
    }
  }

  Future<void> _processBulk(bool approve) async {
    final ids = _currentPendingIds.where(_selected.contains).toList();
    if (ids.isEmpty || _isProcessing) return;
    final tabName = switch (_tab) {
      0 => 'cuti/izin',
      1 => 'koreksi',
      2 => 'luar area',
      _ => 'lembur',
    };
    final note = await showReviewDialog(
      context,
      approve: approve,
      subject:
          '${ids.length} pengajuan $tabName yang dipilih '
          'akan ${approve ? 'disetujui' : 'ditolak'} sekaligus.',
    );
    if (note == null || !mounted) return;

    setState(() => _isProcessing = true);
    var ok = 0;
    String? firstError;
    for (final id in ids) {
      try {
        await _reviewOne(id, approve: approve, note: note);
        ok++;
      } on AppException catch (e) {
        firstError ??= e.message;
      } catch (_) {
        firstError ??= 'Tidak dapat terhubung ke server.';
      }
    }
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _selecting = false;
      _selected.clear();
    });
    final verb = approve ? 'disetujui' : 'ditolak';
    unawaited(
      firstError == null
          ? (approve ? AppHaptics.confirm() : AppHaptics.reject())
          : AppHaptics.reject(),
    );
    showAppSnackBar(
      context,
      firstError == null
          ? '$ok pengajuan $verb.'
          : '$ok dari ${ids.length} $verb. Gagal: $firstError',
    );
    await _load();
  }

  Future<void> _deleteHistory({
    required int tab,
    required String id,
    required String name,
  }) async {
    if (_isProcessing) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus riwayat?'),
        content: Text(
          'Riwayat pengajuan  akan dihapus permanen dan tidak '
          'tampil lagi di daftar ini.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isProcessing = true);
    try {
      final user = SessionScope.userOf(context);
      switch (tab) {
        case 0:
          await _leave.delete(user, id: id);
        case 1:
          await _attendance.deleteCorrection(user, id: id);
        case 2:
          await _attendance.deleteOutOfArea(user, id: id);
        default:
          await _overtime.delete(user, id: id);
      }
      if (!mounted) return;
      showAppSnackBar(context, 'Riwayat  dihapus.');
      await _load();
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Persetujuan',
      onRefresh: _load,
      actions: [
        if (_canBulk)
          TextButton.icon(
            onPressed: _isProcessing
                ? null
                : (_selecting ? _exitSelecting : _enterSelecting),
            icon: Icon(
              _selecting ? Icons.close : Icons.checklist_outlined,
              size: 18,
            ),
            label: Text(_selecting ? 'Batal' : 'Pilih'),
          ),
      ],
      child: AsyncBody(
        isLoading: _isLoading,
        error: _error,
        hasData: _leaveItems != null &&
            _correctionItems != null &&
            _outOfAreaItems != null &&
            _overtimeItems != null,
        onRetry: _load,
        loadingLabel: 'Memuat pengajuan…',
        builder: (context) => _buildContent(),
      ),
    );
  }

  List<T> _paged<T>(List<T> items) =>
      items.length <= _historyLimit ? items : items.take(_historyLimit).toList();

  String get _query => _searchController.text.trim().toLowerCase();
  List<LeaveReviewItem> get _leavePending => [
    for (final i in _leaveItems ?? const <LeaveReviewItem>[])
      if (i.request.status == RequestStatus.pending &&
          _matchesName(i.employee.fullName, _query))
        i,
  ];

  List<LeaveReviewItem> get _leaveDone => [
    for (final i in _leaveItems ?? const <LeaveReviewItem>[])
      if (i.request.status != RequestStatus.pending &&
          _matchesName(i.employee.fullName, _query) &&
          _inHistoryRange(i.request.submittedAt))
        i,
  ];

  List<CorrectionReviewItem> get _corrPending => [
    for (final i in _correctionItems ?? const <CorrectionReviewItem>[])
      if (i.correction.status == RequestStatus.pending &&
          _matchesName(i.employee.fullName, _query))
        i,
  ];

  List<CorrectionReviewItem> get _corrDone => [
    for (final i in _correctionItems ?? const <CorrectionReviewItem>[])
      if (i.correction.status != RequestStatus.pending &&
          _matchesName(i.employee.fullName, _query) &&
          _inHistoryRange(i.correction.submittedAt))
        i,
  ];

  List<OutOfAreaReviewItem> get _oaPending => [
    for (final i in _outOfAreaItems ?? const <OutOfAreaReviewItem>[])
      if (i.request.status == RequestStatus.pending &&
          _matchesName(i.employee.fullName, _query))
        i,
  ];

  List<OutOfAreaReviewItem> get _oaDone => [
    for (final i in _outOfAreaItems ?? const <OutOfAreaReviewItem>[])
      if (i.request.status != RequestStatus.pending &&
          _matchesName(i.employee.fullName, _query) &&
          _inHistoryRange(i.request.submittedAt))
        i,
  ];

  List<OvertimeReviewItem> get _otPending => [
    for (final i in _overtimeItems ?? const <OvertimeReviewItem>[])
      if (i.request.status == RequestStatus.pending &&
          _matchesName(i.employee.fullName, _query))
        i,
  ];

  List<OvertimeReviewItem> get _otDone => [
    for (final i in _overtimeItems ?? const <OvertimeReviewItem>[])
      if (i.request.status != RequestStatus.pending &&
          _matchesName(i.employee.fullName, _query) &&
          _inHistoryRange(i.request.submittedAt))
        i,
  ];

  int get _activeDoneCount => switch (_tab) {
    0 => _leaveDone.length,
    1 => _corrDone.length,
    2 => _oaDone.length,
    _ => _otDone.length,
  };
  /// Id menunggu di tab aktif (untuk mode pilih banyak).
  List<String> get _currentPendingIds => switch (_tab) {
    0 => [for (final i in _leavePending) i.request.id],
    1 => [for (final i in _corrPending) i.correction.id],
    2 => [for (final i in _oaPending) i.request.id],
    _ => [for (final i in _otPending) i.request.id],
  };

  Future<void> _pickHistoryDate(bool isFrom) async {
    final initial = isFrom
        ? (_historyFrom ?? DateTime.now())
        : (_historyTo ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (isFrom) {
        _historyFrom = picked;
      } else {
        _historyTo = picked;
      }
      _historyLimit = 20;
    });
  }

  void _loadMoreHistory() => setState(() => _historyLimit += 20);

  bool get _hasMoreHistory => _historyLimit < _activeDoneCount;

  Widget _buildContent() {
    final leavePending = _leavePending;
    final leaveDone = _leaveDone;
    final corrPending = _corrPending;
    final corrDone = _corrDone;
    final oaPending = _oaPending;
    final oaDone = _oaDone;
    final otPending = _otPending;
    final otDone = _otDone;
    final q = _query;

    final textTheme = Theme.of(context).textTheme;

    Widget section<T>({
      required String label,
      required List<T> items,
      required Widget Function(T) row,
      required String emptyTitle,
      required String emptyMessage,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel('$label  ·  ${items.length}'),
          Panel(
            padding: EdgeInsets.zero,
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.inbox_outlined,
                    title: emptyTitle,
                    message: emptyMessage,
                  )
                : Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(),
                        row(items[i]),
                      ],
                    ],
                  ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Cari nama karyawan',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Hapus pencarian',
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_selecting) _BulkPanel(state: this),
        if (_selecting) const SizedBox(height: AppSpacing.md),
        SegmentToggle(
          options: [
            'Cuti & izin (${leavePending.length})',
            'Koreksi Absensi (${corrPending.length})',
            'Absensi Luar Area (${oaPending.length})',
            'Lembur (${otPending.length})',
          ],
          selectedIndex: _tab,
          onSelect: (i) => setState(() {
            _tab = i;
            _selecting = false;
            _selected.clear();
          }),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          SessionScope.userOf(context).role == UserRole.manager
              ? 'Anda memproses pengajuan karyawan berrole Staff.'
              : 'Anda dapat memproses pengajuan semua karyawan, kecuali '
                    'milik Anda sendiri.',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),
         SegmentToggle(
           options: [
              'Menunggu ()',
              'Riwayat ()',
           ],
           selectedIndex: _historyPane,
           onSelect: (i) => setState(() {
             _historyPane = i;
             _historyLimit = 20;
             _selecting = false;
             _selected.clear();
           }),
         ),
         const SizedBox(height: AppSpacing.sm),
         if (_historyPane == 1) ...[
           Wrap(
             spacing: AppSpacing.sm,
             runSpacing: AppSpacing.sm,
             children: [
               _DateChip(
                 label: 'Dari',
                 date: _historyFrom,
                 onTap: () => _pickHistoryDate(true),
               ),
               _DateChip(
                 label: 'Sampai',
                 date: _historyTo,
                 onTap: () => _pickHistoryDate(false),
               ),
               TextButton(
                 onPressed: () => setState(() {
                   _historyFrom =
                       DateTime.now().subtract(const Duration(days: 30));
                   _historyTo = DateTime.now();
                   _historyLimit = 20;
                 }),
                 child: const Text('30 hari terakhir'),
               ),
             ],
           ),
           const SizedBox(height: AppSpacing.sm),
         ],
         if (_historyPane == 0 && _tab == 0)
           section<LeaveReviewItem>(
             label: 'Menunggu persetujuan',
             items: leavePending,
             row: (i) => _LeaveRow(
               item: i,
               onTap: () => _openLeave(i),
               showCheckbox: _selecting,
               checked: _selected.contains(i.request.id),
               onChecked: (v) => _toggleSelect(i.request.id, v),
             ),
             emptyTitle: 'Tidak ada yang menunggu',
             emptyMessage:
                 'Pengajuan cuti, izin, dan sakit baru muncul di sini.',
           ),
         if (_historyPane == 0 && _tab == 1)
           section<CorrectionReviewItem>(
             label: 'Menunggu persetujuan',
             items: corrPending,
             row: (i) => _CorrectionRow(
               item: i,
               onTap: () => _openCorrection(i),
               showCheckbox: _selecting,
               checked: _selected.contains(i.correction.id),
               onChecked: (v) => _toggleSelect(i.correction.id, v),
             ),
             emptyTitle: 'Tidak ada yang menunggu',
             emptyMessage: 'Pengajuan koreksi absensi baru muncul di sini.',
           ),
         if (_historyPane == 0 && _tab == 2)
           section<OutOfAreaReviewItem>(
             label: 'Menunggu persetujuan',
             items: oaPending,
             row: (i) => _OutOfAreaRow(
               item: i,
               onTap: () => _openOutOfArea(i),
               showCheckbox: _selecting,
               checked: _selected.contains(i.request.id),
               onChecked: (v) => _toggleSelect(i.request.id, v),
             ),
             emptyTitle: 'Tidak ada yang menunggu',
             emptyMessage:
                 'Pengajuan clock in/out dari luar area muncul di sini.',
           ),
         if (_historyPane == 0 && _tab == 3)
           section<OvertimeReviewItem>(
             label: 'Menunggu persetujuan',
             items: otPending,
             row: (i) => _OvertimeRow(
               item: i,
               onTap: () => _openOvertime(i),
               showCheckbox: _selecting,
               checked: _selected.contains(i.request.id),
               onChecked: (v) => _toggleSelect(i.request.id, v),
             ),
             emptyTitle: 'Tidak ada yang menunggu',
             emptyMessage: 'Pengajuan lembur baru muncul di sini.',
           ),
         if (_historyPane == 1 && _tab == 0)
           section<LeaveReviewItem>(
             label: 'Riwayat persetujuan',
             items: _paged(leaveDone),
              row: (i) => _LeaveRow(
                item: i,
                onTap: () => _openLeave(i),
                onDelete: _canDeleteHistory
                    ? () => _deleteHistory(
                        tab: 0,
                        id: i.request.id,
                        name: i.employee.fullName,
                      )
                    : null,
              ),
             emptyTitle: 'Tidak ada riwayat',
             emptyMessage:
                 'Riwayat cuti/izin pada rentang tanggal dan nama ini tidak ditemukan.',
           ),
         if (_historyPane == 1 && _tab == 1)
           section<CorrectionReviewItem>(
             label: 'Riwayat persetujuan',
             items: _paged(corrDone),
              row: (i) => _CorrectionRow(
                item: i,
                onTap: () => _openCorrection(i),
                onDelete: _canDeleteHistory
                    ? () => _deleteHistory(
                        tab: 1,
                        id: i.correction.id,
                        name: i.employee.fullName,
                      )
                    : null,
              ),
             emptyTitle: 'Tidak ada riwayat',
             emptyMessage:
                 'Koreksi absensi pada rentang tanggal dan nama ini tidak ditemukan.',
           ),
         if (_historyPane == 1 && _tab == 2)
           section<OutOfAreaReviewItem>(
             label: 'Riwayat persetujuan',
             items: _paged(oaDone),
              row: (i) => _OutOfAreaRow(
                item: i,
                onTap: () => _openOutOfArea(i),
                onDelete: _canDeleteHistory
                    ? () => _deleteHistory(
                        tab: 2,
                        id: i.request.id,
                        name: i.employee.fullName,
                      )
                    : null,
              ),
             emptyTitle: 'Tidak ada riwayat',
             emptyMessage:
                 'Pengajuan absensi luar area pada rentang tanggal dan nama ini tidak ditemukan.',
           ),
         if (_historyPane == 1 && _tab == 3)
           section<OvertimeReviewItem>(
             label: 'Riwayat persetujuan',
             items: _paged(otDone),
              row: (i) => _OvertimeRow(
                item: i,
                onTap: () => _openOvertime(i),
                onDelete: _canDeleteHistory
                    ? () => _deleteHistory(
                        tab: 3,
                        id: i.request.id,
                        name: i.employee.fullName,
                      )
                    : null,
              ),
             emptyTitle: 'Tidak ada riwayat',
             emptyMessage:
                 'Pengajuan lembur pada rentang tanggal dan nama ini tidak ditemukan.',
           ),
         if (_historyPane == 1 && _hasMoreHistory)
           Padding(
             padding: const EdgeInsets.only(top: AppSpacing.sm),
             child: TextButton.icon(
               onPressed: _loadMoreHistory,
               icon: const Icon(Icons.expand_more, size: 18),
               label: Text(
                 'Muat lebih lama '
                 '(${_activeDoneCount - _historyLimit} sisanya)',
               ),
             ),
           ),
      ],
    );
  }
}

class _BulkPanel extends StatelessWidget {
  const _BulkPanel({required this.state});

  final _ApprovalsPageState state;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final selected = state._selected.length;
    final total = state._currentPendingIds.length;
    final busy = state._isProcessing;

    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  selected == 0
                      ? 'Ketuk baris untuk memilih ($total menunggu)'
                      : '$selected dari $total dipilih',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: busy ? null : state._selectAllPending,
                child: const Text('Pilih semua'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: selected == 0 || busy
                      ? null
                      : () => state._processBulk(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.success,
                    foregroundColor: context.isDark
                        ? context.surface
                        : Colors.white,
                    disabledBackgroundColor: context.border,
                    disabledForegroundColor: context.inkTertiary,
                  ),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: Text(
                    busy ? 'Memproses…' : 'Setujui${selected == 0 ? '' : ' ($selected)'}',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: selected == 0 || busy
                      ? null
                      : () => state._processBulk(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.danger,
                    side: const BorderSide(color: AppColors.dangerBorder),
                  ),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Tolak'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.name,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.semanticLabel,
    required this.onTap,
    this.showCheckbox = false,
    this.checked = false,
    this.onChecked,
    this.onDelete,
  });

  final String name;
  final String title;
  final String subtitle;
  final RequestStatus status;
  final String semanticLabel;
  final VoidCallback onTap;

  /// Mode pilih banyak: ketuk baris = centang, bukan buka detail.
  final bool showCheckbox;
  final bool checked;
  final ValueChanged<bool?>? onChecked;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      checked: showCheckbox ? checked : null,
      label: semanticLabel,
      excludeSemantics: true,
      child: InkWell(
        onTap: showCheckbox ? () => onChecked?.call(!checked) : onTap,
        hoverColor: context.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              if (showCheckbox) ...[
                Checkbox(
                  value: checked,
                  onChanged: onChecked,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
              ],
              InitialsAvatar(name: name, size: 34),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      title,
                      style: textTheme.bodySmall?.copyWith(
                        color: context.ink,
                        fontSize: 12.5,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(label: status.label, tone: requestTone(status)),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: context.inkTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaveRow extends StatelessWidget {
  const _LeaveRow({
    required this.item,
    required this.onTap,
    this.showCheckbox = false,
    this.checked = false,
    this.onChecked,
    this.onDelete,
  });

  final LeaveReviewItem item;
  final VoidCallback onTap;
  final bool showCheckbox;
  final bool checked;
  final ValueChanged<bool?>? onChecked;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final r = item.request;
    final range = DateFormatId.dateRange(r.start, r.end);
    final title = '${r.type.label}  ·  ${r.workingDays} hari  ·  $range';
    final subtitle = 'Diajukan ${DateFormatId.shortDateTime(r.submittedAt)}';
    return _ReviewRow(
      name: item.employee.fullName,
      title: title,
      subtitle: subtitle,
      status: r.status,
      showCheckbox: showCheckbox,
      checked: checked,
      onChecked: onChecked,
      onDelete: onDelete,
      semanticLabel:
          '${item.employee.fullName}, ${r.type.label} ${r.workingDays} hari, '
          '$range. Status ${r.status.label}',
      onTap: onTap,
    );
  }
}

class _OutOfAreaRow extends StatelessWidget {
  const _OutOfAreaRow({
    required this.item,
    required this.onTap,
    this.showCheckbox = false,
    this.checked = false,
    this.onChecked,
    this.onDelete,
  });

  final OutOfAreaReviewItem item;
  final VoidCallback onTap;
  final bool showCheckbox;
  final bool checked;
  final ValueChanged<bool?>? onChecked;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final r = item.request;
    final title =
        '${r.kind.label} Absensi Luar Area  ·  ${DateFormatId.time(r.requestedAt)}  ·  '
        '${GeoMath.formatDistance(r.distanceMeters)} dari '
        '${r.nearestLocationName}';
    final subtitle = 'Diajukan ${DateFormatId.shortDateTime(r.submittedAt)}';
    return _ReviewRow(
      name: item.employee.fullName,
      title: title,
      subtitle: subtitle,
      status: r.status,
      showCheckbox: showCheckbox,
      checked: checked,
      onChecked: onChecked,
      onDelete: onDelete,
      semanticLabel:
          '${item.employee.fullName}, pengajuan ${r.kind.label} Absensi Luar Area '
          'pukul ${DateFormatId.time(r.requestedAt)}, '
          '${GeoMath.formatDistance(r.distanceMeters)} dari '
          '${r.nearestLocationName}. Status ${r.status.label}',
      onTap: onTap,
    );
  }
}

class _OvertimeRow extends StatelessWidget {
  const _OvertimeRow({
    required this.item,
    required this.onTap,
    this.showCheckbox = false,
    this.checked = false,
    this.onChecked,
    this.onDelete,
  });

  final OvertimeReviewItem item;
  final VoidCallback onTap;
  final bool showCheckbox;
  final bool checked;
  final ValueChanged<bool?>? onChecked;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final r = item.request;
    final title =
        'Lembur ${DateFormatId.shortDate(r.date)}  ·  ${r.durationLabel}  ·  '
        '${r.timeRangeLabel}';
    final subtitle = 'Diajukan ${DateFormatId.shortDateTime(r.submittedAt)}';
    return _ReviewRow(
      name: item.employee.fullName,
      title: title,
      subtitle: subtitle,
      status: r.status,
      showCheckbox: showCheckbox,
      checked: checked,
      onChecked: onChecked,
      onDelete: onDelete,
      semanticLabel:
          '${item.employee.fullName}, pengajuan lembur '
          '${DateFormatId.shortDate(r.date)}, ${r.durationLabel}. '
          'Status ${r.status.label}',
      onTap: onTap,
    );
  }
}

class _CorrectionRow extends StatelessWidget {
  const _CorrectionRow({
    required this.item,
    required this.onTap,
    this.showCheckbox = false,
    this.checked = false,
    this.onChecked,
    this.onDelete,
  });

  final CorrectionReviewItem item;
  final VoidCallback onTap;
  final bool showCheckbox;
  final bool checked;
  final ValueChanged<bool?>? onChecked;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = item.correction;
    final date = DateFormatId.shortDate(c.date);
    final times =
        '${DateFormatId.time(c.clockIn)} – ${DateFormatId.time(c.clockOut)}';
    return _ReviewRow(
      name: item.employee.fullName,
      title: 'Koreksi Absensi $date  ·  $times',
      subtitle: 'Diajukan ${DateFormatId.shortDateTime(c.submittedAt)}',
      status: c.status,
      showCheckbox: showCheckbox,
      checked: checked,
      onChecked: onChecked,
      onDelete: onDelete,
      semanticLabel:
          '${item.employee.fullName}, koreksi absensi $date menjadi $times. '
          'Status ${c.status.label}',
      onTap: onTap,
    );
  }
}
class _DateChip extends StatelessWidget {
  const _DateChip({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.event_outlined, size: 16),
      label: Text(
        '$label: ${date == null ? '-' : DateFormatId.shortDate(date!)}',
      ),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }
}
