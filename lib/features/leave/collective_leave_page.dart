import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../../core/widgets/animated_check.dart';
import '../../core/widgets/brand_loading.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/app_exception.dart';
import '../../data/auth_repository.dart';
import '../../data/employee_repository.dart';
import '../../data/leave_repository.dart';

/// Potong cuti bersama massal. Hanya Super Admin (dijaga ganda: tombol
/// masuk hanya tampil untuk Super Admin, server menolak selainnya).
/// Pop `true` bila minimal satu karyawan terpotong.
class CollectiveLeavePage extends StatefulWidget {
  const CollectiveLeavePage({super.key});

  @override
  State<CollectiveLeavePage> createState() => _CollectiveLeavePageState();
}

class _CollectiveLeavePageState extends State<CollectiveLeavePage> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController(
    text: 'Cuti bersama',
  );
  final _searchController = TextEditingController();

  bool _loading = true;
  String? _loadError;
  List<EmployeeAccount> _employees = [];
  final _selected = <String>{};

  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final user = SessionScope.userOf(context);
      final all = await AppScope.of(
        context,
      ).employees.fetchEmployees(user);
      if (!mounted) return;
      setState(() {
        _employees = [
          for (final e in all)
            if (e.active) e,
        ];
        _selected.addAll([for (final e in _employees) e.username]);
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'Daftar karyawan gagal dimuat.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _days => WorkCalendar.workingDaysBetween(_start, _end);

  List<EmployeeAccount> get _shown {
    final q = _searchController.text.trim().toLowerCase();
    return [
      for (final e in _employees)
        if (q.isEmpty ||
            e.fullName.toLowerCase().contains(q) ||
            e.username.contains(q))
          e,
    ];
  }

  Future<void> _pick(bool isStart) async {
    final initial = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(
        const Duration(days: LeaveRules.maxDaysAhead),
      ),
      helpText: isStart ? 'Tanggal mulai' : 'Tanggal selesai',
    );
    if (picked == null || !mounted) return;
    setState(() {
      final d = WorkCalendar.dateOnly(picked);
      if (isStart) {
        _start = d;
        if (_end.isBefore(d)) _end = d;
      } else {
        _end = d;
        if (_start.isAfter(d)) _start = d;
      }
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selected.isEmpty) {
      setState(() => _error = 'Pilih minimal satu karyawan.');
      return;
    }
    if (_days == 0) {
      setState(
        () => _error = 'Rentang tanggal hanya berisi akhir pekan.',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Potong cuti bersama?'),
        content: Text(
          '${_selected.length} karyawan × $_days hari kerja '
          '(${DateFormatId.dateRange(_start, _end)}) akan dipotong dari '
          'cuti tahunan masing-masing. Tiap karyawan menerima notifikasi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: context.inkSecondary,
            ),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Potong'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final results = await AppScope.of(context).leave.applyCollectiveLeave(
        SessionScope.userOf(context),
        usernames: _selected.toList(),
        start: _start,
        end: _end,
        reason: _reasonController.text,
      );
      if (!mounted) return;
      final ok = results.where((r) => r.applied).toList();
      final skipped = results.where((r) => !r.applied).toList();
      final totalDays = ok.fold<int>(0, (sum, r) => sum + r.days);
      await showSuccessSheet(
        context,
        title: 'Cuti bersama diterapkan',
        message:
            '${ok.length} karyawan terpotong (total $totalDays hari).'
            '${skipped.isEmpty ? '' : ' ${skipped.length} dilewati.'}',
      );
      if (!mounted) return;
      if (skipped.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Dilewati'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final r in skipped)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${r.employee.fullName}: ${r.skipped}',
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Tutup'),
              ),
            ],
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(ok.isNotEmpty);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Gagal memproses. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PageScaffold(
      title: 'Cuti bersama',
      maxWidth: 640,
      busy: _saving,
      child: _loading
          ? const SkeletonList(semanticLabel: 'Memuat karyawan…')
          : _loadError != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FormErrorBanner(message: _loadError!),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Coba lagi'),
                ),
              ],
            )
          : Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) ...[
                    FormErrorBanner(message: _error!),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _DateButton(
                                label: 'Mulai',
                                date: _start,
                                onTap: () => _pick(true),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: _DateButton(
                                label: 'Selesai',
                                date: _end,
                                onTap: () => _pick(false),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _reasonController,
                          textCapitalization: TextCapitalization.sentences,
                          maxLength: 120,
                          validator: (v) =>
                              (v == null || v.trim().length < 5)
                              ? 'Alasan minimal 5 karakter.'
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'Nama cuti bersama',
                            hintText: 'mis. Cuti bersama Natal',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _days == 0
                              ? 'Rentang ini hanya berisi akhir pekan.'
                              : 'Otomatis memotong $_days hari kerja '
                                    '(${DateFormatId.dateRange(_start, _end)}). '
                                    'Sabtu–Minggu tidak dihitung.',
                          style: textTheme.bodySmall?.copyWith(
                            color: _days == 0
                                ? context.danger
                                : context.inkSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Karyawan (${_selected.length}/${_employees.length})',
                          style: textTheme.labelLarge,
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(
                          () => _selected.length == _employees.length
                              ? _selected.clear()
                              : _selected.addAll(
                                  [for (final e in _employees) e.username],
                                ),
                        ),
                        child: Text(
                          _selected.length == _employees.length
                              ? 'Batal semua'
                              : 'Pilih semua',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Cari nama',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon:
                          _searchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Hapus pencarian',
                              onPressed: _searchController.clear,
                              icon: const Icon(Icons.close, size: 18),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < _shown.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          CheckboxListTile(
                            value: _selected.contains(_shown[i].username),
                            onChanged: (v) => setState(
                              () => v == true
                                  ? _selected.add(_shown[i].username)
                                  : _selected.remove(_shown[i].username),
                            ),
                            title: Text(
                              _shown[i].fullName,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${_shown[i].position} · ${_shown[i].role.label}',
                              style: textTheme.bodySmall,
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                          ),
                        ],
                        if (_shown.isEmpty)
                          const EmptyState(
                            icon: Icons.search_off_outlined,
                            title: 'Tidak ada yang cocok',
                            message: 'Coba kata kunci lain.',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Potong cuti bersama',
                    loadingLabel: 'Memproses…',
                    isLoading: _saving,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
    );
  }
}

class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.label,
    required this.date,
    required this.onTap,
  });

  final String label;
  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_month_outlined, size: 20),
        ),
        child: Text(DateFormatId.shortDate(date)),
      ),
    );
  }
}
