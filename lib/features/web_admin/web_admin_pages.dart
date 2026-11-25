import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/picker_field.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/app_exception.dart';
import '../../data/employee_repository.dart';

/// Halaman web-only: tulis absensi karyawan langsung, tanpa pengajuan.
class AttendanceAdjustmentPage extends StatefulWidget {
  const AttendanceAdjustmentPage({super.key});

  @override
  State<AttendanceAdjustmentPage> createState() =>
      _AttendanceAdjustmentPageState();
}

class _AttendanceAdjustmentPageState extends State<AttendanceAdjustmentPage> {
  final _search = TextEditingController();
  bool _initialized = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<EmployeeAccount> _employees = const [];
  EmployeeAccount? _selected;
  DateTime? _date;
  TimeOfDay? _clockIn;
  TimeOfDay? _clockOut;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = SessionScope.userOf(context);
      final rows = await AppScope.of(context).employees.fetchEmployees(user);
      if (!mounted) return;
      setState(() => _employees = rows);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Tidak dapat memuat daftar karyawan.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<EmployeeAccount> get _filtered {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _employees;
    return _employees
        .where((e) =>
            e.fullName.toLowerCase().contains(q) ||
            e.username.toLowerCase().contains(q))
        .toList();
  }

  DateTime? _at(TimeOfDay? t) {
    if (_date == null || t == null) return null;
    return DateTime(_date!.year, _date!.month, _date!.day, t.hour, t.minute);
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: DateTime(today.year - 2),
      lastDate: today,
      helpText: 'Tanggal absensi',
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isIn}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isIn ? _clockIn : _clockOut) ??
          const TimeOfDay(hour: 8, minute: 0),
      helpText: isIn ? 'Jam masuk' : 'Jam pulang',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isIn) {
        _clockIn = picked;
      } else {
        _clockOut = picked;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final start = _at(_clockIn);
    final end = _at(_clockOut);
    if (_selected == null || _date == null || start == null || end == null) {
      setState(() => _error = 'Lengkapi karyawan, tanggal, jam masuk, dan jam pulang.');
      return;
    }
    if (!end.isAfter(start)) {
      setState(() => _error = 'Jam pulang harus setelah jam masuk.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.of(context).attendance.directAdjust(
            SessionScope.userOf(context),
            username: _selected!.username,
            date: _date!,
            clockIn: start,
            clockOut: end,
          );
      if (!mounted) return;
      showAppSnackBar(
        context,
        'Absensi ${_selected!.fullName} tersimpan.',
      );
      setState(() {
        _selected = null;
        _date = null;
        _clockIn = null;
        _clockOut = null;
        _search.clear();
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal menyimpan absensi. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rows = _filtered;

    return PageScaffold(
      title: 'Adjustment absensi',
      maxWidth: 680,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            FormErrorBanner(message: _error!),
            const SizedBox(height: AppSpacing.lg),
          ],
          Panel(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pilih karyawan',
                  style: textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _search,
                  enabled: !_saving,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Cari nama atau username',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                if (_loading) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ] else if (_selected == null) ...[
                  const SizedBox(height: 8),
                  if (rows.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Text('Tidak ada karyawan yang cocok.'),
                    )
                  else
                    SizedBox(
                      height: 320,
                      child: ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final e = rows[i];
                          return ListTile(
                            enabled: !_saving,
                            title: Text(e.fullName),
                            subtitle: Text(
                              '${e.username} · ${e.division.label}',
                            ),
                            onTap: () =>
                                setState(() => _selected = e),
                          );
                        },
                      ),
                    ),
                ] else ...[
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: Text(_selected!.fullName),
                    subtitle: Text(
                      '${_selected!.username} · ${_selected!.division.label}',
                    ),
                    trailing: TextButton(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _selected = null),
                      child: const Text('Ganti'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_selected != null) ...[
            const SizedBox(height: AppSpacing.lg),
            LabeledField(
              label: 'Tanggal',
              child: PickerField(
                valueText: _date == null ? null : DateFormatId.longDate(_date!),
                hint: 'Pilih tanggal',
                icon: Icons.event_outlined,
                enabled: !_saving,
                onTap: _pickDate,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Jam masuk',
                    child: PickerField(
                      valueText: _clockIn?.format(context),
                      hint: 'mis. 08.00',
                      icon: Icons.schedule_outlined,
                      enabled: !_saving,
                      onTap: () => _pickTime(isIn: true),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: LabeledField(
                    label: 'Jam pulang',
                    child: PickerField(
                      valueText: _clockOut?.format(context),
                      hint: 'mis. 17.00',
                      icon: Icons.schedule_outlined,
                      enabled: !_saving,
                      onTap: () => _pickTime(isIn: false),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Simpan absensi',
              loadingLabel: 'Menyimpan…',
              isLoading: _saving,
              onPressed: _save,
            ),
          ],
        ],
      ),
    );
  }
}

/// Halaman web-only: buat akun testing tanpa data diri lengkap.
class TestingAccountPage extends StatefulWidget {
  const TestingAccountPage({super.key});

  @override
  State<TestingAccountPage> createState() => _TestingAccountPageState();
}

class _TestingAccountPageState extends State<TestingAccountPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _initialized = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<String> _divisions = const [];
  Map<String, String> _divisionLabels = const {};
  String? _division;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = SessionScope.userOf(context);
      final rows = await AppScope.of(context).master.fetchDivisions(user);
      if (!mounted) return;
      final usable = rows.where((d) => d.active).toList();
      final active = usable.map((d) => d.code).toList();
      setState(() {
        _divisions = active;
        _divisionLabels = {
          for (final d in usable) d.code: d.label,
        };
        if (active.isNotEmpty && !active.contains(_division)) {
          _division = active.first;
        }
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Tidak dapat memuat daftar divisi.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.of(context).employees.createTestingAccount(
            SessionScope.userOf(context),
            username: _username.text.trim(),
            password: _password.text,
            division: _division!,
          );
      if (!mounted) return;
      showAppSnackBar(context, 'Akun testing ${_username.text.trim()} dibuat.');
      _username.clear();
      _password.clear();
      _formKey.currentState?.reset();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal membuat akun. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Buat akun testing',
      maxWidth: 560,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              FormErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            LabeledField(
              label: 'Username',
              child: TextFormField(
                controller: _username,
                enabled: !_saving,
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.length < 3) return 'Username minimal 3 karakter';
                  return null;
                },
                decoration: const InputDecoration(
                  hintText: 'mis. testing01',
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            LabeledField(
              label: 'Password',
              child: TextFormField(
                controller: _password,
                enabled: !_saving,
                obscureText: true,
                validator: (v) {
                  if ((v ?? '').length < 6) return 'Password minimal 6 karakter';
                  return null;
                },
                decoration: const InputDecoration(
                  hintText: 'Minimal 6 karakter',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            LabeledField(
              label: 'Divisi',
              child: _loading
                  ? const LinearProgressIndicator()
                  : DropdownButtonFormField<String>(
                      initialValue: _division,
                      items: [
                        for (final code in _divisions)
                          DropdownMenuItem(
                            value: code,
                            child: Text(_divisionLabels[code] ?? code),
                          ),
                      ],
                      onChanged: _saving ? null : (v) => setState(() => _division = v),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.business_outlined),
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Buat akun',
              loadingLabel: 'Membuat…',
              isLoading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
