import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/date_format_id.dart';

/// Jam & tanggal lokal — relevan untuk karyawan yang membuka portal
/// sebelum absen. Hanya rebuild saat menit berganti.
class LocalClock extends StatefulWidget {
  const LocalClock({super.key});

  @override
  State<LocalClock> createState() => _LocalClockState();
}

class _LocalClockState extends State<LocalClock> {
  late DateTime _now;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final next = DateTime.now();
      if (next.minute != _now.minute || next.day != _now.day) {
        setState(() => _now = next);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final time = DateFormatId.time(_now);
    final date = DateFormatId.longDate(_now);

    return Semantics(
      label: 'Waktu lokal $time, $date',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('WAKTU LOKAL', style: textTheme.labelSmall),
          const SizedBox(height: 6),
          Text(
            time,
            style: TextStyle(
              fontSize: 44,
              height: 1,
              fontWeight: FontWeight.w300,
              letterSpacing: -0.5,
              color: context.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            date,
            style: textTheme.bodyMedium?.copyWith(
              color: context.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
