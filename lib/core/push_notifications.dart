import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

/// Push notification FCM. Tanpa file google-services (Android) /
/// GoogleService-Info.plist (iOS), semuanya nonaktif anggun.
abstract final class PushNotifications {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static bool _ready = false;

  /// Inisialisasi Firebase + sinkron token ke server. Aman dipanggil tanpa
  /// file Firebase (gagal diam-diam, aplikasi tetap jalan).
  static Future<void> ensureInitialized({
    required String baseUrl,
    required Future<String?> Function() readToken,
    required Future<void> Function(String token, String platform)
    syncToken,
  }) async {
    if (_ready || baseUrl.isEmpty) return;
    try {
      await Firebase.initializeApp();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      final session = await readToken();
      if (token != null && token.isNotEmpty && session != null) {
        try {
          await syncToken(token, Platform.operatingSystem);
        } catch (_) {}
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        final s = await readToken();
        if (s == null) return;
        try {
          await syncToken(t, Platform.operatingSystem);
        } catch (_) {}
      });
      // Foreground: sistem tidak menampilkan banner; tampilkan snackbar.
      FirebaseMessaging.onMessage.listen((m) {
        final title =
            m.notification?.title ?? m.data['title'] ?? 'Notifikasi baru';
        final body = m.notification?.body ?? m.data['body'] ?? '';
        messengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(body.isEmpty ? title : '$title — $body'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
      _ready = true;
    } catch (_) {
      // Firebase belum dikonfigurasi: push mati, aplikasi tetap jalan.
    }
  }

  /// Sinkronkan token push sesi berjalan (dipanggil setelah login).
  static Future<void> syncSessionToken({
    required String baseUrl,
    required Future<String?> Function() readToken,
    required Future<void> Function(String token, String platform) syncToken,
  }) async {
    if (!_ready || baseUrl.isEmpty) return;
    try {
      final session = await readToken();
      final token = await FirebaseMessaging.instance.getToken();
      if (session != null && token != null && token.isNotEmpty) {
        await syncToken(token, Platform.operatingSystem);
      }
    } catch (_) {}
  }
}
