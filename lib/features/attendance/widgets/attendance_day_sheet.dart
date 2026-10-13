import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/date_format_id.dart';
import '../../../core/utils/work_calendar.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/attendance_repository.dart';
import '../attendance_presentation.dart';
import 'attendance_calendar.dart';

/// Aksi lanjutan yang dipilih dari lembar detail hari.
enum DaySheetAction {
  requestCorrection,
  openLeave,
  cancelCorrection,
  cancelOutOfArea,
}

/// Detail satu hari: jam clock in/out, atau detail cuti/izin/sakit.
Future<DaySheetAction?> showAttendanceDaySheet(
  BuildContext context,
  AttendanceDay day,
) {
  return showModalBottomSheet<DaySheetAction>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (context) => _DaySheet(day: day),
  );
}

class _DaySheet extends StatelessWidget {
  const _DaySheet({required this.day});

  final AttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    final look = calendarLookFor(
      day,
      date: day.date,
      today: WorkCalendar.dateOnly(now),
    );
    final chip = attendanceChipFor(day);
    final correction = day.correction;
    final outOfArea = day.outOfArea;
    final overtime = day.overtime;
    final leave = day.leave;
    final canCorrect = day.canRequestCorrection(now);
    final showClock =
        day.clockIn != null ||
        (leave == null &&
            day.status != AttendanceDayStatus.upcoming &&
            day.status != AttendanceDayStatus.dayOff);

    String time(DateTime? t) =>
        t == null ? '—' : DateFormatId.timeWithSeconds(t);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _ToneSwatch(look: look),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      DateFormatId.longDate(day.date),
                      style: textTheme.titleMedium?.copyWith(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                chip ??
                    const StatusChip(
                      label: 'Tepat waktu',
                      tone: ChipTone.success,
                    ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (leave != null) ...[
              SectionLabel(
                'Pengajuan ${leave.type.label.toLowerCase()}',
                trailing: StatusChip(
                  label: leave.status.label,
                  tone: requestTone(leave.status),
                ),
              ),
              InfoRow(
                label: 'Periode',
                value:
                    '${DateFormatId.dateRange(leave.start, leave.end)} · '
                    '${leave.workingDays} hari kerja',
              ),
              InfoRow(label: 'Alasan', value: leave.reason),
              InfoRow(
                label: 'Diajukan',
                value: DateFormatId.shortDateTime(leave.submittedAt),
              ),
              if (leave.reviewedBy != null)
                InfoRow(label: 'Diproses oleh', value: leave.reviewedBy!),
              if (leave.status == RequestStatus.pending) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Tanggal ini sudah ditandai di kalender. Warnanya tetap '
                  'berarsir sampai disetujui; bila ditolak, tanda akan hilang.',
                  style: textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ],
            ],
            if (showClock) ...[
              if (leave != null) ...[
                const SizedBox(height: AppSpacing.md),
                const Divider(),
                const SizedBox(height: AppSpacing.md),
                const SectionLabel('Catatan absensi'),
              ],
              InfoRow(label: 'Clock in', value: time(day.clockIn)),
              InfoRow(label: 'Clock out', value: time(day.clockOut)),
              InfoRow(
                label: 'Durasi kerja',
                value: day.worked == null
                    ? '—'
                    : DateFormatId.duration(day.worked!),
              ),
              if (day.clockInLocation != null)
                InfoRow(label: 'Lokasi clock in', value: day.clockInLocation!),
              if (day.clockOutLocation != null)
                InfoRow(
                  label: 'Lokasi clock out',
                  value: day.clockOutLocation!,
                ),
            ],
            if (correction != null) ...[
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              SectionLabel(
                'Pengajuan koreksi',
                trailing: StatusChip(
                  label: correction.status.label,
                  tone: requestTone(correction.status),
                ),
              ),
              InfoRow(
                label: 'Jam diajukan',
                value:
                    '${DateFormatId.time(correction.clockIn)} – '
                    '${DateFormatId.time(correction.clockOut)}',
              ),
              InfoRow(label: 'Alasan', value: correction.reason),
              InfoRow(
                label: 'Diajukan',
                value: DateFormatId.shortDateTime(correction.submittedAt),
              ),
              if (correction.reviewerNote != null)
                InfoRow(
                  label: 'Catatan ${correction.reviewedBy ?? 'Atasan'}',
                  value: correction.reviewerNote!,
                ),
            ],
            if (outOfArea != null &&
                outOfArea.status == RequestStatus.pending) ...[
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              SectionLabel(
                'Pengajuan luar area',
                trailing: StatusChip(
                  label: outOfArea.status.label,
                  tone: requestTone(outOfArea.status),
                ),
              ),
              InfoRow(
                label: 'Jenis',
                value:
                    '${outOfArea.kind.label} pukul '
                    '${DateFormatId.time(outOfArea.requestedAt)}',
              ),
              InfoRow(
                label: 'Posisi',
                value:
                    '${GeoMath.formatDistance(outOfArea.distanceMeters)} '
                    'dari ${outOfArea.nearestLocationName}',
              ),
              InfoRow(label: 'Alasan', value: outOfArea.reason),
              InfoRow(
                label: 'Diajukan',
                value: DateFormatId.shortDateTime(outOfArea.submittedAt),
              ),
              if (outOfArea.reviewerNote != null)
                InfoRow(
                  label: 'Catatan ${outOfArea.reviewedBy ?? 'Atasan'}',
                  value: outOfArea.reviewerNote!,
                ),
              if (outOfArea.status == RequestStatus.pending) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Jam tercatat setelah pengajuan disetujui Manager. '
                  'Koordinat & jarak di atas menjadi bukti pendukung.',
                  style: textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ],
            ],
            if (overtime != null) ...[
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              SectionLabel(
                'Lembur',
                trailing: StatusChip(
                  label: overtime.status.label,
                  tone: requestTone(overtime.status),
                ),
              ),
              InfoRow(
                label: 'Jam',
                value:
                    '${overtime.timeRangeLabel} (${overtime.durationLabel})',
              ),
              InfoRow(label: 'Keterangan', value: overtime.reason),
              InfoRow(
                label: 'Diajukan',
                value: DateFormatId.shortDateTime(overtime.submittedAt),
              ),
              if (overtime.reviewerNote != null)
                InfoRow(
                  label: 'Catatan ${overtime.reviewedBy ?? 'Atasan'}',
                  value: overtime.reviewerNote!,
                ),
            ],
            const SizedBox(height: AppSpacing.xl),
            if (correction?.status == RequestStatus.pending)
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(DaySheetAction.cancelCorrection),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: context.danger,
                  side: const BorderSide(color: AppColors.dangerBorder),
                ),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Batalkan pengajuan koreksi'),
              )
            else if (outOfArea?.status == RequestStatus.pending)
              OutlinedButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(DaySheetAction.cancelOutOfArea),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: context.danger,
                  side: const BorderSide(color: AppColors.dangerBorder),
                ),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Batalkan pengajuan luar area'),
              )
            else if (leave != null)
              OutlinedButton(
                onPressed: () =>
                    Navigator.of(context).pop(DaySheetAction.openLeave),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Lihat pengajuan'),
              )
            else if (canCorrect) ...[
              if (day.status == AttendanceDayStatus.dayOff &&
                  correction == null) ...[
                Text(
                  'Hari libur. Bila Anda tetap bekerja dan lupa absen, '
                  'ajukan absensi — jam akan diperiksa Atasan.',
                  style: textTheme.bodySmall?.copyWith(height: 1.5),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(DaySheetAction.requestCorrection),
                child: Text(
                  correction?.status == RequestStatus.rejected
                      ? 'Ajukan lagi'
                      : day.clockIn == null
                      ? 'Ajukan absensi'
                      : 'Ajukan koreksi',
                ),
              ),
            ]
            else
              Text(
                _whyNoCorrection(day),
                style: textTheme.bodySmall?.copyWith(height: 1.5),
              ),
          ],
        ),
      ),
    );
  }

  static String _whyNoCorrection(AttendanceDay day) {
    final today = WorkCalendar.dateOnly(DateTime.now());
    if (day.correction?.status == RequestStatus.pending) {
      return 'Koreksi untuk tanggal ini sedang menunggu persetujuan Atasan.';
    }
    if (day.status == AttendanceDayStatus.leave) {
      return 'Hari cuti/izin tidak memerlukan koreksi absensi.';
    }
    if (!day.date.isBefore(today)) {
      return 'Absensi untuk hari ini bisa diajukan mulai besok.';
    }
    return 'Absensi hanya bisa diajukan untuk '
        '${WorkPolicy.correctionWindowDays} hari terakhir.';
  }
}

/// Kotak warna kecil yang sama dengan sel kalender.
class _ToneSwatch extends StatelessWidget {
  const _ToneSwatch({required this.look});

  final CalendarLook look;

  @override
  Widget build(BuildContext context) {
    final tone = look.tone;
    return ExcludeSemantics(
      child: Container(
        width: 16,
        height: 16,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: look.pending ? context.surface : tone.fillOf(context),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: look.pending
                ? tone.inkOf(context).withValues(alpha: 0.55)
                : (tone == CalendarTone.off
                      ? context.border
                      : tone.borderOf(context)),
          ),
        ),
        child: look.pending
            ? CustomPaint(painter: HatchPainter(tone.fillOf(context)))
            : null,
      ),
    );
  }
}
