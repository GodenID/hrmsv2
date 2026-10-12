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

/// Detail pengajuan luar-area untuk Manager: bukti posisi vs catatan
/// sistem hari itu. Pop dengan status baru bila diproses.
class OutOfAreaReviewPage extends StatefulWidget {
  const OutOfAreaReviewPage({super.key, required this.item});

  final OutOfAreaReviewItem item;

  @override
  State<OutOfAreaReviewPage> createState() => _OutOfAreaReviewPageState();
}

class _OutOfAreaReviewPageState extends State<OutOfAreaReviewPage> {
  bool _isSubmitting = false;
  String? _error;

  Future<void> _decide({required bool approve}) async {
    final item = widget.item;
    final r = item.request;
    final note = await showReviewDialog(
      context,
      approve: approve,
      subject:
          '${r.kind.label} luar area ${item.employee.fullName}, '
          '${DateFormatId.longDate(r.date)} pukul '
          '${DateFormatId.time(r.requestedAt)}.',
    );
    if (note == null || !mounted) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final updated = await AppScope.of(context).attendance.reviewOutOfArea(
        SessionScope.userOf(context),
        id: r.id,
        approve: approve,
        note: note,
      );
      if (mounted) {
        unawaited(approve ? AppHaptics.confirm() : AppHaptics.reject());
        Navigator.of(context).pop(updated.request.status);
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
    final r = item.request;
    final pending = r.status == RequestStatus.pending;

    String t(DateTime? d) => d == null ? '—' : DateFormatId.time(d);
    final tabular = textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return PopScope(
      canPop: !_isSubmitting,
      child: PageScaffold(
        title: 'Tinjau luar area',
        maxWidth: 640,
        busy: _isSubmitting,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReviewHeader(
              employeeName: item.employee.fullName,
              title: '${r.kind.label} luar area',
              subtitle: DateFormatId.longDate(r.date),
              status: r.status,
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
                    label: 'Jam diajukan',
                    value: DateFormatId.timeWithSeconds(r.requestedAt),
                    valueStyle: tabular?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  InfoRow(
                    label: 'Tercatat sistem',
                    value:
                        '${t(item.recordedClockIn)}  –  '
                        '${t(item.recordedClockOut)}',
                    valueStyle: tabular,
                  ),
                  InfoRow(
                    label: 'Posisi pengajuan',
                    value:
                        '${GeoMath.formatDistance(r.distanceMeters)} dari '
                        '${r.nearestLocationName}',
                  ),
                  InfoRow(
                    label: 'Koordinat',
                    value:
                        '${r.latitude.toStringAsFixed(6)}, '
                        '${r.longitude.toStringAsFixed(6)}'
                        '${r.accuracyMeters == null ? '' : ' (±${GeoMath.formatDistance(r.accuracyMeters!)})'}',
                    valueStyle: tabular,
                  ),
                  InfoRow(label: 'Alasan', value: r.reason),
                  InfoRow(
                    label: 'Diajukan',
                    value: DateFormatId.shortDateTime(r.submittedAt),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Jika disetujui, jam pengajuan ditulis sebagai jam '
              '${r.kind.label.toLowerCase()} tanggal ini (ditandai luar area).',
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
                status: r.status,
                reviewedBy: r.reviewedBy,
                reviewedAt: r.reviewedAt,
                note: r.reviewerNote,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
