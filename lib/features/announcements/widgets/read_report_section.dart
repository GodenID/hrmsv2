import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/date_format_id.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../data/announcement_repository.dart';

/// "Dilihat oleh N dari M karyawan" + daftar sudah/belum melihat.
class ReadReportSection extends StatelessWidget {
  const ReadReportSection({super.key, required this.report});

  final AnnouncementReadReport report;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final viewed = report.viewed.length;
    final total = report.total;
    final ratio = total == 0 ? 0.0 : viewed / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text('Dilihat oleh', style: textTheme.titleMedium),
              ),
            ),
            Text(
              '$viewed dari $total karyawan',
              style: textTheme.bodySmall?.copyWith(
                color: context.ink,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Semantics(
          label: '${(ratio * 100).round()} persen karyawan sudah melihat',
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 4,
              color: context.accentText,
              backgroundColor: context.border,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tercatat saat karyawan membuka pengumuman ini.',
          style: textTheme.bodySmall?.copyWith(fontSize: 12.5),
        ),
        const SizedBox(height: AppSpacing.xl),
        _GroupLabel(label: 'Sudah melihat', count: viewed),
        const SizedBox(height: AppSpacing.sm),
        if (report.viewed.isEmpty)
          const _EmptyLine(text: 'Belum ada yang melihat.')
        else
          for (final v in report.viewed)
            _PersonRow(
              name: v.employee.fullName,
              trailing: DateFormatId.shortDateTime(v.viewedAt),
            ),
        const SizedBox(height: AppSpacing.xl),
        _GroupLabel(label: 'Belum melihat', count: report.notViewed.length),
        const SizedBox(height: AppSpacing.sm),
        if (report.notViewed.isEmpty)
          const _EmptyLine(text: 'Semua karyawan sudah melihat.')
        else
          for (final e in report.notViewed)
            _PersonRow(name: e.fullName, muted: true),
      ],
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: '$label, $count orang',
      excludeSemantics: true,
      child: Text(
        '${label.toUpperCase()}  ·  $count',
        style: Theme.of(context).textTheme.labelSmall,
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.name, this.trailing, this.muted = false});

  final String name;
  final String? trailing;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            InitialsAvatar(name: name, size: 30, muted: muted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: textTheme.bodyMedium?.copyWith(
                  color: muted ? context.inkSecondary : context.ink,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.md),
              Text(
                trailing!,
                style: textTheme.bodySmall?.copyWith(
                  fontSize: 12.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
