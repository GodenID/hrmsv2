import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/segment_toggle.dart';
import '../../data/app_exception.dart';
import '../../data/auth_repository.dart';
import '../../data/employee.dart';
import '../../data/warning_repository.dart';

/// Form penerbitan SP. Hanya Super Admin (dijaga ganda: tombol "Buat SP"
/// hanya tampil untuk Super Admin, server menolak selainnya).
/// Pop `true` bila SP berhasil diterbitkan.
class WarningFormPage extends StatefulWidget {
  const WarningFormPage({super.key});

  @override
  State<WarningFormPage> createState() => _WarningFormPageState();
}

class _WarningFormPageState extends State<WarningFormPage> {
  final _formKey = GlobalKey<FormState>();
  late WarningRepository _repo;
  bool _initialized = false;

  bool _loadingMaster = true;
  String? _masterError;
  List<EmployeeRef> _employees = [];

  EmployeeRef? _employee;
  WarningSeverity _severity = WarningSeverity.ringan;
  WarningSuggestion? _suggestion;
  bool _loadingSuggestion = false;
  int _level = 1;
  DateTime _incidentDate = DateTime.now();
  final _violationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _articleController = TextEditingController();
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).warnings;
    _loadMaster();
  }

  @override
  void dispose() {
    _violationController.dispose();
    _descriptionController.dispose();
    _articleController.dispose();
    super.dispose();
  }

  Future<void> _loadMaster() async {
    setState(() {
      _loadingMaster = true;
      _masterError = null;
    });
    try {
      final user = SessionScope.userOf(context);
      final employees = await _repo.fetchIssuableEmployees(user);
      if (mounted) {
        setState(() => _employees = employees);
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _masterError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _masterError = 'Data gagal dimuat. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _loadingMaster = false);
    }
  }

  Future<void> _onEmployeeChanged(EmployeeRef? employee) async {
    setState(() {
      _employee = employee;
      _suggestion = null;
    });
    if (employee == null) return;
    setState(() => _loadingSuggestion = true);
    try {
      final suggestion = await _repo.suggestLevel(
        SessionScope.userOf(context),
        username: employee.username,
      );
      if (mounted) {
        setState(() {
          _suggestion = suggestion;
          _level = suggestion.suggestedLevel;
        });
      }
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Saran tingkat gagal dimuat.');
    } finally {
      if (mounted) setState(() => _loadingSuggestion = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _incidentDate.isAfter(today) ? today : _incidentDate,
      firstDate: today.subtract(
        const Duration(days: WarningRules.maxIncidentDaysBack),
      ),
      lastDate: today,
      helpText: 'Tanggal kejadian',
    );
    if (picked != null && mounted) setState(() => _incidentDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_employee == null) return;
    setState(() => _saving = true);
    try {
      await _repo.issue(
        SessionScope.userOf(context),
        username: _employee!.username,
        violationName: _violationController.text,
        severity: _severity,
        level: _level,
        incidentDate: _incidentDate,
        description: _descriptionController.text,
        articleRef: _articleController.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Gagal menerbitkan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final suggestion = _suggestion;

    return PageScaffold(
      title: 'Buat SP',
      maxWidth: 720,
      busy: _saving,
      child: AsyncBody(
        isLoading: _loadingMaster,
        error: _masterError,
        hasData: true,
        onRetry: _loadMaster,
        loadingLabel: 'Memuat data…',
        builder: (context) => Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<EmployeeRef>(
                      initialValue: _employee,
                      decoration: const InputDecoration(
                        labelText: 'Karyawan',
                      ),
                      items: [
                        for (final e in _employees)
                          DropdownMenuItem(
                            value: e,
                            child: Text(
                              e.fullName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      validator: (v) =>
                          v == null ? 'Pilih karyawan.' : null,
                      onChanged: _onEmployeeChanged,
                    ),
                    if (_loadingSuggestion) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (suggestion != null) ...[
                      const SizedBox(height: 12),
                      _SuggestionBanner(
                        suggestion: suggestion,
                        employeeName: _employee?.fullName ?? '',
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Tingkat',
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SegmentToggle(
                      options: const ['SP 1', 'SP 2', 'SP 3'],
                      selectedIndex: _level - 1,
                      onSelect: (i) => setState(() => _level = i + 1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _violationController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nama pelanggaran',
                        hintText:
                            'mis. Terlambat masuk kerja tanpa keterangan',
                      ),
                      validator: (v) => WarningRules.validateViolationName(
                        v ?? '',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Kategori',
                      style: textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SegmentToggle(
                      options: [
                        for (final s in WarningSeverity.values) s.label,
                      ],
                      selectedIndex: WarningSeverity.values.indexOf(
                        _severity,
                      ),
                      onSelect: (i) => setState(
                        () => _severity = WarningSeverity.values[i],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _articleController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Pasal peraturan',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Pasal peraturan wajib diisi.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Tanggal kejadian',
                          suffixIcon: Icon(
                            Icons.calendar_month_outlined,
                            size: 20,
                          ),
                        ),
                        child: Text(
                          DateFormatId.shortDate(_incidentDate),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descriptionController,
                      minLines: 4,
                      maxLines: 8,
                      maxLength: WarningRules.maxDescription,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Uraian kejadian',
                        hintText:
                            'Tulis kronologi yang jelas: kapan, di mana, apa yang terjadi…',
                        alignLabelWithHint: true,
                      ),
                      validator: (v) => WarningRules.validateDescription(
                        v ?? '',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.danger,
                  foregroundColor: context.isDark
                      ? context.surface
                      : Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _saving ? null : _save,
                child: const Text('Terbitkan SP'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Banner saran eskalasi + peringatan bila sudah memenuhi syarat PHK.
class _SuggestionBanner extends StatelessWidget {
  const _SuggestionBanner({
    required this.suggestion,
    required this.employeeName,
  });

  final WarningSuggestion suggestion;
  final String employeeName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (suggestion.phkEligible) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: context.danger.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          '$employeeName masih memiliki SP 3 yang aktif. Pelanggaran baru '
          'ini memenuhi syarat PHK menurut ketentuan bertahap — pastikan '
          'berkas & prosedur bipartit lengkap sebelum memutuskan.',
          style: textTheme.bodySmall?.copyWith(
            color: context.danger,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (suggestion.activeCount == 0) {
      return Text(
        '$employeeName tidak memiliki SP aktif. Tingkat yang disarankan: SP 1.',
        style: textTheme.bodySmall?.copyWith(
          color: context.inkSecondary,
        ),
      );
    }
    return Text(
      '$employeeName memiliki ${suggestion.activeCount} SP aktif. '
      'Tingkat yang disarankan: SP ${suggestion.suggestedLevel}.',
      style: textTheme.bodySmall?.copyWith(
        color: context.inkSecondary,
      ),
    );
  }
}
