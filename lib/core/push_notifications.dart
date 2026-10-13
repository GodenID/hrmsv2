import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../features/shell/shell_controller.dart';

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
        onDidReceiveNotificationResponse: (r) => _openApprovals(),
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
            payload: (m.data['kind'] ?? '').toString(),
          );
        } catch (_) {}
      });
      // Ketuk banner/tray: buka menu Persetujuan (daftar antrean).
      FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);
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

  static void _openFromMessage(RemoteMessage m) {
    // Hanya pengajuan (reviewRequested) yang punya menu tujuan pasti.
    // Detail spesifik dibuka dari halaman Notifikasi di aplikasi.
    if ((m.data['kind'] ?? '') != 'reviewRequested') return;
    _openApprovals();
  }

  static void _openApprovals() {
    final context = navigatorKey.currentContext;
    if (context == null) {
      _pendingTap = const {'kind': 'reviewRequested'};
      return;
    }
    ShellController.maybeOf(context)?.openTab(ShellTab.approvals);
  }

  /// Dipanggil shell setelah login: buka Persetujuan bila ada ketukan
  /// tertunda dari tray saat aplikasi mati.
  static void consumePendingTap(BuildContext context) {
    final pending = _pendingTap;
    if (pending == null) return;
    _pendingTap = null;
    if ((pending['kind'] ?? '') != 'reviewRequested') return;
    ShellController.maybeOf(context)?.openTab(ShellTab.approvals);
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
