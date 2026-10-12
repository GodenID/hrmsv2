import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/theme_colors.dart';
import '../utils/app_haptics.dart';

/// Centang sukses animasi vektor (tanpa aset/unduhan): lingkaran tergambar
/// lalu centang menukik, ~900ms. Dipakai di lembar sukses & status berhasil.
class AnimatedCheck extends StatefulWidget {
  const AnimatedCheck({super.key, this.size = 76});

  final double size;

  @override
  State<AnimatedCheck> createState() => _AnimatedCheckState();
}

class _AnimatedCheckState extends State<AnimatedCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 900),
        )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _CheckPainter(
            progress: _controller.value,
            ring: context.successSubtle,
            stroke: context.success,
          ),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.progress,
    required this.ring,
    required this.stroke,
  });

  final double progress;
  final Color ring;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;
    final ringPaint = Paint()
      ..color = ring
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, ringPaint);

    final circlePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;
    // 0 → 0.55: lingkaran tergambar.
    final circleT = (progress / 0.55).clamp(0.0, 1.0);
    final sweep = circleT * math.pi * 2;
    if (sweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 6),
        -math.pi / 2,
        sweep,
        false,
        circlePaint,
      );
    }

    // 0.55 → 1: centang tergambar (dengan sedikit overshoot).
    final checkT = ((progress - 0.55) / 0.45).clamp(0.0, 1.0);
    if (checkT <= 0) return;
    final eased = Curves.easeOutBack.transform(checkT);
    final p1 = center + Offset(-radius * 0.42, radius * 0.02);
    final p2 = center + Offset(-radius * 0.08, radius * 0.34);
    final p3 = center + Offset(radius * 0.46, -radius * 0.32);
    final checkPaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(p1.dx, p1.dy);
    if (eased < 0.45) {
      final t = eased / 0.45;
      path.lineTo(
        p1.dx + (p2.dx - p1.dx) * t,
        p1.dy + (p2.dy - p1.dy) * t,
      );
    } else {
      path.lineTo(p2.dx, p2.dy);
      final t = (eased - 0.45) / 0.55;
      path.lineTo(
        p2.dx + (p3.dx - p2.dx) * t,
        p2.dy + (p3.dy - p2.dy) * t,
      );
    }
    canvas.drawPath(path, checkPaint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.progress != progress;
}

/// Lembar sukses seragam: centang animasi + judul + pesan + tombol.
/// Memainkan haptic sukses saat tampil.
Future<void> showSuccessSheet(
  BuildContext context, {
  required String title,
  required String message,
  String buttonLabel = 'Tutup',
}) {
  unawaited(AppHaptics.success());
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: AnimatedCheck()),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: context.inkSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: context.success,
                foregroundColor: context.isDark
                    ? context.surface
                    : Colors.white,
              ),
              child: Text(buttonLabel),
            ),
          ],
        ),
      ),
    ),
  );
}
