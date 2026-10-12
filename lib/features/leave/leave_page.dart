import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/segment_toggle.dart';
import '../../data/auth_repository.dart';
import '../../data/leave_repository.dart';
import '../../data/overtime_repository.dart';
import '../attendance/attendance_presentation.dart';
import '../shell/shell_routes.dart';

/// Saldo cuti + riwayat pengajuan cuti/izin/sakit + riwayat lembur.
class LeavePage extends StatefulWidget {
  const LeavePage({super.key});

  @override
  State<LeavePage> createState() => _LeavePageState();
}

class _LeavePageState extends State<LeavePage> {
  late LeaveRepository _repo;
  late OvertimeRepository _overtimeRepo;
  bool _initialized = false;
  final _searchController = TextEditingController();

  LeaveBalance? _balance;
  List<LeaveRequest>? _requests;
  List<OvertimeRequest>? _overtimes;
  bool _isLoading = false;
  String? _error;
  LeaveType? _typeFilter;
  RequestStatus? _statusFilter;
  int _tab = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).leave;
    _overtimeRepo = AppScope.of(context).overtime;
    _repo.changes.addListener(_onChanged);
    _overtimeRepo.changes.addListener(_onChanged);
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _repo.changes.removeListener(_onChanged);
    _overtimeRepo.changes.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(LeaveRequest r, String q) {
    if (q.isNotEmpty &&
        !'${r.type.label} ${r.reason}'.toLowerCase().contains(q)) {
      return false;
    }
    if (_typeFilter != null && r.type != _typeFilter) return false;
    if (_statusFilter != null && r.status != _statusFilter) return false;
    return true;
  }

  void _onChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final user = SessionScope.userOf(context);
      final results = await Future.wait([
        _repo.fetchBalance(user),
        _repo.fetchRequests(user),
        _overtimeRepo.fetchRequests(user),
      ]);
      if (!mounted) return;
      setState(() {
        _balance = results[0] as LeaveBalance;
        _requests = results[1] as List<LeaveRequest>;
        _overtimes = results[2] as List<OvertimeRequest>;
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Data pengajuan gagal dimuat. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openForm() async {
    final sent = await Navigator.of(context)
        .pushNamed<bool>(ShellRoutes.leaveForm, arguments: _balance);
    // Lembar sukses sudah tampil di formulir; daftar memuat ulang otomatis.
    if (sent == true && mounted) {
      await _load();
    }
  }

  Future<void> _openOvertimeForm() async {
    final sent = await Navigator.of(context)
        .pushNamed<bool>(ShellRoutes.overtimeForm);
    if (sent == true && mounted) {
      await _load();
    }
  }

  Future<void> _openCollective() async {
    final applied = await Navigator.of(
      context,
    ).pushNamed<bool>(ShellRoutes.collectiveLeave);
    if (applied == true && mounted) {
      await _load();
    }
  }

  void _openDetail(LeaveRequest request) {
    Navigator.of(context)
        .pushNamed(ShellRoutes.leaveDetail, arguments: request);
  }

  void _openOvertimeDetail(OvertimeRequest request) {
    Navigator.of(context)
        .pushNamed(ShellRoutes.overtimeDetail, arguments: request);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = AppSpacing.isSidebarLayout(MediaQuery.sizeOf(context).width);
    final onLeaveTab = _tab == 0;
    final isSuperAdmin =
        SessionScope.userOf(context).role == UserRole.superadmin;

    return PageScaffold(
      title: 'Pengajuan',
      onRefresh: _load,
      actions: [
        if (isSuperAdmin && onLeaveTab)
          TextButton.icon(
            onPressed: _openCollective,
            icon: const Icon(Icons.beach_access_outlined, size: 18),
            label: const Text('Cuti bersama'),
          ),
        if (isWide)
          FilledButton.icon(
            onPressed: onLeaveTab
                ? (_balance == null ? null : _openForm)
                : _openOvertimeForm,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ajukan'),
          )
        else
          TextButton.icon(
            onPressed: onLeaveTab
                ? (_balance == null ? null : _openForm)
                : _openOvertimeForm,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Ajukan'),
          ),
      ],
      child: AsyncBody(
        isLoading: _isLoading,
        error: _error,
        hasData: _balance != null &&
            _requests != null &&
            _overtimes != null,
        onRetry: _load,
        loadingLabel: 'Memuat pengajuan…',
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentToggle(
              options: const ['Cuti & izin', 'Lembur'],
              selectedIndex: _tab,
              onSelect: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (onLeaveTab) _buildLeave() else _buildOvertime(),
          ],
        ),
      ),
    );
  }

  Widget _buildLeave() {
    final q = _searchController.text.trim().toLowerCase();
    final shown = [
      for (final r in _requests!)
        if (_matches(r, q)) r,
    ];
    final filtering =
        q.isNotEmpty || _typeFilter != null || _statusFilter != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BalancePanel(balance: _balance!),
        const SizedBox(height: 28),
        const SectionLabel('Riwayat pengajuan'),
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Cari alasan atau jenis',
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
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<LeaveType?>(
                      initialValue: _typeFilter,
                      items: [
                        const DropdownMenuItem<LeaveType?>(
                          value: null,
                          child: Text('Semua jenis'),
                        ),
                        for (final t in LeaveType.values)
                          DropdownMenuItem<LeaveType?>(
                            value: t,
                            child: Text(t.label),
                          ),
                      ],
                      onChanged: (t) => setState(() => _typeFilter = t),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(
                          Icons.category_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: DropdownButtonFormField<RequestStatus?>(
                      initialValue: _statusFilter,
                      items: [
                        const DropdownMenuItem<RequestStatus?>(
                          value: null,
                          child: Text('Semua status'),
                        ),
                        for (final s in RequestStatus.values)
                          DropdownMenuItem<RequestStatus?>(
                            value: s,
                            child: Text(s.label),
                          ),
                      ],
                      onChanged: (s) => setState(() => _statusFilter = s),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.flag_outlined, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              if (shown.isEmpty)
                Panel(
                  padding: EdgeInsets.zero,
                  child: EmptyState(
                    icon: Icons.event_available_outlined,
                    title: filtering
                        ? 'Tidak ada yang cocok'
                        : 'Belum ada pengajuan',
                    message: filtering
                        ? 'Coba kata kunci atau filter lain.'
                        : 'Pengajuan cuti, izin, atau sakit akan muncul di sini.',
                  ),
                )
              else
                Panel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < shown.length; i++) ...[
                        if (i > 0) const Divider(),
                        _RequestRow(
                          request: shown[i],
                          onTap: () => _openDetail(shown[i]),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
  }

  Widget _buildOvertime() {
    final items = _overtimes!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Riwayat lembur'),
        if (items.isEmpty)
          const Panel(
            padding: EdgeInsets.zero,
            child: EmptyState(
              icon: Icons.schedule_outlined,
              title: 'Belum ada lembur',
              message: 'Pengajuan lembur yang sudah dikerjakan muncul di sini.',
            ),
          )
        else
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(),
                  _OvertimeRow(
                    request: items[i],
                    onTap: () => _openOvertimeDetail(items[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _BalancePanel extends StatelessWidget {
  const _BalancePanel({required this.balance});

  final LeaveBalance balance;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final b = balance;
    final rest = b.quota - b.used - b.pending;

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CUTI TAHUNAN ${b.year}', style: textTheme.labelSmall),
          const SizedBox(height: 8),
          Semantics(
            label: 'Sisa cuti tahunan ${b.remaining} dari ${b.quota} hari',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                text: '${b.remaining}',
                style: TextStyle(
                  fontSize: 34,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: context.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                children: [
                  TextSpan(
                    text: '  dari ${b.quota} hari tersisa',
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Row(
                  children: [
                    if (b.used > 0)
                      Expanded(
                        flex: b.used,
                        child: const ColoredBox(color: AppColors.accent),
                      ),
                    if (b.pending > 0)
                      Expanded(
                        flex: b.pending,
                        child: ColoredBox(
                          color: AppColors.accent.withValues(alpha: 0.35),
                        ),
                      ),
                    if (rest > 0)
                      Expanded(
                        flex: rest,
                        child: ColoredBox(color: context.border),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _Legend(color: AppColors.accent, text: '${b.used} hari terpakai'),
              if (b.pending > 0)
                _Legend(
                  color: AppColors.accent.withValues(alpha: 0.35),
                  text: '${b.pending} hari menunggu persetujuan',
                ),
              _Legend(
                color: context.border,
                text: '${b.available} hari bisa diajukan',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(fontSize: 12.5),
        ),
      ],
    );
  }
}

class _RequestRow extends StatelessWidget {
  const _RequestRow({required this.request, required this.onTap});

  final LeaveRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final r = request;
    final range = DateFormatId.dateRange(r.start, r.end);

    return Semantics(
      button: true,
      label:
          '${r.type.label}, ${r.workingDays} hari, $range. '
          'Status ${r.status.label}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        hoverColor: context.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.type.label}  ·  ${r.workingDays} hari',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      range,
                      style: textTheme.bodySmall?.copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(label: r.status.label, tone: requestTone(r.status)),
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

class _OvertimeRow extends StatelessWidget {
  const _OvertimeRow({required this.request, required this.onTap});

  final OvertimeRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final r = request;

    return Semantics(
      button: true,
      label:
          'Lembur ${DateFormatId.shortDate(r.date)}, ${r.durationLabel}, '
          '${r.timeRangeLabel}. Status ${r.status.label}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        hoverColor: context.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${DateFormatId.shortDate(r.date)}  ·  ${r.durationLabel}',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      r.timeRangeLabel,
                      style: textTheme.bodySmall?.copyWith(fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusChip(label: r.status.label, tone: requestTone(r.status)),
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
