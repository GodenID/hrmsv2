import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_scope.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/auth_repository.dart';
import '../../../data/leave_repository.dart';

/// Dialog kuota cuti tahunan satu karyawan (Super Admin).
/// Mengembalikan `true` bila ada perubahan, agar pemanggil memuat ulang.
Future<bool> showLeaveQuotaDialog(
  BuildContext context, {
  required String username,
  required String fullName,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _LeaveQuotaDialog(username: username, fullName: fullName),
  );
  return changed ?? false;
}

class _LeaveQuotaDialog extends StatefulWidget {
  const _LeaveQuotaDialog({required this.username, required this.fullName});

  final String username;
  final String fullName;

  @override
  State<_LeaveQuotaDialog> createState() => _LeaveQuotaDialogState();
}

class _LeaveQuotaDialogState extends State<_LeaveQuotaDialog> {
  final _days = TextEditingController();
  final _note = TextEditingController();

  bool _started = false;
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  LeaveQuota? _quota;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _days.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final quota = await AppScope.of(context).leave.fetchQuota(
            SessionScope.userOf(context),
            username: widget.username,
          );
      if (mounted) setState(() => _quota = quota);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Kuota gagal dimuat. Periksa koneksi Anda.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    final q = _quota;
    if (q == null) return;
    final days = int.tryParse(_days.text.trim()) ?? 0;
    final note = _note.text.trim();
    String? error;
    if (days < 1) {
      error = 'Isi jumlah hari yang dikurangi.';
    } else if (days > q.reducible) {
      error = q.reducible == 0
          ? 'Kuota sudah terpakai penuh, tidak bisa dikurangi.'
          : 'Maksimal ${q.reducible} hari (kuota tidak boleh di bawah cuti terpakai).';
    } else if (note.length < 5) {
      error = 'Tulis alasan minimal 5 karakter.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await AppScope.of(context).leave.adjustQuota(
            SessionScope.userOf(context),
            username: widget.username,
            days: -days,
            note: note,
          );
      if (!mounted) return;
      setState(() {
        _quota = updated;
        _changed = true;
        _days.clear();
        _note.clear();
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Tidak dapat terhubung ke server. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteAdjustment(LeaveQuotaAdjustment adjustment) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan pengurangan?'),
        content: Text(
          'Pengurangan ${-adjustment.days} hari akan dibatalkan dan kuota '
          'kembali seperti sebelumnya.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.of(context).leave.deleteQuotaAdjustment(
            SessionScope.userOf(context),
            id: adjustment.id,
          );
      if (!mounted) return;
      _changed = true;
      await _load();
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Tidak dapat terhubung ke server. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) Navigator.of(context).pop(_changed);
      },
      child: AlertDialog(
        title: Text('Kuota cuti · ${widget.fullName}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(child: _buildContent(textTheme)),
        ),
        actions: [
          TextButton(
            onPressed: _saving
                ? null
                : () => Navigator.of(context).pop(_changed),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(TextTheme textTheme) {
    if (_loading && _quota == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final q = _quota;
    if (q == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) FormErrorBanner(message: _error!),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Coba lagi'),
          ),
        ],
      );
    }

    Widget row(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label, style: textTheme.bodySmall)),
              Text(
                value,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Cuti tahunan ${q.year}',
          style: textTheme.labelSmall?.copyWith(
            color: context.inkSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        row('Kuota dasar', '${q.baseQuota} hari'),
        row('Penyesuaian', '${q.adjustment} hari'),
        row('Kuota efektif', '${q.quota} hari'),
        row('Sudah terpakai', '${q.used} hari'),
        row('Menunggu persetujuan', '${q.pending} hari'),
        row(
          'Sisa',
          '${q.remaining} hari',
          color: q.reducible == 0 ? context.danger : null,
        ),
        const SizedBox(height: AppSpacing.lg),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Kurangi kuota',
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          'Hanya pengurangan. Tidak ada penambahan kuota.',
          style: textTheme.bodySmall,
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          FormErrorBanner(message: _error!),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              child: TextField(
                controller: _days,
                enabled: !_saving && q.reducible > 0,
                keyboardType: TextInputType.number,
                maxLength: 3,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Hari',
                  counterText: '',
                  hintText: '0',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: TextField(
                controller: _note,
                enabled: !_saving && q.reducible > 0,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Alasan',
                  counterText: '',
                  hintText: 'mis. sisa cuti tahun lalu hangus',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        FilledButton.icon(
          onPressed: _saving || q.reducible == 0 ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.remove_circle_outline, size: 18),
          label: const Text('Kurangi kuota'),
        ),
        if (q.adjustments.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          Text('Riwayat penyesuaian', style: textTheme.labelSmall),
          const SizedBox(height: AppSpacing.sm),
          for (final a in q.adjustments)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${a.days} hari · ${a.note}',
                          style: textTheme.bodySmall?.copyWith(
                            color: context.ink,
                          ),
                        ),
                        Text(
                          'oleh ${a.createdBy}',
                          style: textTheme.bodySmall?.copyWith(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Batalkan pengurangan ini',
                    onPressed: _saving ? null : () => _deleteAdjustment(a),
                    icon: const Icon(Icons.undo, size: 18),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
