import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/app_haptics.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/app_exception.dart';
import '../../data/attendance_repository.dart';
import 'widgets/review_widgets.dart';

/// Detail koreksi absensi untuk Atasan: catatan sistem vs jam yang diajukan.
/// Pop dengan status baru bila diproses.
class CorrectionReviewPage extends StatefulWidget {
  const CorrectionReviewPage({super.key, required this.item});

  final CorrectionReviewItem item;

  @override
  State<CorrectionReviewPage> createState() => _CorrectionReviewPageState();
}

class _CorrectionReviewPageState extends State<CorrectionReviewPage> {
  bool _isSubmitting = false;
  String? _error;

  Future<void> _decide({required bool approve}) async {
    final c = widget.item.correction;
    final note = await showReviewDialog(
      context,
      approve: approve,
      subject:
          'Koreksi absensi ${widget.item.employee.fullName}, '
          '${DateFormatId.longDate(c.date)}: '
          '${DateFormatId.time(c.clockIn)} – ${DateFormatId.time(c.clockOut)}.',
    );
    if (note == null || !mounted) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final updated = await AppScope.of(context).attendance.reviewCorrection(
        SessionScope.userOf(context),
        id: c.id,
        approve: approve,
        note: note,
      );
      if (mounted) {
        unawaited(approve ? AppHaptics.confirm() : AppHaptics.reject());
        Navigator.of(context).pop(updated.correction.status);
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final item = widget.item;
    final c = item.correction;
    final pending = c.status == RequestStatus.pending;

    String t(DateTime? d) => d == null ? '—' : DateFormatId.time(d);
    final tabular = textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return PopScope(
      canPop: !_isSubmitting,
      child: PageScaffold(
        title: 'Tinjau koreksi',
        maxWidth: 640,
        busy: _isSubmitting,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReviewHeader(
              employeeName: item.employee.fullName,
              title: 'Koreksi absensi',
              subtitle: DateFormatId.longDate(c.date),
              status: c.status,
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_error != null) ...[
              FormErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            Panel(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Column(
                children: [
                  InfoRow(label: 'Karyawan', value: item.employee.fullName),
                  InfoRow(
                    label: 'Tercatat sistem',
                    value:
                        '${t(item.recordedClockIn)}  –  '
                        '${t(item.recordedClockOut)}',
                    valueStyle: tabular,
                  ),
                  InfoRow(
                    label: 'Diajukan menjadi',
                    value: '${t(c.clockIn)}  –  ${t(c.clockOut)}',
                    valueStyle: tabular?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  InfoRow(
                    label: 'Durasi baru',
                    value: DateFormatId.duration(
                      c.clockOut.difference(c.clockIn),
                    ),
                  ),
                  InfoRow(label: 'Alasan', value: c.reason),
                  InfoRow(
                    label: 'Diajukan',
                    value: DateFormatId.shortDateTime(c.submittedAt),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Jika disetujui, jam yang diajukan menggantikan catatan absensi '
              'tanggal ini.',
              style: textTheme.bodySmall?.copyWith(height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (pending)
              ReviewDecisionBar(
                busy: _isSubmitting,
                onApprove: () => _decide(approve: true),
                onReject: () => _decide(approve: false),
              )
            else ...[
              const SectionLabel('Keputusan'),
              ReviewOutcomePanel(
                status: c.status,
                reviewedBy: c.reviewedBy,
                reviewedAt: c.reviewedAt,
                note: c.reviewerNote,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
