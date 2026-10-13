import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_scope.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/animated_check.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/auth_repository.dart';
import '../../../data/employee_repository.dart';

/// Buat banyak akun sekaligus (Super Admin). Username & password acak,
/// tampil SEKALI untuk dibagikan. Karyawan wajib ganti password + lengkapi
/// data diri saat login pertama. Pop jumlah akun yang dibuat.
class EmployeeBulkPage extends StatefulWidget {
  const EmployeeBulkPage({super.key});

  @override
  State<EmployeeBulkPage> createState() => _EmployeeBulkPageState();
}

class _EmployeeBulkPageState extends State<EmployeeBulkPage> {
  final _formKey = GlobalKey<FormState>();
  final _countController = TextEditingController(text: '5');
  final _linesController = TextEditingController();

  UserRole _role = UserRole.staff;
  Division _division = Division.produksiPrasasti;
  EmploymentStatus _status = EmploymentStatus.contract;
  final _monthsController = TextEditingController(text: '12');

  bool _saving = false;
  String? _error;
  List<EmployeeCredential>? _result;

  @override
  void dispose() {
    _countController.dispose();
    _linesController.dispose();
    _monthsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
      _result = null;
    });
    try {
      final rawLines = _linesController.text
          .split('\\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final accounts = _parseLines(rawLines);
      final created = await AppScope.of(context).employees.createBulk(
            SessionScope.userOf(context),
            accounts: accounts.isEmpty ? null : accounts,
            count: accounts.isEmpty
                ? int.parse(_countController.text.trim())
                : null,
            role: _role,
            division: _division,
            employmentStatus: _status,
            contractMonths: _status.requiresDuration
                ? int.parse(_monthsController.text.trim())
                : null,
          );
      if (!mounted) return;
      unawaited(AppHaptics.confirm());
      setState(() => _result = created);
      await showSuccessSheet(
        context,
        title: 'Akun dibuat',
        message:
            '${created.length} akun dibuat. Bagikan username '
            '& password di bawah — hanya tampil sekali di sini.',
      );
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal membuat akun. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<BulkAccountSpec> _parseLines(List<String> rawLines) {
    final out = <BulkAccountSpec>[];
    for (final line in rawLines) {
      final parts = line.split(':');
      final username = parts.isNotEmpty ? parts.first.trim() : '';
      String? password;
      UserRole? role;
      if (parts.length == 1) {
        password = null;
        role = null;
      } else if (parts.length == 2) {
        final second = parts[1].trim();
        if (second.toLowerCase() == 'staff' ||
            second.toLowerCase() == 'manager') {
          role = second.toLowerCase() == 'staff'
              ? UserRole.staff
              : UserRole.manager;
          password = null;
        } else {
          password = second.isEmpty ? null : second;
          role = null;
        }
      } else {
        password = parts[1].trim().isEmpty ? null : parts[1].trim();
        final r = parts[2].trim().toLowerCase();
        role = r.isEmpty
            ? null
            : (r == 'staff'
                ? UserRole.staff
                : (r == 'manager' ? UserRole.manager : null));
      }
      out.add(
        BulkAccountSpec(
          username: username,
          password: password,
          role: role,
        ),
      );
    }
    return out;
  }

  Future<void> _copyAll() async {
    final result = _result;
    if (result == null) return;
    final buf = StringBuffer('Akun Prasasti Connect\n');
    for (final c in result) {
      buf.writeln('Username: ${c.username} | Password: ${c.temporaryPassword}');
    }
    buf.writeln(
      'Login pertama wajib ganti password & lengkapi data diri.',
    );
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) showAppSnackBar(context, 'Disalin. Bagikan ke karyawan.');
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final result = _result;
    return PageScaffold(
      title: 'Bulk akun',
      maxWidth: 640,
      busy: _saving,
      child: Form(
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
                  TextFormField(
                    controller: _linesController,
                    minLines: 4,
                    maxLines: 12,
                    decoration: const InputDecoration(
                      labelText: 'Daftar akun (opsional)',
                      hintText: 'satu baris per akun: username:password:role\npassword/role boleh kosong (password acak, role default Staff)',
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _linesController,
                    builder: (context, value, _) {
                      final n = value.text
                          .split('\n')
                          .map((e) => e.trim())
                          .where((e) => e.isNotEmpty)
                          .length;
                      if (n == 0) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text('Jumlah akun dari daftar: $n'),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _countController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) {
                      if (_linesController.text.trim().isNotEmpty) {
                        return null;
                      }
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n < 1 || n > 50) {
                        return 'Isi 1-50, atau isi daftar akun di atas.';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Jumlah akun (jika tanpa daftar)',
                      hintText: 'mis. 10',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<UserRole>(
                    initialValue: _role,
                    items: const [
                      DropdownMenuItem(
                        value: UserRole.staff,
                        child: Text('Staff'),
                      ),
                      DropdownMenuItem(
                        value: UserRole.manager,
                        child: Text('Manager'),
                      ),
                    ],
                    onChanged: (r) => setState(() => _role = r ?? _role),
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      prefixIcon: Icon(Icons.badge_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<Division>(
                    initialValue: _division,
                    items: [
                      for (final d in Division.values)
                        DropdownMenuItem(value: d, child: Text(d.label)),
                    ],
                    onChanged: (d) =>
                        setState(() => _division = d ?? _division),
                    decoration: const InputDecoration(
                      labelText: 'Divisi',
                      prefixIcon: Icon(Icons.apartment_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<EmploymentStatus>(
                    initialValue: _status,
                    items: [
                      for (final s in EmploymentStatus.values)
                        DropdownMenuItem(value: s, child: Text(s.label)),
                    ],
                    onChanged: (s) =>
                        setState(() => _status = s ?? _status),
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      prefixIcon: Icon(Icons.work_outline, size: 20),
                    ),
                  ),
                  if (_status.requiresDuration) ...[
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _monthsController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        final max = _status.maxMonths;
                        if (n == null || n < 1 || n > max) {
                          return 'Isi 1–$max bulan.';
                        }
                        return null;
                      },
                      decoration: InputDecoration(
                        labelText: 'Durasi (bulan)',
                        hintText: 'maks. ${_status.maxMonths}',
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Username & password dibuat acak oleh server dan hanya tampil '
              'sekali di bawah. Karyawan wajib mengganti password dan '
              'melengkapi data diri saat login pertama.',
              style: textTheme.bodySmall?.copyWith(height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Buat akun',
              loadingLabel: 'Membuat…',
              isLoading: _saving,
              onPressed: _submit,
            ),
            if (result != null) ...[
              const SizedBox(height: AppSpacing.xl),
              const SectionLabel('Bagikan kredensial'),
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < result.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        dense: true,
                        title: Text(
                          result[i].username,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Password: ${result[i].temporaryPassword}',
                          style: textTheme.bodySmall?.copyWith(
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        trailing: IconButton(
                          tooltip: 'Salin',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text:
                                    'Username: ${result[i].username} | Password: ${result[i].temporaryPassword}',
                              ),
                            );
                            if (context.mounted) {
                              showAppSnackBar(context, 'Disalin.');
                            }
                          },
                          icon: const Icon(Icons.copy, size: 18),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _copyAll,
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Salin semua'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
