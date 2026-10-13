import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/session_storage.dart';
import 'api_time.dart';
import '../auth_repository.dart';
import '../employee.dart';
import '../warning_repository.dart';

/// [WarningRepository] via REST.
class ApiWarningRepository implements WarningRepository {
  ApiWarningRepository({
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

  WarningSeverity _severity(Object? v) {
    for (final s in WarningSeverity.values) {
      if (s.name == v) return s;
    }
    return WarningSeverity.ringan;
  }

  DateTime? _dt(Object? v) => apiDateTimeOpt(v);

  WarningLetter _letter(Map<String, dynamic> m) => WarningLetter(
        id: (m['id'] ?? '').toString(),
        employeeUsername: (m['employeeUsername'] ?? '').toString(),
        violationName: (m['violationName'] ?? '').toString(),
        severity: _severity(m['severity']),
        level: (m['level'] as num?)?.toInt() ?? 1,
        incidentDate: apiDateTime(m['incidentDate']),
        description: (m['description'] ?? '').toString(),
        articleRef: (m['articleRef'] ?? '').toString(),
        issuedBy: (m['issuedBy'] ?? '').toString(),
        issuedByName: (m['issuedByName'] ?? '').toString(),
        issuedAt: apiDateTime(m['issuedAt']),
        expiresAt: apiDateTime(m['expiresAt']),
        acknowledgedAt: _dt(m['acknowledgedAt']),
        acknowledgedBy: m['acknowledgedBy'] as String?,
        refused: (m['refused'] as bool?) ?? false,
        witness1: m['witness1'] as String?,
        witness2: m['witness2'] as String?,
        appeal: m['appeal'] as String?,
        appealAt: _dt(m['appealAt']),
        appealAccepted: m['appealAccepted'] as bool?,
        appealResponseNote: m['appealResponseNote'] as String?,
        appealRespondedAt: _dt(m['appealRespondedAt']),
      );

  WarningLetterDetail _detail(Map<String, dynamic> m) => WarningLetterDetail(
        employee: EmployeeRef(
          username: (_map(m['employee'])['username'] ?? '').toString(),
          fullName: (_map(m['employee'])['fullName'] ?? '').toString(),
        ),
        letter: _letter(_map(m['letter'])),
      );

  @override
  Future<List<EmployeeRef>> fetchIssuableEmployees(AuthUser actor) async {
    final res = await _client.get(
      Uri.parse('$_base/warnings/issuable'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<EmployeeRef>.unmodifiable(
      [
        for (final e in (m['employees'] as List? ?? []))
          EmployeeRef(
            username: (_map(e)['username'] ?? '').toString(),
            fullName: (_map(e)['fullName'] ?? '').toString(),
          ),
      ],
    );
  }

  @override
  Future<WarningSuggestion> suggestLevel(
    AuthUser actor, {
    required String username,
  }) async {
    final res = await _client.get(
      Uri.parse('$_base/warnings/suggest?username=${Uri.encodeComponent(username)}'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return WarningSuggestion(
      suggestedLevel: (m['suggestedLevel'] as num?)?.toInt() ?? 1,
      activeCount: (m['activeCount'] as num?)?.toInt() ?? 0,
      phkEligible: (m['phkEligible'] as bool?) ?? false,
    );
  }

  @override
  Future<WarningLetterDetail> issue(
    AuthUser actor, {
    required String username,
    required String violationName,
    required WarningSeverity severity,
    required int level,
    required DateTime incidentDate,
    required String description,
    required String articleRef,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/warnings'),
      headers: await _h(),
      body: jsonEncode({
        'username': username,
        'violationName': violationName,
        'severity': severity.name,
        'level': level,
        'incidentDate': incidentDate.toIso8601String().substring(0, 10),
        'description': description,
        'articleRef': articleRef,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    _ping();
    return _detail(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<List<WarningLetterDetail>> _list(String path) async {
    final res = await _client.get(
      Uri.parse('$_base$path'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<WarningLetterDetail>.unmodifiable(
      [for (final e in (m['letters'] as List? ?? [])) _detail(_map(e))],
    );
  }

  @override
  Future<List<WarningLetterDetail>> fetchLetters(AuthUser actor) => _list('/warnings');

  @override
  Future<List<WarningLetterDetail>> fetchMyLetters(AuthUser user) =>
      _list('/warnings/mine');

  @override
  Future<WarningLetterDetail> acknowledge(
    AuthUser user, {
    required String id,
    required bool refused,
    String? witness1,
    String? witness2,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/warnings/$id/acknowledge'),
      headers: await _h(),
      body: jsonEncode({
        'refused': refused,
        'witness1': witness1,
        'witness2': witness2,
      }),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _detail(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<WarningLetterDetail> appeal(
    AuthUser user, {
    required String id,
    required String text,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/warnings/$id/appeal'),
      headers: await _h(),
      body: jsonEncode({'text': text}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _detail(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<WarningLetterDetail> respondAppeal(
    AuthUser actor, {
    required String id,
    required bool accept,
    required String note,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/warnings/$id/respond-appeal'),
      headers: await _h(),
      body: jsonEncode({'accept': accept, 'note': note}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _detail(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
