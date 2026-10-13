import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/session_storage.dart';
import 'api_time.dart';
import '../auth_repository.dart';
import '../leave_repository.dart';

/// [LeaveRepository] via REST.
class ApiLeaveRepository implements LeaveRepository {
  ApiLeaveRepository({
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

  LeaveType _type(Object? v) {
    for (final t in LeaveType.values) {
      if (t.name == v) return t;
    }
    return LeaveType.annual;
  }

  RequestStatus _status(Object? v) {
    for (final s in RequestStatus.values) {
      if (s.name == v) return s;
    }
    return RequestStatus.pending;
  }

  DateTime _dt(Object? v, [DateTime? fallback]) =>
      apiDateTime(v, fallback);

  LeaveRequest _req(Map<String, dynamic> m) {
    LeaveAttachment? att;
    if (m['attachment'] is Map) {
      final a = _map(m['attachment']);
      att = LeaveAttachment(
        name: (a['name'] ?? '').toString(),
        sizeBytes: (a['sizeBytes'] as num?)?.toInt() ?? 0,
        key: a['key'] as String?,
      );
    }
    return LeaveRequest(
      id: (m['id'] ?? '').toString(),
      type: _type(m['type']),
      start: _dt(m['start']),
      end: _dt(m['end']),
      workingDays: (m['workingDays'] as num?)?.toInt() ?? 0,
      reason: (m['reason'] ?? '').toString(),
      status: _status(m['status']),
      submittedAt: _dt(m['submittedAt']),
      attachment: att,
      reviewedBy: m['reviewedBy'] as String?,
      reviewedAt: apiDateTimeOpt(m['reviewedAt']),
      reviewerNote: m['reviewerNote'] as String?,
    );
  }

  LeaveBalance _balance(Map<String, dynamic> m) => LeaveBalance(
        year: (m['year'] as num?)?.toInt() ?? DateTime.now().year,
        quota: (m['quota'] as num?)?.toInt() ?? 12,
        used: (m['used'] as num?)?.toInt() ?? 0,
        pending: (m['pending'] as num?)?.toInt() ?? 0,
      );

  LeaveReviewItem _item(Map<String, dynamic> m) => LeaveReviewItem(
        employee: EmployeeRef(
          username: ((_map(m['employee']))['username'] ?? '').toString(),
          fullName: ((_map(m['employee']))['fullName'] ?? '').toString(),
        ),
        request: _req(_map(m['request'])),
        balance: _balance(_map(m['balance'])),
      );

  @override
  Future<LeaveBalance> fetchBalance(AuthUser user) async {
    final res = await _client.get(
      Uri.parse('$_base/leave/balance'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    return _balance(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<List<LeaveRequest>> fetchRequests(AuthUser user) async {
    final res = await _client.get(
      Uri.parse('$_base/leave/requests'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<LeaveRequest>.unmodifiable(
      [for (final e in (m['requests'] as List? ?? [])) _req(_map(e))],
    );
  }

  @override
  Future<LeaveRequest> submit(
    AuthUser user, {
    required LeaveType type,
    required DateTime start,
    required DateTime end,
    required String reason,
    LeaveAttachment? attachment,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/leave/requests'),
      headers: await _h(),
      body: jsonEncode({
        'type': type.name,
        'start': start.toIso8601String().substring(0, 10),
        'end': end.toIso8601String().substring(0, 10),
        'reason': reason,
        'attachmentName': attachment?.name,
        'attachmentSize': attachment?.sizeBytes,
        'attachmentKey': attachment?.key,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    _ping();
    return _req(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<LeaveRequest> cancel(AuthUser user, {required String id}) async {
    final res = await _client.post(
      Uri.parse('$_base/leave/requests/$id/cancel'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _req(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<List<LeaveReviewItem>> fetchReviewQueue(AuthUser actor) async {
    final res = await _client.get(
      Uri.parse('$_base/leave/queue'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<LeaveReviewItem>.unmodifiable(
      [for (final e in (m['queue'] as List? ?? [])) _item(_map(e))],
    );
  }

  @override
  Future<LeaveReviewItem> review(
    AuthUser actor, {
    required String id,
    required bool approve,
    String? note,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/leave/requests/$id/review'),
      headers: await _h(),
      body: jsonEncode({'approve': approve, 'note': note}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _item(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<List<CollectiveLeaveResult>> applyCollectiveLeave(
    AuthUser actor, {
    required List<String> usernames,
    required DateTime start,
    required DateTime end,
    required String reason,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/leave/collective'),
      headers: await _h(),
      body: jsonEncode({
        'usernames': usernames,
        'start': start.toIso8601String().substring(0, 10),
        'end': end.toIso8601String().substring(0, 10),
        'reason': reason,
      }),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<CollectiveLeaveResult>.unmodifiable(
      [
        for (final e in (m['results'] as List? ?? []))
          CollectiveLeaveResult(
            employee: EmployeeRef(
              username: ((_map(e))['employee'] as Map? ?? {})['username']?.toString() ?? '',
              fullName: ((_map(e))['employee'] as Map? ?? {})['fullName']?.toString() ?? '',
            ),
            days: ((_map(e))['days'] as num?)?.toInt() ?? 0,
            skipped: (_map(e))['skipped'] as String?,
          ),
      ],
    );
  }
}
