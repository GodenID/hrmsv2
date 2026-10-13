import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/session_storage.dart';
import 'api_time.dart';
import '../attendance_repository.dart';
import '../auth_repository.dart';
import '../employee.dart';
import '../leave_repository.dart' show LeaveAttachment, LeaveRequest, LeaveType;

/// [AttendanceRepository] via REST. Jam & jarak dihitung server.
class ApiAttendanceRepository implements AttendanceRepository {
  ApiAttendanceRepository({
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

  RequestStatus _status(Object? v) {
    for (final s in RequestStatus.values) {
      if (s.name == v) return s;
    }
    return RequestStatus.pending;
  }

  DateTime? _dt(Object? v) => apiDateTimeOpt(v);

  AttendanceRecord _record(Map<String, dynamic> m) => AttendanceRecord(
        date: apiDateTime(m['date']),
        clockIn: _dt(m['clockIn']),
        clockOut: _dt(m['clockOut']),
        clockInLocation: m['clockInLocation'] as String?,
        clockOutLocation: m['clockOutLocation'] as String?,
      );

  AttendanceLocation _loc(Map<String, dynamic> m) => AttendanceLocation(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        radiusMeters: (m['radiusMeters'] as num).toInt(),
      );

  AttendanceDayStatus _dayStatus(Object? v) {
    for (final s in AttendanceDayStatus.values) {
      if (s.name == v) return s;
    }
    return AttendanceDayStatus.absent;
  }

  LeaveRequest? _leave(Object? v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    LeaveAttachment? att;
    if (m['attachment'] is Map) {
      final a = Map<String, dynamic>.from(m['attachment'] as Map);
      att = LeaveAttachment(
        name: (a['name'] ?? '').toString(),
        sizeBytes: (a['sizeBytes'] as num?)?.toInt() ?? 0,
      );
    }
    RequestStatus status = RequestStatus.pending;
    for (final s in RequestStatus.values) {
      if (s.name == m['status']) status = s;
    }
    LeaveType type = LeaveType.annual;
    for (final t in LeaveType.values) {
      if (t.name == m['type']) type = t;
    }
    return LeaveRequest(
      id: (m['id'] ?? '').toString(),
      type: type,
      start: apiDateTime(m['start']),
      end: apiDateTime(m['end']),
      workingDays: (m['workingDays'] as num?)?.toInt() ?? 0,
      reason: (m['reason'] ?? '').toString(),
      status: status,
      submittedAt:
          apiDateTime(m['submittedAt']),
      attachment: att,
      reviewedBy: m['reviewedBy'] as String?,
      reviewedAt: apiDateTimeOpt(m['reviewedAt']),
      reviewerNote: m['reviewerNote'] as String?,
    );
  }

  AttendanceCorrection _correction(Map<String, dynamic> m) => AttendanceCorrection(
        id: (m['id'] ?? '').toString(),
        date: apiDateTime(m['date']),
        clockIn: _dt(m['clockIn']) ?? DateTime.now(),
        clockOut: _dt(m['clockOut']) ?? DateTime.now(),
        reason: (m['reason'] ?? '').toString(),
        status: _status(m['status']),
        submittedAt: _dt(m['submittedAt']) ?? DateTime.now(),
        reviewedBy: m['reviewedBy'] as String?,
        reviewedAt: _dt(m['reviewedAt']),
        reviewerNote: m['reviewerNote'] as String?,
      );

  OutOfAreaRequest _ooa(Map<String, dynamic> m) => OutOfAreaRequest(
        id: (m['id'] ?? '').toString(),
        date: apiDateTime(m['date']),
        kind: OutOfAreaKind.values.firstWhere(
          (k) => k.name == m['kind'],
          orElse: () => OutOfAreaKind.clockIn,
        ),
        requestedAt: _dt(m['requestedAt']) ?? DateTime.now(),
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        accuracyMeters: (m['accuracyMeters'] as num?)?.toDouble(),
        nearestLocationName: (m['nearestLocationName'] ?? '-').toString(),
        distanceMeters: (m['distanceMeters'] as num?)?.toDouble() ?? 0,
        reason: (m['reason'] ?? '').toString(),
        status: _status(m['status']),
        submittedAt: _dt(m['submittedAt']) ?? DateTime.now(),
        reviewedBy: m['reviewedBy'] as String?,
        reviewedAt: _dt(m['reviewedAt']),
        reviewerNote: m['reviewerNote'] as String?,
      );

  OvertimeRequest _overtime(Map<String, dynamic> m) => OvertimeRequest(
        id: (m['id'] ?? '').toString(),
        date: apiDateTime(m['date']),
        start: _dt(m['start']) ?? DateTime.now(),
        end: _dt(m['end']) ?? DateTime.now(),
        reason: (m['reason'] ?? '').toString(),
        status: _status(m['status']),
        submittedAt: _dt(m['submittedAt']) ?? DateTime.now(),
        reviewedBy: m['reviewedBy'] as String?,
        reviewedAt: _dt(m['reviewedAt']),
        reviewerNote: m['reviewerNote'] as String?,
      );

  EmployeeRef _ref(Map<String, dynamic> m) => EmployeeRef(
        username: (m['username'] ?? '').toString(),
        fullName: (m['fullName'] ?? '').toString(),
      );

  Map<String, dynamic> _map(Object? e) => Map<String, dynamic>.from(e as Map);

  @override
  Future<AttendanceRecord> fetchToday(AuthUser user) async {
    final res = await _client.get(
      Uri.parse('$_base/attendance/today'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    return _record(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Map<String, dynamic> _pos(GeoPoint p) => {
        'latitude': p.latitude,
        'longitude': p.longitude,
        'accuracyMeters': p.accuracyMeters,
        'isMocked': p.isMocked,
      };

  @override
  Future<AttendanceRecord> clockIn(AuthUser user, {required GeoPoint position}) async {
    final res = await _client.post(
      Uri.parse('$_base/attendance/clock-in'),
      headers: await _h(),
      body: jsonEncode(_pos(position)),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _record(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<AttendanceRecord> clockOut(AuthUser user, {required GeoPoint position}) async {
    final res = await _client.post(
      Uri.parse('$_base/attendance/clock-out'),
      headers: await _h(),
      body: jsonEncode(_pos(position)),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _record(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<List<AttendanceLocation>> fetchLocations(AuthUser user) async {
    final res = await _client.get(
      Uri.parse('$_base/attendance/locations'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = m['locations'] as List? ?? [];
    return List<AttendanceLocation>.unmodifiable(
      [for (final e in raw) _loc((e as Map).cast<String, dynamic>())],
    );
  }

  @override
  Future<AttendanceLocation> saveLocation(
    AuthUser actor, {
    String? id,
    required AttendanceLocationDraft draft,
  }) async {
    final body = jsonEncode({
      'name': draft.name,
      'latitude': draft.latitude,
      'longitude': draft.longitude,
      'radiusMeters': draft.radiusMeters,
    });
    final res = id == null
        ? await _client.post(Uri.parse('$_base/attendance/locations'),
            headers: await _h(), body: body)
        : await _client.put(Uri.parse('$_base/attendance/locations/$id'),
            headers: await _h(), body: body);
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    _ping();
    return _loc(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<void> deleteLocation(AuthUser actor, {required String id}) async {
    final res = await _client.delete(
      Uri.parse('$_base/attendance/locations/$id'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
  }

  @override
  Future<List<AttendanceDay>> fetchMonth(AuthUser user,
      {required int year, required int month}) async {
    final res = await _client.get(
      Uri.parse('$_base/attendance/month?year=$year&month=$month'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<AttendanceDay>.unmodifiable(
      [
        for (final e in (m['days'] as List? ?? []))
          AttendanceDay(
            date: apiDateTime(_map(e)['date']),
            status: _dayStatus(_map(e)['status']),
            clockIn: _dt(_map(e)['clockIn']),
            clockOut: _dt(_map(e)['clockOut']),
            clockInLocation: _map(e)['clockInLocation'] as String?,
            clockOutLocation: _map(e)['clockOutLocation'] as String?,
            leave: _leave(_map(e)['leave']),
            correction: _map(e)['correction'] == null
                ? null
                : _correction(_map(_map(e)['correction'])),
            outOfArea: _map(e)['outOfArea'] == null
                ? null
                : _ooa(_map(_map(e)['outOfArea'])),
            overtime: _map(e)['overtime'] == null
                ? null
                : _overtime(_map(_map(e)['overtime'])),
          ),
      ],
    );
  }

  @override
  Future<DateTime> fetchFirstMonth(AuthUser user) async {
    final res = await _client.get(
      Uri.parse('$_base/attendance/first-month'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return DateTime((m['year'] as num).toInt(), (m['month'] as num).toInt());
  }

  @override
  Future<AttendanceCorrection> submitCorrection(
    AuthUser user, {
    required DateTime date,
    required DateTime clockIn,
    required DateTime clockOut,
    required String reason,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/attendance/corrections'),
      headers: await _h(),
      body: jsonEncode({
        'date': date.toIso8601String().substring(0, 10),
        // Kirim instant UTC (bertanda Z); tanpa ini server (UTC) membaca jam
        // lokal perangkat sebagai UTC dan hasilnya bergeser 7 jam.
        'clockIn': clockIn.toUtc().toIso8601String(),
        'clockOut': clockOut.toUtc().toIso8601String(),
        'reason': reason,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    _ping();
    return _correction(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<List<CorrectionReviewItem>> fetchCorrectionQueue(AuthUser actor) async {
    final res = await _client.get(
      Uri.parse('$_base/attendance/corrections/queue'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<CorrectionReviewItem>.unmodifiable(
      [
        for (final raw in (m['queue'] as List? ?? []))
          CorrectionReviewItem(
            employee: _ref(_map(_map(raw)['employee'])),
            correction: _correction(_map(_map(raw)['correction'])),
          ),
      ],
    );
  }

  @override
  Future<CorrectionReviewItem> reviewCorrection(
    AuthUser actor, {
    required String id,
    required bool approve,
    String? note,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/attendance/corrections/$id/review'),
      headers: await _h(),
      body: jsonEncode({'approve': approve, 'note': note}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return CorrectionReviewItem(
      employee: _ref(m['employee'] as Map<String, dynamic>),
      correction: _correction(m['correction'] as Map<String, dynamic>),
    );
  }


  @override
  Future<void> deleteCorrection(AuthUser actor, {required String id}) async {
    final res = await _client.delete(
      Uri.parse('$_base/attendance/corrections/$id'),
      headers: await _h(),
    );
    if (res.statusCode != 200 && res.statusCode != 204) _throw(res.body, res.statusCode);
    _ping();
  }

  @override
  Future<AttendanceCorrection> cancelCorrection(AuthUser user, {required String id}) async {
    final res = await _client.post(
      Uri.parse('$_base/attendance/corrections/$id/cancel'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _correction(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<OutOfAreaRequest> submitOutOfArea(
    AuthUser user, {
    required OutOfAreaKind kind,
    required GeoPoint position,
    required String reason,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/attendance/out-of-area'),
      headers: await _h(),
      body: jsonEncode({
        'kind': kind.name,
        ..._pos(position),
        'reason': reason,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    _ping();
    return _ooa(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<List<OutOfAreaRequest>> fetchMyOutOfArea(AuthUser user) async {
    final res = await _client.get(
      Uri.parse('$_base/attendance/out-of-area/mine'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final raw = m['requests'] as List? ?? [];
    return List<OutOfAreaRequest>.unmodifiable(
      [for (final e in raw) _ooa(_map(e))],
    );
  }

  @override
  Future<List<OutOfAreaReviewItem>> fetchOutOfAreaQueue(AuthUser actor) async {
    final res = await _client.get(
      Uri.parse('$_base/attendance/out-of-area/queue'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<OutOfAreaReviewItem>.unmodifiable(
      [
        for (final e in (m['queue'] as List? ?? []))
          OutOfAreaReviewItem(
            employee: _ref(_map(_map(e)['employee'])),
            request: _ooa(_map(_map(e)['request'])),
          ),
      ],
    );
  }

  @override
  Future<OutOfAreaReviewItem> reviewOutOfArea(
    AuthUser actor, {
    required String id,
    required bool approve,
    String? note,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/attendance/out-of-area/$id/review'),
      headers: await _h(),
      body: jsonEncode({'approve': approve, 'note': note}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return OutOfAreaReviewItem(
      employee: _ref(m['employee'] as Map<String, dynamic>),
      request: _ooa(m['request'] as Map<String, dynamic>),
    );
  }


  @override
  Future<void> deleteOutOfArea(AuthUser actor, {required String id}) async {
    final res = await _client.delete(
      Uri.parse('$_base/attendance/out-of-area/$id'),
      headers: await _h(),
    );
    if (res.statusCode != 200 && res.statusCode != 204) _throw(res.body, res.statusCode);
    _ping();
  }
  @override
  Future<OutOfAreaRequest> cancelOutOfArea(AuthUser user, {required String id}) async {
    final res = await _client.post(
      Uri.parse('$_base/attendance/out-of-area/$id/cancel'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _ooa(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
