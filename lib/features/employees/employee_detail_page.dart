import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/push_notifications.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/initials_avatar.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/role_badge.dart';
import '../../data/auth_repository.dart';
import '../../data/employee_repository.dart';
import '../shell/shell_routes.dart';
import 'widgets/temporary_password_dialog.dart';

/// Detail akun karyawan + aksi kelola (ubah, reset password,
/// nonaktifkan/aktifkan) sesuai hak yang dikirim server.
class EmployeeDetailPage extends StatefulWidget {
  const EmployeeDetailPage({super.key, required this.initial});

  final EmployeeAccount initial;

  @override
  State<EmployeeDetailPage> createState() => _EmployeeDetailPageState();
}

class _EmployeeDetailPageState extends State<EmployeeDetailPage> {
  late EmployeeRepository _repo;
  bool _initialized = false;

  late EmployeeAccount _employee = widget.initial;
  String? _error;
  bool _isBusy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).employees;
    _repo.changes.addListener(_onChanged);
    AppRefresh.employees.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _repo.changes.removeListener(_onChanged);
    AppRefresh.employees.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final e = await _repo.fetchEmployee(
        SessionScope.userOf(context),
        username: widget.initial.username,
      );
      if (mounted) setState(() => _employee = e);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Data karyawan gagal dimuat. Coba lagi.');
      }
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context)
        .pushNamed<bool>(ShellRoutes.employeeForm, arguments: _employee);
    if (saved == true && mounted) {
      showAppSnackBar(context, 'Data karyawan diperbarui.');
    }
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String action,
    bool danger = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
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
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 44),
              backgroundColor: danger ? context.danger : null,
              foregroundColor: danger
                  ? (context.isDark ? context.surface : Colors.white)
                  : null,
            ),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await action();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _resetPassword() async {
    final e = _employee;
    final ok = await _confirm(
      title: 'Reset password?',
      message:
          'Password ${e.fullName} akan diganti dengan password sementara '
          'baru. Password lama tidak berlaku lagi.',
      action: 'Reset password',
    );
    if (!ok || !mounted) return;
    await _run(() async {
      final password = await _repo.resetPassword(
        SessionScope.userOf(context),
        username: e.username,
      );
      if (!mounted) return;
      await showTemporaryPasswordDialog(
        context,
        title: 'Password direset',
        fullName: e.fullName,
        username: e.username,
        password: password,
      );
    });
  }

  Future<void> _toggleActive() async {
    final e = _employee;
    final deactivate = e.active;
    final ok = await _confirm(
      title: deactivate ? 'Nonaktifkan akun?' : 'Aktifkan kembali akun?',
      message: deactivate
          ? '${e.fullName} tidak akan bisa masuk ke Prasasti Connect dan '
                'tidak lagi muncul di daftar pembaca pengumuman. Data '
                'absensi & cuti tetap tersimpan.'
          : '${e.fullName} dapat masuk kembali dengan password terakhirnya.',
      action: deactivate ? 'Nonaktifkan' : 'Aktifkan',
      danger: deactivate,
    );
    if (!ok || !mounted) return;
    await _run(() async {
      final updated = await _repo.setActive(
        SessionScope.userOf(context),
        username: e.username,
        active: !deactivate,
      );
      if (!mounted) return;
      setState(() => _employee = updated);
      showAppSnackBar(
        context,
        deactivate ? 'Akun dinonaktifkan.' : 'Akun diaktifkan kembali.',
      );
    });
  }

  static Widget _optionalRow(
    BuildContext context,
    TextTheme textTheme,
    String label,
    String? value,
  ) {
    return InfoRow(
      label: label,
      value: value ?? 'Belum diisi',
      valueStyle: value == null
          ? textTheme.bodyMedium?.copyWith(color: context.inkTertiary)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = SessionScope.userOf(context);
    final textTheme = Theme.of(context).textTheme;
    final e = _employee;
    final isSelf = e.username == me.username;
    final hasActions = e.canEdit || e.canResetPassword || e.canChangeStatus;

    return PopScope(
      canPop: !_isBusy,
      child: PageScaffold(
        title: 'Detail karyawan',
        maxWidth: 720,
        busy: _isBusy,
        onRefresh: _load,
        actions: [
          if (e.canEdit)
            TextButton.icon(
              onPressed: _isBusy ? null : _edit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Ubah'),
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              FormErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            Panel(
              child: Row(
                children: [
                  PhotoAvatar(
                    name: e.fullName,
                    photoUrl: e.photoUrl,
                    size: 56,
                    muted: !e.active,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            e.fullName,
                            style: textTheme.titleMedium?.copyWith(
                              fontSize: 20,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${e.position} · ${e.division.label}',
                          style: textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            RoleBadge(role: e.role),
                            StatusChip(
                              label: e.active ? 'Aktif' : 'Nonaktif',
                              tone: e.active
                                  ? ChipTone.success
                                  : ChipTone.danger,
                            ),
                            if (isSelf)
                              const StatusChip(
                                label: 'Akun Anda',
                                tone: ChipTone.accent,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Kepegawaian'),
                  InfoRow(label: 'ID karyawan', value: e.employeeId),
                  InfoRow(label: 'Jabatan', value: e.position),
                  InfoRow(label: 'Divisi', value: e.division.label),
                  InfoRow(
                    label: 'Atasan langsung',
                    value: e.managerName ?? '—',
                  ),
                  InfoRow(
                    label: 'Status',
                    value: e.employmentStatus.displayLabel(e.contractMonths),
                  ),
                  InfoRow(
                    label: 'Bergabung sejak',
                    value: DateFormatId.dayMonthYear(e.joinDate),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Kontak & identitas'),
                  InfoRow(label: 'Username', value: e.username),
                  InfoRow(label: 'Email', value: e.email),
                  InfoRow(label: 'Telepon', value: e.phone),
                  InfoRow(
                    label: 'NIK',
                    value: e.nikMasked,
                    valueStyle: textTheme.bodyMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  _optionalRow(
                    context,
                    textTheme,
                    'Jenis kelamin',
                    e.gender?.label,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Alamat & kontak darurat'),
                  if (!e.hasPrivateData)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Hanya terlihat oleh yang berhak mengelola akun '
                        '${e.role.label}.',
                        style: textTheme.bodySmall?.copyWith(height: 1.5),
                      ),
                    )
                  else ...[
                    _optionalRow(
                      context,
                      textTheme,
                      'Tempat lahir',
                      e.birthPlace,
                    ),
                    _optionalRow(
                      context,
                      textTheme,
                      'Tanggal lahir',
                      e.birthDate == null
                          ? null
                          : DateFormatId.dayMonthYear(e.birthDate!),
                    ),
                    _optionalRow(context, textTheme, 'Alamat', e.address),
                    if (e.emergencyContact case final ec?) ...[
                      InfoRow(label: 'Kontak darurat', value: ec.name),
                      InfoRow(label: 'Hubungan', value: ec.relation.label),
                      InfoRow(label: 'Nomor darurat', value: ec.phone),
                    ] else
                      _optionalRow(
                        context,
                        textTheme,
                        'Kontak darurat',
                        null,
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 6),
                      child: Text(
                        'Diperbarui karyawan sendiri lewat Profil, atau lewat '
                        'tombol Ubah di halaman ini.',
                        style: textTheme.bodySmall?.copyWith(fontSize: 12.5),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (e.canResetPassword || e.canChangeStatus)
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  if (e.canResetPassword)
                    OutlinedButton.icon(
                      onPressed: _isBusy ? null : _resetPassword,
                      icon: const Icon(Icons.lock_reset, size: 18),
                      label: const Text('Reset password'),
                    ),
                  if (e.canChangeStatus)
                    OutlinedButton.icon(
                      onPressed: _isBusy ? null : _toggleActive,
                      style: e.active
                          ? OutlinedButton.styleFrom(
                              foregroundColor: context.danger,
                              side: const BorderSide(
                                color: AppColors.dangerBorder,
                              ),
                            )
                          : null,
                      icon: Icon(
                        e.active
                            ? Icons.person_off_outlined
                            : Icons.person_outline,
                        size: 18,
                      ),
                      label: Text(
                        e.active ? 'Nonaktifkan akun' : 'Aktifkan akun',
                      ),
                    ),
                ],
              ),
            if (!hasActions || isSelf) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                isSelf
                    ? 'Ini akun Anda. Role, status, dan password akun sendiri '
                          'tidak bisa diubah dari sini — gunakan Profil › '
                          'Ganti password.'
                    : me.role == UserRole.manager
                    ? 'Manager hanya dapat mengelola akun berrole Staff. '
                          'Hubungi Super Admin untuk akun ini.'
                    : 'Anda tidak memiliki akses untuk mengelola akun ini.',
                style: textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
