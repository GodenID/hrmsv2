import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/app_exception.dart';
import '../../data/overtime_repository.dart';
import '../attendance/attendance_presentation.dart';

/// Detail pengajuan lembur + pembatalan (bila masih menunggu).
class OvertimeDetailPage extends StatefulWidget {
  const OvertimeDetailPage({super.key, required this.request});

  final OvertimeRequest request;

  @override
  State<OvertimeDetailPage> createState() => _OvertimeDetailPageState();
}

class _OvertimeDetailPageState extends State<OvertimeDetailPage> {
  late OvertimeRequest _request = widget.request;
  bool _isCancelling = false;

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan pengajuan?'),
        content: Text(
          'Lembur ${DateFormatId.longDate(_request.date)} '
          '(${_request.timeRangeLabel}) akan dibatalkan dan tidak diproses '
          'oleh atasan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: context.inkSecondary,
            ),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 44),
              backgroundColor: context.danger,
              foregroundColor: context.isDark ? context.surface : Colors.white,
            ),
            child: const Text('Batalkan pengajuan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      final updated = await AppScope.of(context).overtime
          .cancel(SessionScope.userOf(context), id: _request.id);
      if (!mounted) return;
      setState(() => _request = updated);
      showAppSnackBar(context, 'Pengajuan dibatalkan.');
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Gagal membatalkan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final r = _request;

    return PopScope(
      canPop: !_isCancelling,
      child: PageScaffold(
        title: 'Detail lembur',
        maxWidth: 640,
        busy: _isCancelling,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lembur',
                        style: textTheme.headlineSmall?.copyWith(fontSize: 22),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${DateFormatId.longDate(r.date)}  ·  '
                        '${r.timeRangeLabel}  ·  ${r.durationLabel}',
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                StatusChip(label: r.status.label, tone: requestTone(r.status)),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Panel(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Column(
                children: [
                  InfoRow(
                    label: 'Tanggal',
                    value: DateFormatId.longDate(r.date),
                  ),
                  InfoRow(label: 'Jam', value: r.timeRangeLabel),
                  InfoRow(label: 'Durasi', value: r.durationLabel),
                  InfoRow(label: 'Keterangan', value: r.reason),
                  InfoRow(
                    label: 'Diajukan',
                    value: DateFormatId.shortDateTime(r.submittedAt),
                  ),
                  if (r.reviewedBy != null)
                    InfoRow(label: 'Diproses oleh', value: r.reviewedBy!),
                  if (r.reviewedAt != null)
                    InfoRow(
                      label: 'Waktu',
                      value: DateFormatId.shortDateTime(r.reviewedAt!),
                    ),
                  if (r.reviewerNote != null)
                    InfoRow(label: 'Catatan', value: r.reviewerNote!),
                ],
              ),
            ),
            if (r.status == RequestStatus.pending) ...[
              const SizedBox(height: AppSpacing.xl),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _isCancelling ? null : _cancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.danger,
                    side: const BorderSide(color: AppColors.dangerBorder),
                  ),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Batalkan pengajuan'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
