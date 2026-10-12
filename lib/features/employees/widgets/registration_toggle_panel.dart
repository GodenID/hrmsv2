import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/widgets/loading_row.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/app_exception.dart';

/// Saklar buka / tutup pendaftaran akun mandiri (hanya Super Admin).
/// Tutup bila semua karyawan sudah terdaftar; tombol "Daftar akun" di
/// halaman masuk ikut tersembunyi.
class RegistrationTogglePanel extends StatefulWidget {
  const RegistrationTogglePanel({super.key});

  @override
  State<RegistrationTogglePanel> createState() =>
      _RegistrationTogglePanelState();
}

class _RegistrationTogglePanelState extends State<RegistrationTogglePanel> {
  bool? _open;
  bool _isSaving = false;
  String? _loadError;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final open = await AppScope.of(context).auth.isRegistrationOpen();
      if (mounted) setState(() => _open = open);
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'Status pendaftaran gagal dimuat.');
      }
    }
  }

  Future<void> _set(bool open) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    final repo = AppScope.of(context).employees;
    final me = SessionScope.userOf(context);
    try {
      final result = await repo.setRegistrationOpen(me, open: open);
      if (!mounted) return;
      setState(() => _open = result);
      showAppSnackBar(
        context,
        result
            ? 'Pendaftaran dibuka. Tombol "Daftar akun" tampil di halaman '
                  'masuk.'
            : 'Pendaftaran ditutup. Akun baru hanya lewat Tambah karyawan.',
      );
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu coba '
          'lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final open = _open;

    if (open == null) {
      return Panel(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _loadError == null
            ? const LoadingRow(label: 'Memuat status pendaftaran…')
            : Row(
                children: [
                  Expanded(
                    child: Text(_loadError!, style: textTheme.bodySmall),
                  ),
                  TextButton(onPressed: _load, child: const Text('Coba lagi')),
                ],
              ),
      );
    }

    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: open ? context.accentSubtle : context.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(
                  color: open ? const Color(0xFFC6DDDA) : context.border,
                ),
              ),
              child: Icon(
                open ? Icons.how_to_reg_outlined : Icons.person_off_outlined,
                size: 20,
                color: open ? context.accentText : context.inkSecondary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Pendaftaran akun mandiri',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      StatusChip(
                        label: open ? 'Dibuka' : 'Ditutup',
                        tone: open ? ChipTone.success : ChipTone.neutral,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    open
                        ? 'Karyawan dapat mendaftar sendiri lewat tombol '
                              '"Daftar akun" di halaman masuk dan otomatis '
                              'menjadi Staff. Tutup bila semua karyawan sudah '
                              'terdaftar.'
                        : 'Tombol "Daftar akun" disembunyikan dari halaman '
                              'masuk. Akun baru hanya dapat dibuat lewat '
                              'Tambah karyawan.',
                    style: textTheme.bodySmall?.copyWith(height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              width: 56,
              height: 36,
              child: _isSaving
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Switch(
                      value: open,
                      onChanged: _set,
                      activeThumbColor: Colors.white,
                      activeTrackColor: context.isDark
                          ? context.accentText
                          : null,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
