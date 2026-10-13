import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth_repository.dart';

/// Base URL API, diisi via `--dart-define=API_BASE_URL=https://api.domain`.
/// Wajib diisi untuk build aplikasi (lihat `main.dart`).
class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
}

/// [AuthRepository] yang bicara ke backend Shelf + PostgreSQL.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _base = (baseUrl ?? ApiConfig.baseUrl).replaceAll(RegExp(r'/$'), '');

  final http.Client _client;
  final String _base;

  Uri _u(String path) => Uri.parse('$_base$path');

  Never _throw(Object body, int status) {
    String msg = 'Terjadi kesalahan. Coba lagi.';
    try {
      final m = body is String ? jsonDecode(body) : body;
      if (m is Map) msg = (m['message'] ?? msg).toString();
    } catch (_) {}
    throw AuthException(msg);
  }

  Map<String, String> _h([String? token]) => {
        'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      };

  AuthUser _user(Map<String, dynamic> m) => AuthUser(
        username: (m['username'] ?? '').toString(),
        fullName: (m['fullName'] ?? '').toString(),
        role: UserRole.values.firstWhere(
          (r) => r.name == (m['role'] ?? 'staff'),
          orElse: () => UserRole.staff,
        ),
        mustChangePassword: (m['mustChangePassword'] as bool?) ?? false,
        profileIncomplete: (m['profileIncomplete'] as bool?) ?? false,
      );

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final res = await _client.post(
      _u('/auth/login'),
      headers: _h(),
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final um = m['user'] as Map<String, dynamic>;
    return AuthSession(token: (m['token'] ?? '').toString(), user: _user(um));
  }

  @override
  Future<AuthUser> restoreSession(String token) async {
    final res = await _client.get(_u('/auth/me'), headers: _h(token));
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return _user(m['user'] as Map<String, dynamic>);
  }

  @override
  Future<void> logout(String token) async {
    try {
      await _client.post(_u('/auth/logout'), headers: _h(token));
    } catch (_) {}
  }

  @override
  Future<void> logoutOthers(AuthUser user, {required String currentToken}) async {
    final res = await _client.post(
      _u('/auth/logout-others'),
      headers: _h(currentToken),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
  }

  @override
  Future<void> verifyUsername(String username) async {
    final res = await _client.post(
      _u('/auth/recovery/verify-username'),
      headers: _h(),
      body: jsonEncode({'username': username}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
  }

  @override
  Future<String> verifyNik({required String username, required String nik}) async {
    final res = await _client.post(
      _u('/auth/recovery/verify-nik'),
      headers: _h(),
      body: jsonEncode({'username': username, 'nik': nik}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (m['resetToken'] ?? '').toString();
  }

  @override
  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  }) async {
    final res = await _client.post(
      _u('/auth/recovery/reset'),
      headers: _h(),
      body: jsonEncode({'resetToken': resetToken, 'newPassword': newPassword}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
  }
}
