import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/session_storage.dart';
import '../auth_repository.dart';

/// Upload file via S3 presigned URL: presign ke server, PUT langsung ke S3.
class ApiUploadRepository {
  ApiUploadRepository({
    http.Client? client,
    required String baseUrl,
    required SessionStorage sessionStorage,
  })  : _client = client ?? http.Client(),
        _base = baseUrl.replaceAll(RegExp(r'/$'), ''),
        _sessions = sessionStorage;

  final http.Client _client;
  final String _base;
  final SessionStorage _sessions;

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

  Never _throw(String body, int status) {
    String msg = 'Upload gagal. Coba lagi.';
    try {
      final m = jsonDecode(body);
      if (m is Map && m['message'] != null) msg = m['message'].toString();
    } catch (_) {}
    throw AppException(msg);
  }

  /// {key, putUrl} — lalu PUT [bytes] ke [putUrl].
  Future<({String key, String putUrl})> presign({
    required String purpose,
    required String filename,
    required String contentType,
    required int size,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/uploads/presign'),
      headers: await _h(),
      body: jsonEncode({
        'purpose': purpose,
        'filename': filename,
        'contentType': contentType,
        'size': size,
      }),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (key: (m['key'] ?? '').toString(), putUrl: (m['putUrl'] ?? '').toString());
  }

  Future<void> putBytes({
    required String putUrl,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final res = await _client.put(
      Uri.parse(putUrl),
      headers: {'content-type': contentType},
      body: bytes,
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw const AppException('Upload file ke penyimpanan gagal. Coba lagi.');
    }
  }

  /// Upload sekali jalan: presign + PUT. Mengembalikan key S3.
  Future<String> upload({
    required String purpose,
    required String filename,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final p = await presign(
      purpose: purpose,
      filename: filename,
      contentType: contentType,
      size: bytes.length,
    );
    await putBytes(putUrl: p.putUrl, bytes: bytes, contentType: contentType);
    return p.key;
  }

  /// URL baca (presigned utk privat / publik utk avatar).
  Future<String> viewUrl(String key) async {
    final res = await _client.get(
      Uri.parse('$_base/uploads/view?key=${Uri.encodeComponent(key)}'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (m['url'] ?? '').toString();
  }
}
