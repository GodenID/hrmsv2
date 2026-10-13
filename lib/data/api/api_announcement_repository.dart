import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/session_storage.dart';
import 'api_time.dart';
import '../announcement_repository.dart';
import '../auth_repository.dart';

/// [AnnouncementRepository] via REST.
class ApiAnnouncementRepository implements AnnouncementRepository {
  ApiAnnouncementRepository({
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
    String msg = 'Terjadi kesalahan. Coba lagi.';
    try {
      final m = jsonDecode(body);
      if (m is Map && m['message'] != null) msg = m['message'].toString();
    } catch (_) {}
    if (status == 401 || status == 403) throw PermissionDeniedException(msg);
    throw AppException(msg);
  }

  Map<String, dynamic> _map(Object? e) => Map<String, dynamic>.from(e as Map);

  EmployeeRef _ref(Map<String, dynamic> m) => EmployeeRef(
        username: (m['username'] ?? '').toString(),
        fullName: (m['fullName'] ?? '').toString(),
        photoUrl: m['photoUrl'] as String?,
      );

  Division _div(Object? v) {
    for (final d in Division.values) {
      if (d.name == v) return d;
    }
    return Division.hrIt;
  }

  AnnouncementAttachment _att(Map<String, dynamic> m) => AnnouncementAttachment(
        name: (m['name'] ?? '').toString(),
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        key: m['key'] as String?,
      );

  Announcement _ann(Map<String, dynamic> m) => Announcement(
        id: (m['id'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        body: (m['body'] ?? '').toString(),
        authorName: (m['authorName'] ?? '').toString(),
        publishedAt: apiDateTime(m['publishedAt']),
        updatedAt: apiDateTimeOpt(m['updatedAt']),
        expiresAt: apiDateTimeOpt(m['expiresAt']),
        pinned: (m['pinned'] as bool?) ?? false,
        targetDivisions: [
          for (final v in (m['targetDivisions'] as List? ?? [])) _div(v),
        ],
        attachments: [
          for (final v in (m['attachments'] as List? ?? [])) _att(_map(v)),
        ],
      );

  Map<String, dynamic> _draft(AnnouncementDraft d) => {
        'title': d.title,
        'body': d.body,
        'publishAt': d.publishAt?.toIso8601String(),
        'expiresAt': d.expiresAt?.toIso8601String(),
        'pinned': d.pinned,
        'targetDivisions': [for (final v in d.targetDivisions) v.name],
        'attachments': [
          for (final a in d.attachments)
            {'name': a.name, 'sizeBytes': a.sizeBytes, 'key': a.key},
        ],
      };

  @override
  Future<List<AnnouncementFeedItem>> fetchFeed(AuthUser viewer) async {
    final res = await _client.get(
      Uri.parse('$_base/announcements/feed'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return List<AnnouncementFeedItem>.unmodifiable(
      [
        for (final e in (m['feed'] as List? ?? []))
          AnnouncementFeedItem(
            announcement: _ann(_map(_map(e)['announcement'])),
            viewedByMe: (_map(e)['viewedByMe'] as bool?) ?? false,
            viewCount: (_map(e)['viewCount'] as num?)?.toInt() ?? 0,
          ),
      ],
    );
  }

  @override
  Future<Announcement> open({required AuthUser viewer, required String id}) async {
    final res = await _client.post(
      Uri.parse('$_base/announcements/$id/open'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    return _ann(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<AnnouncementReadReport> fetchReadReport({
    required AuthUser actor,
    required String id,
  }) async {
    final res = await _client.get(
      Uri.parse('$_base/announcements/$id/readers'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return AnnouncementReadReport(
      viewed: [
        for (final e in (m['viewed'] as List? ?? []))
          AnnouncementViewer(
            employee: _ref(_map(_map(e)['employee'])),
            viewedAt: apiDateTime(_map(e)['viewedAt']),
          ),
      ],
      notViewed: [
        for (final e in (m['notViewed'] as List? ?? [])) _ref(_map(e)),
      ],
    );
  }

  @override
  Future<Announcement> create({
    required AuthUser actor,
    required AnnouncementDraft draft,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/announcements'),
      headers: await _h(),
      body: jsonEncode(_draft(draft)),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    return _ann(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<Announcement> update({
    required AuthUser actor,
    required String id,
    required AnnouncementDraft draft,
  }) async {
    final res = await _client.put(
      Uri.parse('$_base/announcements/$id'),
      headers: await _h(),
      body: jsonEncode(_draft(draft)),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    return _ann(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<void> delete({required AuthUser actor, required String id}) async {
    final res = await _client.delete(
      Uri.parse('$_base/announcements/$id'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
  }
}
