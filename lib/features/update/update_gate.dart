import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_update.dart';
import 'update_dialog.dart';

/// Menjalankan pemeriksaan pembaruan sekali setiap aplikasi dibuka.
///
/// Lapisan pembaruan dipasang sebagai anak teratas [Stack] di atas Navigator,
/// bukan sebagai route dialog. Route dialog ikut terganti saat splash memanggil
/// `pushReplacement`, sehingga pembaruan wajib bisa hilang sebelum sempat
/// dipasang. Lapisan ini tidak tersentuh navigasi mana pun.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.updater, required this.child});

  final AppUpdater updater;
  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  bool _started = false;
  AppUpdate? _update;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_check());
    });
  }

  Future<void> _check() async {
    if (_started) return;
    _started = true;

    final update = await widget.updater.check();
    if (update == null || !mounted) return;

    if (!update.forced) {
      final skipped = await widget.updater.skippedVersion();
      // "Nanti" hanya menunda versi itu, bukan semua pembaruan berikutnya.
      if (skipped == update.release.versionCode) return;
    }

    if (!mounted) return;
    setState(() => _update = update);
  }

  void _hide() {
    if (!mounted) return;
    setState(() => _update = null);
  }

  @override
  Widget build(BuildContext context) {
    final update = _update;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (update != null)
          AppUpdateDialog(
            update: update,
            updater: widget.updater,
            onDismiss: update.forced ? null : _hide,
            onInstalled: _hide,
          ),
      ],
    );
  }
}
