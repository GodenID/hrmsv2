import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';

/// Indikator langkah tersegmentasi: "LANGKAH 2 DARI 3 · VERIFIKASI KTP"
/// dengan bar 3 segmen. Ringkas sehingga tetap muat di layar 320px.
///
/// [showLabels] menampilkan nama tiap langkah di bawah segmennya (untuk
/// alur yang panjang, mis. pendaftaran). [onStepTap] membuat langkah yang
/// sudah dilewati bisa diketuk untuk kembali.
class StepProgress extends StatelessWidget {
  const StepProgress({
    super.key,
    required this.steps,
    required this.currentIndex,
    this.showLabels = false,
    this.onStepTap,
  });

  final List<String> steps;

  /// Indeks langkah aktif (0-based). Jika >= steps.length, semua selesai.
  final int currentIndex;

  final bool showLabels;
  final ValueChanged<int>? onStepTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final allDone = currentIndex >= steps.length;
    final caption = allDone
        ? 'SELESAI'
        : showLabels
        ? 'LANGKAH ${currentIndex + 1} DARI ${steps.length}'
        : 'LANGKAH ${currentIndex + 1} DARI ${steps.length}  ·  '
              '${steps[currentIndex].toUpperCase()}';
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 240);

    Widget segment(int i) => AnimatedContainer(
      duration: duration,
      height: 4,
      decoration: BoxDecoration(
        color: i <= currentIndex ? context.accentText : context.border,
        borderRadius: BorderRadius.circular(2),
      ),
    );

    final summary = Semantics(
      label: allDone
          ? 'Semua langkah selesai'
          : 'Langkah ${currentIndex + 1} dari ${steps.length}: '
                '${steps[currentIndex]}',
      excludeSemantics: true,
      child: Text(caption, style: textTheme.labelSmall),
    );

    if (!showLabels) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          summary,
          const SizedBox(height: AppSpacing.sm),
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < steps.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(child: segment(i)),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        summary,
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(
                child: _LabeledSegment(
                  label: steps[i],
                  state: allDone || i < currentIndex
                      ? _SegmentState.done
                      : i == currentIndex
                      ? _SegmentState.current
                      : _SegmentState.upcoming,
                  segment: segment(i),
                  // Hanya langkah yang sudah dilewati yang bisa dibuka lagi.
                  onTap: !allDone && i < currentIndex && onStepTap != null
                      ? () => onStepTap!(i)
                      : null,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

enum _SegmentState { done, current, upcoming }

class _LabeledSegment extends StatelessWidget {
  const _LabeledSegment({
    required this.label,
    required this.state,
    required this.segment,
    required this.onTap,
  });

  final String label;
  final _SegmentState state;
  final Widget segment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11.5,
      height: 16 / 11.5,
      fontWeight: state == _SegmentState.current
          ? FontWeight.w700
          : FontWeight.w500,
      color: switch (state) {
        _SegmentState.done => context.accentText,
        _SegmentState.current => context.ink,
        _SegmentState.upcoming => context.inkSecondary,
      },
    );

    final content = Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          segment,
          const SizedBox(height: 6),
          Text(
            label,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );

    if (onTap == null) return ExcludeSemantics(child: content);
    return Semantics(
      button: true,
      label: 'Kembali ke langkah $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: content,
      ),
    );
  }
}
