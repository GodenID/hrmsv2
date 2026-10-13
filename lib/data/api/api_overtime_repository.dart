import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/session_storage.dart';
import 'api_time.dart';
import '../auth_repository.dart';
import '../overtime_repository.dart';

/// [OvertimeRepository] via REST.
class ApiOvertimeRepository implements OvertimeRepository {
  ApiOvertimeRepository({
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

  RequestStatus _status(Object? v) {
    for (final s in RequestStatus.values) {
      if (s.name == v) return s;
    }
    return RequestStatus.pending;
  }

  OvertimeRequest _req(Map<String, dynamic> m) => OvertimeRequest(
        id: (m['id'] ?? '').toString(),
        date: apiDateTime(m['date']),
        start: apiDateTime(m['start']),
        end: apiDateTime(m['end']),
        reason: (m['reason'] ?? '').toString(),
        status: _status(m['status']),
        submittedAt:
            apiDateTime(m['submittedAt']),
        reviewedBy: m['reviewedBy'] as String?,
        reviewedAt: apiDateTimeOpt(m['reviewedAt']),
        reviewerNote: m['reviewerNote'] as String?,
      );

  @override
  Future<List<OvertimeRequest>> fetchRequests(AuthUser user) async {
    final res = await _client.get(
      Uri.parse('$_base/overtime/requests'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<OvertimeRequest>.unmodifiable(
      [for (final e in (m['requests'] as List? ?? [])) _req(_map(e))],
    );
  }

  @override
  Future<OvertimeRequest> submit(
    AuthUser user, {
    required DateTime date,
    required DateTime start,
    required DateTime end,
    required String reason,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/overtime/requests'),
      headers: await _h(),
      body: jsonEncode({
        'date': date.toIso8601String().substring(0, 10),
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'reason': reason,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    _ping();
    return _req(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<OvertimeRequest> cancel(AuthUser user, {required String id}) async {
    final res = await _client.post(
      Uri.parse('$_base/overtime/requests/$id/cancel'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _req(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<List<OvertimeReviewItem>> fetchReviewQueue(AuthUser actor) async {
    final res = await _client.get(
      Uri.parse('$_base/overtime/queue'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<OvertimeReviewItem>.unmodifiable(
      [
        for (final e in (m['queue'] as List? ?? []))
          OvertimeReviewItem(
            employee: EmployeeRef(
              username: (_map(_map(e)['employee'])['username'] ?? '').toString(),
              fullName: (_map(_map(e)['employee'])['fullName'] ?? '').toString(),
            ),
            request: _req(_map(_map(e)['request'])),
          ),
      ],
    );
  }

  @override
  Future<OvertimeReviewItem> review(
    AuthUser actor, {
    required String id,
    required bool approve,
    String? note,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/overtime/requests/$id/review'),
      headers: await _h(),
      body: jsonEncode({'approve': approve, 'note': note}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return OvertimeReviewItem(
      employee: EmployeeRef(
        username: (_map(m['employee'])['username'] ?? '').toString(),
        fullName: (_map(m['employee'])['fullName'] ?? '').toString(),
      ),
      request: _req(_map(m['request'])),
    );
  }
}
