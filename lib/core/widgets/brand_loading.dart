import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_colors.dart';
import 'brand_mark.dart';
import 'panel.dart';

/// Logo P berdenyut: dua lingkaran mengembang + logo di tengah.
/// Pengganti spinner generik di seluruh aplikasi.
class BrandPulseLogo extends StatefulWidget {
  const BrandPulseLogo({super.key, this.size = 56});

  /// Sisi kotak (logo ≈ 55% nya, denyut di dalamnya).
  final double size;

  @override
  State<BrandPulseLogo> createState() => _BrandPulseLogoState();
}

class _BrandPulseLogoState extends State<BrandPulseLogo>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return Image.asset(
        BrandAssets.mark,
        width: widget.size * 0.55,
        height: widget.size * 0.55,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      );
    }
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _PulsePainter(phase: _controller.value),
          child: Center(
            child: Image.asset(
              BrandAssets.mark,
              width: widget.size * 0.55,
              height: widget.size * 0.55,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.phase});

  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide / 2;
    for (final offset in [0.0, 0.5]) {
      final p = (phase + offset) % 1.0;
      canvas.drawCircle(
        center,
        maxRadius * (0.25 + 0.75 * p),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = AppColors.accent.withValues(alpha: (1 - p) * 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.phase != phase;
}

/// Kilau berjalan (shimmer) untuk kerangka konten. Tanpa animasi bila
/// pengguna mematikan animasi (reduce motion).
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Pita terang digeser dengan menggerakkan vektor gradien; begin/end
        // di luar -1..1 legal (hanya koordinat), stops tetap aman.
        final v = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment(-1.5 + 3.0 * v, 0),
            end: Alignment(-0.5 + 3.0 * v, 0),
            colors: [
              context.border,
              context.inkTertiary.withValues(alpha: 0.55),
              context.border,
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(bounds),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Balok / lingkaran kerangka berwarna abu.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.widthFactor,
    this.height = 12,
    this.circle = false,
  }) : assert(
         width != null || widthFactor != null || circle,
         'Isi lebar pasti, pecahan lebar, atau lingkaran.',
       );

  final double? width;
  final double? widthFactor;
  final double height;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: circle ? height : (widthFactor != null ? double.infinity : width),
      height: height,
      decoration: BoxDecoration(
        color: context.border,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(6),
      ),
    );
    if (widthFactor != null && !circle) {
      return FractionallySizedBox(widthFactor: widthFactor, child: box);
    }
    return box;
  }
}

/// Daftar kerangka mirip baris daftar aplikasi (avatar + teks + chip).
/// Dipakai sebagai tampilan memuat baku [AsyncBody].
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.rows = 5, this.semanticLabel});

  final int rows;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? 'Memuat data',
      liveRegion: true,
      excludeSemantics: true,
      child: Shimmer(
        child: Panel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < rows; i++) ...[
                if (i > 0) const Divider(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      SkeletonBox(circle: true, height: 36),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox(widthFactor: 0.7, height: 13),
                            SizedBox(height: 7),
                            SkeletonBox(widthFactor: 0.45, height: 11),
                          ],
                        ),
                      ),
                      SizedBox(width: 8),
                      SkeletonBox(width: 52, height: 22),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Kepala halaman + kerangka: logo berdenyut di tengah untuk pemuatan
/// layar penuh yang singkat (mis. splash / startup).
class BrandLoadingScreen extends StatelessWidget {
  const BrandLoadingScreen({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final label = this.label;
    return Semantics(
      label: label ?? 'Memuat',
      liveRegion: true,
      excludeSemantics: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandPulseLogo(size: 88),
            if (label != null) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(label, style: textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
