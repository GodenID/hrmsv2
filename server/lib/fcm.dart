import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;

import 'config.dart';

/// Pengirim push FCM HTTP v1. Tanpa service account (env) = nonaktif anggun.
class FcmSender {
  FcmSender(this.cfg);

  final Config cfg;

  auth.AutoRefreshingAuthClient? _client;
  http.Client? _raw;

  bool get enabled =>
      cfg.fcmProjectId.isNotEmpty && cfg.fcmServiceAccount.isNotEmpty;

  Future<void> _ensure() async {
    if (_client != null) return;
    final creds = auth.ServiceAccountCredentials.fromJson(
      jsonDecode(cfg.fcmServiceAccount),
    );
    _raw = http.Client();
    _client = await auth.clientViaServiceAccount(
      creds,
      const ['https://www.googleapis.com/auth/firebase.messaging'],
      baseClient: _raw,
    );
  }

  /// Kirim ke satu token. false = token mati (penerima hapus).
  Future<bool> send(
    String token,
    String title,
    String body,
    String kind, {
    String? refType,
    String? refId,
  }) async {
    if (!enabled) return true;
    try {
      await _ensure();
      final data = <String, String>{'kind': kind};
      if (refType != null) data['refType'] = refType;
      if (refId != null) data['refId'] = refId;
      final res = await _client!.post(
        Uri.parse(
          'https://fcm.googleapis.com/v1/projects/${cfg.fcmProjectId}/messages:send',
        ),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'message': {
            'token': token,
            'notification': {'title': title, 'body': body},
            'android': {'priority': 'HIGH'},
            'data': data,
          },
        }),
      );
      if (res.statusCode == 200) return true;
      if (res.statusCode == 404) return false;
      stderr.writeln(
          'FCM gagal ${res.statusCode} [$kind]: ${res.body.substring(0, res.body.length.clamp(0, 200))}');
      return true;
    } catch (e) {
      stderr.writeln('FCM exception [$kind]: $e');
      return true;
    }
  }
}
