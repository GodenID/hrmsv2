import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/session_storage.dart';
import 'api_time.dart';
import '../auth_repository.dart';
import '../event_repository.dart';

/// [EventRepository] via REST.
class ApiEventRepository implements EventRepository {
  ApiEventRepository({
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

  CrewRole _crewRole(Object? v) {
    for (final r in CrewRole.values) {
      if (r.name == v) return r;
    }
    return CrewRole.crew;
  }

  EventSize _size(Object? v) {
    for (final s in EventSize.values) {
      if (s.name == v) return s;
    }
    return EventSize.small;
  }

  CrewMember _member(Map<String, dynamic> m) => CrewMember(
        username: (m['username'] ?? '').toString(),
        fullName: (m['fullName'] ?? '').toString(),
        role: _crewRole(m['role']),
        note: (m['note'] ?? '').toString(),
        joinedAt: apiDateTime(m['joinedAt']),
      );

  EventItem _item(Map<String, dynamic> m) {
    final cat = _map(m['category']);
    final ent = m['entity'] == null ? null : _map(m['entity']);
    return EventItem(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      company: (m['company'] ?? '').toString(),
      category: EventCategory(
        id: (cat['id'] ?? '').toString(),
        name: (cat['name'] ?? '').toString(),
      ),
      entity: ent == null
          ? null
          : EventEntity(
              id: (ent['id'] ?? '').toString(),
              name: (ent['name'] ?? '').toString(),
              active: (ent['active'] as bool?) ?? true,
            ),
      startDate: apiDateTime(m['startDate']),
      endDate: apiDateTime(m['endDate']),
      location: (m['location'] ?? '').toString(),
      size: _size(m['size']),
      createdBy: (m['createdBy'] ?? '').toString(),
      crew: [
        for (final e in (m['crew'] as List? ?? [])) _member(_map(e)),
      ],
      poValue: (m['poValue'] as num?)?.toInt(),
    );
  }

  EventThresholds _thr(Map<String, dynamic> m) => EventThresholds(
        smallMax: (m['smallMax'] as num?)?.toInt() ?? 0,
        mediumMax: (m['mediumMax'] as num?)?.toInt() ?? 0,
        largeMax: (m['largeMax'] as num?)?.toInt() ?? 0,
      );

  @override
  Future<EventThresholds> fetchThresholds() async {
    final res = await _client.get(
      Uri.parse('$_base/events/thresholds'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    return _thr(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<EventThresholds> updateThresholds(
    AuthUser actor,
    EventThresholds thresholds,
  ) async {
    final res = await _client.put(
      Uri.parse('$_base/events/thresholds'),
      headers: await _h(),
      body: jsonEncode({
        'smallMax': thresholds.smallMax,
        'mediumMax': thresholds.mediumMax,
        'largeMax': thresholds.largeMax,
      }),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    return _thr(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<List<EventCategory>> fetchCategories(AuthUser viewer) async {
    final res = await _client.get(
      Uri.parse('$_base/events/categories'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<EventCategory>.unmodifiable(
      [
        for (final e in (m['categories'] as List? ?? []))
          EventCategory(
            id: (_map(e)['id'] ?? '').toString(),
            name: (_map(e)['name'] ?? '').toString(),
          ),
      ],
    );
  }

  @override
  Future<EventCategory> saveCategory(
    AuthUser actor, {
    String? id,
    required String name,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/events/categories'),
      headers: await _h(),
      body: jsonEncode({'id': id, 'name': name}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    _ping();
    return EventCategory(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
    );
  }

  @override
  Future<void> deleteCategory(AuthUser actor, {required String id}) async {
    final res = await _client.delete(
      Uri.parse('$_base/events/categories/$id'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
  }

  @override
  Future<List<EventEntity>> fetchEntities(AuthUser viewer) async {
    final res = await _client.get(
      Uri.parse('$_base/events/entities'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<EventEntity>.unmodifiable(
      [
        for (final e in (m['entities'] as List? ?? []))
          EventEntity(
            id: (_map(e)['id'] ?? '').toString(),
            name: (_map(e)['name'] ?? '').toString(),
            active: (_map(e)['active'] as bool?) ?? true,
          ),
      ],
    );
  }

  @override
  Future<EventEntity> createEntity(
    AuthUser actor, {
    required String name,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/events/entities'),
      headers: await _h(),
      body: jsonEncode({'name': name}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    _ping();
    return EventEntity(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      active: (m['active'] as bool?) ?? true,
    );
  }

  @override
  Future<EventEntity> updateEntity(
    AuthUser actor, {
    required String id,
    required String name,
    required bool active,
  }) async {
    final res = await _client.patch(
      Uri.parse('$_base/events/entities/$id'),
      headers: await _h(),
      body: jsonEncode({'name': name, 'active': active}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    _ping();
    return EventEntity(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      active: (m['active'] as bool?) ?? true,
    );
  }

  @override
  Future<void> deleteEntity(AuthUser actor, {required String id}) async {
    final res = await _client.delete(
      Uri.parse('$_base/events/entities/$id'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
  }

  @override
  Future<List<EventItem>> fetchEvents(AuthUser viewer) async {
    final res = await _client.get(
      Uri.parse('$_base/events'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<EventItem>.unmodifiable(
      [for (final e in (m['events'] as List? ?? [])) _item(_map(e))],
    );
  }

  @override
  Future<EventItem> fetchEvent(AuthUser viewer, {required String id}) async {
    final res = await _client.get(
      Uri.parse('$_base/events/$id'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    return _item(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Map<String, dynamic> _write({
    required String name,
    required String company,
    required String categoryId,
    required String entityId,
    required DateTime startDate,
    required DateTime endDate,
    required String location,
    required int poValue,
  }) =>
      {
        'name': name,
        'company': company,
        'categoryId': categoryId,
        'entityId': entityId,
        'startDate': startDate.toIso8601String().substring(0, 10),
        'endDate': endDate.toIso8601String().substring(0, 10),
        'location': location,
        'poValue': poValue,
      };

  @override
  Future<EventItem> createEvent(
    AuthUser actor, {
    required String name,
    required String company,
    required String categoryId,
    required String entityId,
    required DateTime startDate,
    required DateTime endDate,
    required String location,
    required int poValue,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/events'),
      headers: await _h(),
      body: jsonEncode(_write(
        name: name,
        company: company,
        categoryId: categoryId,
        entityId: entityId,
        startDate: startDate,
        endDate: endDate,
        location: location,
        poValue: poValue,
      )),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    _ping();
    return _item(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<EventItem> updateEvent(
    AuthUser actor, {
    required String id,
    required String name,
    required String company,
    required String categoryId,
    required String entityId,
    required DateTime startDate,
    required DateTime endDate,
    required String location,
    required int poValue,
  }) async {
    final res = await _client.put(
      Uri.parse('$_base/events/$id'),
      headers: await _h(),
      body: jsonEncode(_write(
        name: name,
        company: company,
        categoryId: categoryId,
        entityId: entityId,
        startDate: startDate,
        endDate: endDate,
        location: location,
        poValue: poValue,
      )),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _item(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<void> deleteEvent(AuthUser actor, {required String id}) async {
    final res = await _client.delete(
      Uri.parse('$_base/events/$id'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
  }

  @override
  Future<EventItem> joinEvent(
    AuthUser user, {
    required String id,
    required CrewRole role,
    required String note,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/events/$id/join'),
      headers: await _h(),
      body: jsonEncode({'role': role.name, 'note': note}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _item(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<EventItem> leaveEvent(AuthUser user, {required String id}) async {
    final res = await _client.delete(
      Uri.parse('$_base/events/$id/leave'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _item(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
