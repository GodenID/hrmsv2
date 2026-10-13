import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth_repository.dart';

/// Base URL API, diisi via `--dart-define=API_BASE_URL=https://api.domain`.
/// Kosong = mode mock (pengembangan).
class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static bool get useApi => baseUrl.isNotEmpty;
}

/// [AuthRepository] yang bicara ke backend Shelf + PostgreSQL.
/// Kontrak & pesan galat disamakan dengan mock agar halaman tidak berubah.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _base = (baseUrl ?? ApiConfig.baseUrl).replaceAll(RegExp(r'/$'), '');

  final http.Client _client;
  final String _base;

  Uri _u(String path) => Uri.parse('$_base$path');

  Never _throw(Object body, int fallbackStatus) {
    String msg = 'Terjadi kesalahan. Coba lagi.';
    String? field;
    int status = fallbackStatus;
    try {
      final m = body is String ? jsonDecode(body) : body;
      if (m is Map) {
        msg = (m['message'] ?? msg).toString();
        field = m['field'] as String?;
        if (m['status'] is int) status = m['status'] as int;
      }
    } catch (_) {}
    if (status == 422 || status == 409) {
      throw RegistrationException(msg, field: _fieldOf(field));
    }
    throw AuthException(msg);
  }

  RegistrationField? _fieldOf(String? f) {
    if (f == null) return null;
    for (final v in RegistrationField.values) {
      if (v.name == f) return v;
    }
    return null;
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

  @override
  Future<bool> isRegistrationOpen() async {
    final res = await _client.get(_u('/auth/registration-open'), headers: _h());
    if (res.statusCode != 200) return true;
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (m['open'] as bool?) ?? true;
  }

  @override
  Future<void> checkUsernameAvailable(String username) async {
    final res = await _client.post(
      _u('/auth/check-username'),
      headers: _h(),
      body: jsonEncode({'username': username}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
  }

  @override
  Future<RegisteredAccount> register(RegistrationDraft d) async {
    final res = await _client.post(
      _u('/auth/register'),
      headers: _h(),
      body: jsonEncode({
        'username': d.username,
        'password': d.password,
        'fullName': d.fullName,
        'nik': d.nik,
        'birthPlace': d.birthPlace,
        'birthDate': d.birthDate.toIso8601String().substring(0, 10),
        'gender': d.gender.name,
        'address': d.address,
        'email': d.email,
        'phone': d.phone,
        'emergencyName': d.emergencyContact.name,
        'emergencyRelation': d.emergencyContact.relation.name,
        'emergencyPhone': d.emergencyContact.phone,
        'division': d.division.name,
        'employmentStatus': d.employmentStatus.name,
        'contractMonths': d.contractMonths,
        'privacyConsent': d.privacyConsent,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final um = (m['user'] ?? {}) as Map<String, dynamic>;
    return RegisteredAccount(
      username: (um['username'] ?? d.username).toString(),
      fullName: (um['fullName'] ?? d.fullName).toString(),
      role: UserRole.values.firstWhere(
        (r) => r.name == (um['role'] ?? 'staff'),
        orElse: () => UserRole.staff,
      ),
      division: d.division,
      employmentStatus: d.employmentStatus,
      contractMonths: d.contractMonths,
    );
  }
}
