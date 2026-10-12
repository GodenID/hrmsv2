import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/date_format_id.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/attendance_repository.dart';
import '../../attendance/attendance_presentation.dart';

/// Dialog keputusan. Mengembalikan catatan ('' bila kosong) atau null bila
/// dibatalkan. Catatan wajib saat menolak.
Future<String?> showReviewDialog(
  BuildContext context, {
  required bool approve,
  required String subject,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _ReviewDialog(approve: approve, subject: subject),
  );
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.approve, required this.subject});

  final bool approve;
  final String subject;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(_noteController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final approve = widget.approve;

    return AlertDialog(
      title: Text(approve ? 'Setujui pengajuan?' : 'Tolak pengajuan?'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteractionIfError,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.subject),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _noteController,
                autofocus: !approve,
                minLines: 2,
                maxLines: 4,
                maxLength: ReviewRules.maxNote,
                textCapitalization: TextCapitalization.sentences,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (!approve && value.length < ReviewRules.minRejectNote) {
                    return 'Tulis alasan penolakan (minimal '
                        '${ReviewRules.minRejectNote} karakter)';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  labelText: approve
                      ? 'Catatan untuk karyawan (opsional)'
                      : 'Alasan penolakan',
                  hintText: approve
                      ? 'mis. Selamat berlibur.'
                      : 'mis. Bertepatan dengan jadwal audit.',
                  alignLabelWithHint: true,
                ),
              ),
              Text(
                'Karyawan akan menerima notifikasi beserta catatan ini.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: context.inkSecondary,
          ),
          child: const Text('Kembali'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, 44),
            backgroundColor: approve ? context.success : context.danger,
            foregroundColor: context.isDark ? context.surface : Colors.white,
          ),
          child: Text(approve ? 'Setujui' : 'Tolak'),
        ),
      ],
    );
  }
}

/// Tombol Setujui / Tolak di bawah detail pengajuan.
class ReviewDecisionBar extends StatelessWidget {
  const ReviewDecisionBar({
    super.key,
    required this.busy,
    required this.onApprove,
    required this.onReject,
  });

  final bool busy;

  /// null = tombol Setujui dinonaktifkan (mis. kuota tidak cukup).
  final VoidCallback? onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        FilledButton.icon(
          onPressed: busy || onApprove == null ? null : onApprove,
          style: FilledButton.styleFrom(
            backgroundColor: context.success,
            foregroundColor: context.isDark ? context.surface : Colors.white,
            disabledBackgroundColor: context.border,
            disabledForegroundColor: context.inkTertiary,
          ),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Setujui'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onReject,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(64, 48),
            foregroundColor: context.danger,
            side: const BorderSide(color: AppColors.dangerBorder),
          ),
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Tolak'),
        ),
      ],
    );
  }
}

/// Nama karyawan + judul pengajuan + status.
class ReviewHeader extends StatelessWidget {
  const ReviewHeader({
    super.key,
    required this.employeeName,
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final String employeeName;
  final String title;
  final String subtitle;
  final RequestStatus status;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InitialsAvatar(name: employeeName, size: 44),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(employeeName, style: textTheme.bodySmall),
              const SizedBox(height: 2),
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: textTheme.headlineSmall?.copyWith(fontSize: 22),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: textTheme.bodyMedium?.copyWith(
                  color: context.inkSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        StatusChip(label: status.label, tone: requestTone(status)),
      ],
    );
  }
}

/// Ringkasan keputusan (siapa, kapan, catatan) untuk pengajuan yang sudah
/// diproses.
class ReviewOutcomePanel extends StatelessWidget {
  const ReviewOutcomePanel({
    super.key,
    required this.status,
    this.reviewedBy,
    this.reviewedAt,
    this.note,
  });

  final RequestStatus status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        children: [
          InfoRow(label: 'Hasil', value: status.label),
          InfoRow(label: 'Diproses oleh', value: reviewedBy ?? '—'),
          if (reviewedAt != null)
            InfoRow(
              label: 'Waktu',
              value: DateFormatId.shortDateTime(reviewedAt!),
            ),
          if (note != null) InfoRow(label: 'Catatan', value: note!),
        ],
      ),
    );
  }
}
