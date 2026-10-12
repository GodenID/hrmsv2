import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/app_haptics.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/app_exception.dart';
import '../../data/leave_repository.dart';
import 'widgets/review_widgets.dart';

/// Detail pengajuan cuti/izin/sakit untuk Manager. Pop dengan status baru
/// ([RequestStatus.approved] / [RequestStatus.rejected]) bila diproses.
class LeaveReviewPage extends StatefulWidget {
  const LeaveReviewPage({super.key, required this.item});

  final LeaveReviewItem item;

  @override
  State<LeaveReviewPage> createState() => _LeaveReviewPageState();
}

class _LeaveReviewPageState extends State<LeaveReviewPage> {
  bool _isSubmitting = false;
  String? _error;

  Future<void> _decide({required bool approve}) async {
    final r = widget.item.request;
    final note = await showReviewDialog(
      context,
      approve: approve,
      subject:
          '${r.type.label} ${widget.item.employee.fullName}, '
          '${DateFormatId.dateRange(r.start, r.end)} '
          '(${r.workingDays} hari kerja).',
    );
    if (note == null || !mounted) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final updated = await AppScope.of(context).leave.review(
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
    final b = item.balance;
    final pending = r.status == RequestStatus.pending;
    final dates = WorkCalendar.isSameDay(r.start, r.end)
        ? DateFormatId.longDate(r.start)
        : '${DateFormatId.longDate(r.start)}\ns.d. ${DateFormatId.longDate(r.end)}';
    final quotaShort =
        pending && r.type.usesQuota && r.workingDays > b.remaining;

    return PopScope(
      canPop: !_isSubmitting,
      child: PageScaffold(
        title: 'Tinjau pengajuan',
        maxWidth: 640,
        busy: _isSubmitting,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ReviewHeader(
              employeeName: item.employee.fullName,
              title: r.type.label,
              subtitle:
                  '${r.workingDays} hari kerja  ·  '
                  '${DateFormatId.dateRange(r.start, r.end)}',
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
                  InfoRow(label: 'Tanggal', value: dates),
                  InfoRow(
                    label: 'Jumlah',
                    value: '${r.workingDays} hari kerja',
                  ),
                  InfoRow(label: 'Alasan', value: r.reason),
                  if (r.type == LeaveType.sick)
                    InfoRow(
                      label: 'Surat dokter',
                      value: r.attachment == null
                          ? 'Tidak dilampirkan'
                          : '${r.attachment!.name} (${r.attachment!.sizeLabel})',
                    ),
                  InfoRow(
                    label: 'Diajukan',
                    value: DateFormatId.shortDateTime(r.submittedAt),
                  ),
                  InfoRow(
                    label: 'Cuti tahunan ${b.year}',
                    value:
                        'Sisa ${b.remaining} dari ${b.quota} hari'
                        '${b.pending > 0 ? ' (${b.pending} hari menunggu)' : ''}',
                    valueStyle: quotaShort
                        ? textTheme.bodyMedium?.copyWith(
                            color: context.danger,
                            fontWeight: FontWeight.w600,
                          )
                        : null,
                  ),
                ],
              ),
            ),
            if (quotaShort) ...[
              const SizedBox(height: AppSpacing.md),
              FormErrorBanner(
                message:
                    'Sisa cuti tahunan tidak cukup untuk ${r.workingDays} '
                    'hari. Pengajuan ini hanya bisa ditolak.',
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            if (pending)
              ReviewDecisionBar(
                busy: _isSubmitting,
                onApprove: quotaShort ? null : () => _decide(approve: true),
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
