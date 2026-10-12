import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/session_storage.dart';
import '../auth_repository.dart';
import '../notification_repository.dart';

/// [NotificationRepository] via REST (polling; push/FCM menyusul).
class ApiNotificationRepository implements NotificationRepository {
  ApiNotificationRepository({
    http.Client? client,
    required String baseUrl,
    required SessionStorage sessionStorage,
    this.onChanged,
  })  : _client = client ?? http.Client(),
        _base = baseUrl.replaceAll(RegExp(r'/$'), ''),
        _sessions = sessionStorage;

  final http.Client _client;
  final String _base;
  final SessionStorage _sessions;

  /// Dipanggil setelah tandai-baca agar badge ikut segar.
  final VoidCallback? onChanged;
  final _notifier = ValueNotifier<int>(0);

  @override
  Listenable get changes => _notifier;
  void _ping() {
    _notifier.value++;
    onChanged?.call();
  }

  Future<Map<String, String>> _h() async {
    final t = await _sessions.readToken();
    if (t == null || t.isEmpty) {
      throw const AuthException('Sesi berakhir. Silakan masuk kembali.');
    }
    return {
      'content-type': 'application/json',
      'authorization': 'Bearer $t',
    };
  }

  NotificationKind _kind(Object? v) {
    for (final k in NotificationKind.values) {
      if (k.name == v) return k;
    }
    return NotificationKind.announcement;
  }

  AppNotification _parse(Map<String, dynamic> m) => AppNotification(
        id: (m['id'] ?? '').toString(),
        kind: _kind(m['kind']),
        title: (m['title'] ?? '').toString(),
        body: (m['body'] ?? '').toString(),
        createdAt:
            DateTime.tryParse((m['createdAt'] ?? '').toString()) ?? DateTime.now(),
        read: (m['read'] as bool?) ?? false,
      );

  @override
  Future<List<AppNotification>> fetch(AuthUser user) async {
    final res = await _client.get(
      Uri.parse('$_base/notifications'),
      headers: await _h(),
    );
    if (res.statusCode != 200) throw const AppException('Notifikasi gagal dimuat.');
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<AppNotification>.unmodifiable(
      [
        for (final e in (m['notifications'] as List? ?? []))
          _parse(Map<String, dynamic>.from(e as Map)),
      ],
    );
  }

  @override
  Future<int> unreadCount(AuthUser user) async {
    final res = await _client.get(
      Uri.parse('$_base/notifications/unread-count'),
      headers: await _h(),
    );
    if (res.statusCode != 200) return 0;
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (m['unread'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> markRead(AuthUser user, {required String id}) async {
    await _client.post(
      Uri.parse('$_base/notifications/$id/read'),
      headers: await _h(),
    );
    _ping();
  }

  @override
  Future<void> markAllRead(AuthUser user) async {
    await _client.post(
      Uri.parse('$_base/notifications/read-all'),
      headers: await _h(),
    );
    _ping();
  }

  @override
  Future<void> clearAll(AuthUser user) async {
    await _client.delete(
      Uri.parse('$_base/notifications'),
      headers: await _h(),
    );
    _ping();
  }
}
