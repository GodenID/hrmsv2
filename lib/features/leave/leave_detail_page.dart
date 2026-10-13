import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/api/api_auth_repository.dart' show ApiConfig;
import '../../data/api/api_upload_repository.dart';
import '../../data/app_exception.dart';
import '../../data/leave_repository.dart';
import '../attendance/attendance_presentation.dart';

class LeaveDetailPage extends StatefulWidget {
  const LeaveDetailPage({super.key, required this.request});

  final LeaveRequest request;

  @override
  State<LeaveDetailPage> createState() => _LeaveDetailPageState();
}

class _LeaveDetailPageState extends State<LeaveDetailPage> {
  late LeaveRequest _request = widget.request;
  bool _isCancelling = false;
  bool _isOpening = false;

  /// Buka surat dokter dari S3.
  Future<void> _openAttachment() async {
    final key = _request.attachment?.key;
    if (key == null || key.isEmpty || _isOpening) return;
    setState(() => _isOpening = true);
    try {
      final uploader = ApiUploadRepository(
        baseUrl: ApiConfig.baseUrl,
        sessionStorage: AppScope.of(context).sessionStorage,
      );
      final url = await uploader.viewUrl(key);
      final uri = Uri.tryParse(url);
      if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const AppException('Dokumen tidak dapat dibuka.');
      }
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Dokumen tidak dapat dibuka.');
    } finally {
      if (mounted) setState(() => _isOpening = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batalkan pengajuan?'),
        content: Text(
          '${_request.type.label} '
          '${DateFormatId.dateRange(_request.start, _request.end)} akan '
          'dibatalkan dan tidak diproses oleh atasan.',
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
      final updated = await AppScope.of(context).leave
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
    final dates = WorkCalendar.isSameDay(r.start, r.end)
        ? DateFormatId.longDate(r.start)
        : '${DateFormatId.longDate(r.start)}\ns.d. ${DateFormatId.longDate(r.end)}';

    return PopScope(
      canPop: !_isCancelling,
      child: PageScaffold(
        title: 'Detail pengajuan',
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
                        r.type.label,
                        style: textTheme.headlineSmall?.copyWith(fontSize: 22),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${r.workingDays} hari kerja  ·  '
                        '${DateFormatId.dateRange(r.start, r.end)}',
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
                      trailing: r.attachment?.key == null || r.attachment!.key!.isEmpty
                          ? null
                          : TextButton.icon(
                              onPressed: _isOpening ? null : _openAttachment,
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: Text(_isOpening ? 'Membuka…' : 'Lihat'),
                            ),
                    ),
                  InfoRow(
                    label: 'Diajukan',
                    value: DateFormatId.shortDateTime(r.submittedAt),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const SectionLabel('Status'),
            _Timeline(request: r),
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

class _Timeline extends StatelessWidget {
  const _Timeline({required this.request});

  final LeaveRequest request;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final steps = <_Step>[
      _Step(
        icon: Icons.send_outlined,
        color: context.inkSecondary,
        title: 'Diajukan',
        subtitle: DateFormatId.shortDateTime(r.submittedAt),
      ),
      switch (r.status) {
        RequestStatus.pending => _Step(
          icon: Icons.schedule,
          color: context.warning,
          title: 'Menunggu persetujuan atasan',
          subtitle: 'Anda akan melihat hasilnya di halaman ini.',
        ),
        RequestStatus.approved => _Step(
          icon: Icons.check_circle,
          color: context.success,
          title: 'Disetujui oleh ${r.reviewedBy ?? 'atasan'}',
          subtitle: r.reviewedAt == null
              ? null
              : DateFormatId.shortDateTime(r.reviewedAt!),
          note: r.reviewerNote,
        ),
        RequestStatus.rejected => _Step(
          icon: Icons.cancel,
          color: context.danger,
          title: 'Ditolak oleh ${r.reviewedBy ?? 'atasan'}',
          subtitle: r.reviewedAt == null
              ? null
              : DateFormatId.shortDateTime(r.reviewedAt!),
          note: r.reviewerNote,
        ),
        RequestStatus.cancelled => _Step(
          icon: Icons.remove_circle_outline,
          color: context.inkSecondary,
          title: 'Dibatalkan oleh Anda',
          subtitle: r.reviewedAt == null
              ? null
              : DateFormatId.shortDateTime(r.reviewedAt!),
        ),
      },
    ];

    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepRow(step: steps[i], isLast: i == steps.length - 1),
      ],
    );
  }
}

class _Step {
  const _Step({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.note,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final String? note;
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step, required this.isLast});

  final _Step step;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MergeSemantics(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 24,
              child: Column(
                children: [
                  Icon(step.icon, size: 20, color: step.color),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 1.5,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: context.border,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.title,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (step.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(step.subtitle!, style: textTheme.bodySmall),
                    ],
                    if (step.note != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.surfaceMuted,
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          border: Border.all(color: context.border),
                        ),
                        child: Text(
                          '“${step.note!}”',
                          style: textTheme.bodyMedium?.copyWith(height: 1.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
