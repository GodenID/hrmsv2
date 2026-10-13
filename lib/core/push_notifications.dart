import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';


/// Kanal notifikasi sistem (Android 8+): pentingnya tinggi agar tampil
/// di luar aplikasi seperti aplikasi lain (heads-up + suara).
const _channel = AndroidNotificationChannel(
  'prasasti_high',
  'Notifikasi',
  description: 'Pengajuan, persetujuan, dan siaran Prasasti Connect.',
  importance: Importance.max,
);

final _local = FlutterLocalNotificationsPlugin();

/// Push notification FCM. Tanpa file google-services (Android) /
/// GoogleService-Info.plist (iOS), semuanya nonaktif anggun.
abstract final class PushNotifications {
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// Deep link tertunda dari ketukan notifikasi saat aplikasi mati.
  static Map<String, String>? _pendingTap;

  /// Dipasang shell setelah login: membuka tujuan notifikasi (detail bila
  /// ada refType/refId). Null selama belum login / shell belum tampil.
  static Future<void> Function(String kind, String? refType, String? refId)?
  linkHandler;
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
      // Kanal sistem + tampilkan pesan foreground sebagai notifikasi
      // (bukan cuma snackbar di dalam aplikasi).
      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: (r) => _handleTap(_decode(r.payload)),
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
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
      // Foreground: tampilkan sebagai notifikasi sistem (tray) seperti
      // aplikasi lain + segarkan semua tampilan terkait (realtime).
      FirebaseMessaging.onMessage.listen((m) async {
        AppRefresh.pingForKind((m.data['kind'] ?? '').toString());
        final title =
            m.notification?.title ?? m.data['title'] ?? 'Notifikasi baru';
        final body = m.notification?.body ?? m.data['body'] ?? '';
        try {
          await _local.show(
            body.hashCode ^ title.hashCode,
            title,
            body.isEmpty ? null : body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                _channel.id,
                _channel.name,
                channelDescription: _channel.description,
                importance: Importance.max,
                priority: Priority.high,
                icon: 'ic_stat_notify',
              ),
              iOS: const DarwinNotificationDetails(),
            ),
            payload: jsonEncode(m.data),
          );
        } catch (_) {}
      });
      // Ketuk banner/tray: buka detail pengajuan / pengumuman / SP terkait.
      FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleTap(m.data));
      FirebaseMessaging.instance.getInitialMessage().then((m) {
        if (m != null) _pendingTap = Map<String, String>.from(m.data);
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

  static Map<String, String> _decode(String? payload) {
    if (payload == null || payload.isEmpty) return const {};
    try {
      final m = jsonDecode(payload);
      if (m is Map) {
        return {for (final e in m.entries) e.key.toString(): e.value.toString()};
      }
    } catch (_) {}
    // Payload lama: hanya jenis notifikasi.
    return {'kind': payload};
  }

  static void _handleTap(Map<String, dynamic> data) {
    final handler = linkHandler;
    if (handler == null) {
      // Aplikasi baru dibuka / belum login: proses setelah shell tampil.
      _pendingTap = {
        for (final e in data.entries) e.key: e.value.toString(),
      };
      return;
    }
    _dispatch(handler, data);
  }

  static void _dispatch(
    Future<void> Function(String kind, String? refType, String? refId)
    handler,
    Map<String, dynamic> data,
  ) {
    final kind = (data['kind'] ?? '').toString();
    if (kind.isEmpty) return;
    final refType = data['refType']?.toString();
    final refId = data['refId']?.toString();
    unawaited(handler(kind, refType, refId));
  }

  /// Dipanggil shell setelah tampil: proses ketukan tertunda dari tray saat
  /// aplikasi mati.
  static void consumePendingTap() {
    final pending = _pendingTap;
    final handler = linkHandler;
    if (pending == null || handler == null) return;
    _pendingTap = null;
    _dispatch(handler, pending);
  }
}
/// Pemicu muat-ulang lintas halaman (mis. push masuk saat aplikasi terbuka).
/// Halaman berlangganan bus domainnya; push memicu bus yang sesuai agar
/// semua yang tampil terganti otomatis tanpa refresh manual.
abstract final class AppRefresh {
  static final attendance = ValueNotifier<int>(0);
  static final leave = ValueNotifier<int>(0);
  static final overtime = ValueNotifier<int>(0);
  static final employees = ValueNotifier<int>(0);
  static final announcements = ValueNotifier<int>(0);
  static final events = ValueNotifier<int>(0);
  static final warnings = ValueNotifier<int>(0);
  static final notifications = ValueNotifier<int>(0);

  static void pingAttendance() => attendance.value++;
  static void pingLeave() => leave.value++;
  static void pingOvertime() => overtime.value++;
  static void pingEmployees() => employees.value++;
  static void pingAnnouncements() => announcements.value++;
  static void pingEvents() => events.value++;
  static void pingWarnings() => warnings.value++;
  static void pingNotifications() => notifications.value++;

  /// Pemicu dari jenis notifikasi push. Selalu + lonceng.
  static void pingForKind(String kind) {
    switch (kind) {
      case 'leaveApproved':
      case 'leaveRejected':
      case 'collectiveLeaveApplied':
        pingLeave();
      case 'correctionApproved':
      case 'correctionRejected':
      case 'outOfAreaApproved':
      case 'outOfAreaRejected':
        pingAttendance();
      case 'overtimeApproved':
      case 'overtimeRejected':
        pingOvertime();
        pingLeave();
      case 'reviewRequested':
        pingAttendance();
        pingLeave();
        pingOvertime();
      case 'announcement':
        pingAnnouncements();
      case 'eventCancelled':
      case 'eventToday':
        pingEvents();
      case 'accountRegistered':
      case 'contractExpiring':
      case 'contractExpired':
        pingEmployees();
      case 'warningIssued':
      case 'warningExpiring':
        pingWarnings();
    }
    pingNotifications();
  }
}
