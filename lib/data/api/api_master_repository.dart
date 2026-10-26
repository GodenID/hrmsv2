import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/session_storage.dart';
import '../auth_repository.dart';
import '../master_data.dart';

/// [MasterDataRepository] via REST.
class ApiMasterRepository implements MasterDataRepository {
  ApiMasterRepository({
    http.Client? client,
    required String baseUrl,
    required SessionStorage sessionStorage,
  })  : _client = client ?? http.Client(),
        _base = baseUrl.replaceAll(RegExp(r'/$'), ''),
        _sessions = sessionStorage;

  final http.Client _client;
  final String _base;
  final SessionStorage _sessions;
  final _notifier = ValueNotifier<int>(0);

  @override
  Listenable get changes => _notifier;

  void _ping() => _notifier.value++;

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
    String msg = 'Terjadi kesalahan. Coba lagi.';
    try {
      final m = jsonDecode(body);
      if (m is Map && m['message'] != null) msg = m['message'].toString();
    } catch (_) {}
    if (status == 401 || status == 403) throw PermissionDeniedException(msg);
    throw AppException(msg);
  }

  Map<String, dynamic> _map(Object? e) => Map<String, dynamic>.from(e as Map);

  MasterDivision _division(Map<String, dynamic> m) => MasterDivision(
        code: (m['code'] ?? '').toString(),
        label: (m['label'] ?? '').toString(),
        active: (m['active'] as bool?) ?? true,
        employees: (m['employees'] as num?)?.toInt() ?? 0,
      );

  MasterPosition _position(Map<String, dynamic> m) => MasterPosition(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        active: (m['active'] as bool?) ?? true,
        employees: (m['employees'] as num?)?.toInt() ?? 0,
      );

  @override
  Future<List<MasterDivision>> fetchDivisions(AuthUser actor) async {
    final res = await _client.get(
      Uri.parse('$_base/master/divisions'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<MasterDivision>.unmodifiable(
      [for (final e in (m['divisions'] as List? ?? [])) _division(_map(e))],
    );
  }

  @override
  Future<List<MasterPosition>> fetchPositions(AuthUser actor) async {
    final res = await _client.get(
      Uri.parse('$_base/master/positions'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<MasterPosition>.unmodifiable(
      [for (final e in (m['positions'] as List? ?? [])) _position(_map(e))],
    );
  }

  @override
  Future<MasterDivision> createDivision(
    AuthUser actor, {
    required String label,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/master/divisions'),
      headers: await _h(),
      body: jsonEncode({'label': label}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    _ping();
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return _division(_map(m['division']));
  }

  @override
  Future<MasterDivision> updateDivision(
    AuthUser actor, {
    required String code,
    String? label,
    bool? active,
  }) async {
    final res = await _client.patch(
      Uri.parse('$_base/master/divisions/${Uri.encodeComponent(code)}'),
      headers: await _h(),
      body: jsonEncode({
        'label': ?label,
        'active': ?active,
      }),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return _division(_map(m['division']));
  }

  @override
  Future<void> deleteDivision(
    AuthUser actor, {
    required String code,
  }) async {
    final res = await _client.delete(
      Uri.parse('$_base/master/divisions/${Uri.encodeComponent(code)}'),
      headers: await _h(),
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      _throw(res.body, res.statusCode);
    }
    _ping();
  }

  @override
  Future<MasterPosition> createPosition(
    AuthUser actor, {
    required String name,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/master/positions'),
      headers: await _h(),
      body: jsonEncode({'name': name}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    _ping();
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return _position(_map(m['position']));
  }

  @override
  Future<MasterPosition> updatePosition(
    AuthUser actor, {
    required String id,
    String? name,
    bool? active,
  }) async {
    final res = await _client.patch(
      Uri.parse('$_base/master/positions/${Uri.encodeComponent(id)}'),
      headers: await _h(),
      body: jsonEncode({
        'name': ?name,
        'active': ?active,
      }),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return _position(_map(m['position']));
  }

  @override
  Future<void> deletePosition(AuthUser actor, {required String id}) async {
    final res = await _client.delete(
      Uri.parse('$_base/master/positions/${Uri.encodeComponent(id)}'),
      headers: await _h(),
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      _throw(res.body, res.statusCode);
    }
    _ping();
  }
}
