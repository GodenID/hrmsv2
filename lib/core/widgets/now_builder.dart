import 'dart:async';

import 'package:flutter/widgets.dart';

/// Membangun ulang [builder] setiap detik dengan waktu sekarang.
/// Dipakai untuk bagian kecil UI saja (jam berjalan, durasi kerja),
/// agar seluruh halaman tidak ikut rebuild.
class NowBuilder extends StatefulWidget {
  const NowBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<NowBuilder> createState() => _NowBuilderState();
}

class _NowBuilderState extends State<NowBuilder> {
  late DateTime _now = DateTime.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _now);
}
