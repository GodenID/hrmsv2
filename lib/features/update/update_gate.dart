import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_update.dart';
import 'update_dialog.dart';

/// Menjalankan pemeriksaan pembaruan sekali setiap aplikasi dibuka.
///
/// Dipasang sebagai `MaterialApp.builder`, jadi dialog tetap muncul di atas
/// halaman mana pun — termasuk splash dan login — sebelum pengguna sempat
/// memakai versi lama.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.updater,
    required this.navigatorKey,
    required this.child,
  });

  final AppUpdater updater;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> {
  bool _started = false;

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

    // Context milik Navigator sendiri tidak punya leluhur Navigator; overlay
    // adalah anak Navigator sehingga showDialog dapat menemukannya.
    final overlayContext = widget.navigatorKey.currentState?.overlay?.context;
    if (overlayContext == null || !mounted || !overlayContext.mounted) return;

    await showDialog<void>(
      context: overlayContext,
      barrierDismissible: !update.forced,
      builder: (_) => AppUpdateDialog(update: update, updater: widget.updater),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
