import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../core/app_info.dart';
import '../../core/app_scope.dart';
import '../../core/theme/theme_colors.dart';
import '../../data/api/api_notification_repository.dart';

/// Keluar: hapus token tersimpan, cabut sesi di server, lalu kembali ke
/// halaman login (dari halaman mana pun di shell).
Future<void> signOut(BuildContext context) async {
  final deps = AppScope.of(context);
  final session = SessionScope.maybeSessionOf(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  try {
    await deps.sessionStorage.clear();
  } catch (_) {
    // Tetap keluar walau penyimpanan lokal gagal dihapus.
  }
  if (session != null) {
    // Tidak ditunggu: keluar tidak boleh terhambat koneksi.
    unawaited(deps.auth.logout(session.token).catchError((Object _) {}));
    final notifications = deps.notifications;
    if (notifications is ApiNotificationRepository) {
      unawaited(notifications.clearPushToken().catchError((Object _) {}));
    }
  }
  navigator.pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
}

/// Minta konfirmasi, lalu [signOut].
Future<void> confirmSignOut(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context) => AlertDialog(
      title: const Text('Keluar dari ${AppInfo.appName}?'),
      content: const Text('Anda perlu masuk kembali untuk membuka aplikasi.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: context.inkSecondary),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          child: const Text('Keluar'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) await signOut(context);
}
