import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/theme_colors.dart';
import 'brand_loading.dart';
import 'form_widgets.dart';

/// Wadah putih bergaris tipis — unit dasar tata letak konten.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: context.border),
      ),
      clipBehavior: Clip.antiAlias,
      padding: padding,
      child: child,
    );
  }
}

/// Judul bagian kecil: "RIWAYAT PENGAJUAN".
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

enum ChipTone { neutral, accent, success, warning, danger, strong }

/// Label status kecil berwarna (Menunggu, Disetujui, Terlambat, ...).
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.tone});

  final String label;
  final ChipTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      ChipTone.neutral => (context.surfaceMuted, context.inkSecondary),
      ChipTone.accent => (context.accentSubtle, context.accentText),
      ChipTone.success => (context.successSubtle, context.success),
      ChipTone.warning => (context.warningSubtle, context.warning),
      ChipTone.danger => (context.dangerSubtle, context.danger),
      ChipTone.strong => (context.ink, context.surface),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Baris label–nilai untuk detail (mis. "Jabatan  Staf Operasional").
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.valueStyle,
    this.trailing,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  /// Aksi di bawah nilai (mis. tombol "Lihat" lampiran).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final labelText = Text(label, style: textTheme.bodySmall);
            final valueText = Text(
              value,
              style: valueStyle ?? textTheme.bodyMedium,
            );
            final valueKids = <Widget>[valueText];
            final tr = trailing;
            if (tr != null) valueKids.add(tr);
            final valueColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: valueKids,
            );
            // Layar sempit: label di atas nilai.
            if (constraints.maxWidth < 300) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [labelText, const SizedBox(height: 2), valueColumn],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: constraints.maxWidth < 480 ? 116 : 160,
                  child: labelText,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: valueColumn),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Status memuat / gagal / kosong yang seragam.
class AsyncBody extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.isLoading,
    required this.error,
    required this.hasData,
    required this.onRetry,
    required this.builder,
    this.loadingLabel = 'Memuat data…',
  });

  final bool isLoading;
  final String? error;
  final bool hasData;
  final VoidCallback onRetry;
  final WidgetBuilder builder;
  final String loadingLabel;

  @override
  Widget build(BuildContext context) {
    if (hasData) return builder(context);
    if (isLoading) return SkeletonList(semanticLabel: loadingLabel);
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FormErrorBanner(message: error!),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Coba lagi'),
          ),
        ],
      );
    }
    return const SizedBox.shrink();
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        children: [
          _FloatingIcon(icon: icon),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Ikon status-kosong yang melayang lembut (animasi vektor tanpa aset),
/// menggantikan ikon statis di semua layar.
class _FloatingIcon extends StatefulWidget {
  const _FloatingIcon({required this.icon});

  final IconData icon;

  @override
  State<_FloatingIcon> createState() => _FloatingIconState();
}

class _FloatingIconState extends State<_FloatingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Transform.translate(
          offset: Offset(0, -4 * t),
          child: Opacity(
            opacity: 0.75 + 0.25 * t,
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.surfaceMuted,
          shape: BoxShape.circle,
        ),
        child: Icon(widget.icon, size: 28, color: context.inkTertiary),
      ),
    );
  }
}

/// Snackbar seragam (lebar tetap di layar lebar).
void showAppSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      width: MediaQuery.sizeOf(context).width >= 600 ? 420 : null,
      content: Text(message),
    ),
  );
}
