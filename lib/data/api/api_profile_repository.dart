import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/session_storage.dart';
import 'api_time.dart';
import '../auth_repository.dart';
import '../profile_repository.dart';
import 'api_upload_repository.dart';

/// [ProfileRepository] via REST. Foto via S3 presigned URL.
class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository({
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
    if (status == 401 || status == 403) throw AuthException(msg);
    throw AppException(msg);
  }

  T _enumOf<T extends Enum>(List<T> values, Object? raw, T fallback) {
    for (final v in values) {
      if (v.name == raw) return v;
    }
    return fallback;
  }

  EmployeeProfile _profile(Map<String, dynamic> m) {
    EmergencyContact? ec;
    if (m['emergencyContact'] is Map) {
      final e = Map<String, dynamic>.from(m['emergencyContact'] as Map);
      ec = EmergencyContact(
        name: (e['name'] ?? '').toString(),
        relation: _enumOf(
          EmergencyRelation.values,
          e['relation'],
          EmergencyRelation.other,
        ),
        phone: (e['phone'] ?? '').toString(),
      );
    }
    return EmployeeProfile(
      username: (m['username'] ?? '').toString(),
      fullName: (m['fullName'] ?? '').toString(),
      role: _enumOf(UserRole.values, m['role'], UserRole.staff),
      employeeId: (m['employeeId'] ?? '').toString(),
      position: (m['position'] ?? '').toString(),
      division: Division.fromJson(m['division'], m['divisionLabel']),
      employmentStatus: _enumOf(
        EmploymentStatus.values,
        m['employmentStatus'],
        EmploymentStatus.permanent,
      ),
      contractMonths: (m['contractMonths'] as num?)?.toInt(),
      joinDate: apiDateTime(m['joinDate']),
      email: (m['email'] ?? '').toString(),
      phone: (m['phone'] ?? '').toString(),
      nikMasked: (m['nikMasked'] ?? '').toString(),
      gender: m['gender'] == null ? null : _enumOf(Gender.values, m['gender'], Gender.male),
      birthPlace: m['birthPlace'] as String?,
      birthDate: apiDateTimeOpt(m['birthDate']),
      address: m['address'] as String?,
      emergencyContact: ec,
    );
  }

  ApiUploadRepository get _uploader => ApiUploadRepository(
        client: _client,
        baseUrl: _base,
        sessionStorage: _sessions,
      );

  @override
  Future<EmployeeProfile> fetchProfile(AuthUser user) async {
    final res = await _client.get(
      Uri.parse('$_base/profile'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    return _profile(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<Uint8List?> fetchPhoto(AuthUser user) async {
    final res = await _client.get(
      Uri.parse('$_base/profile/photo'),
      headers: await _h(),
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final url = (m['url'] ?? '').toString();
    if (url.isEmpty) return null;
    final img = await _client.get(Uri.parse(url));
    if (img.statusCode != 200) return null;
    return img.bodyBytes;
  }

  String _photoContentType(Uint8List bytes) =>
      bytes.length >= 8 &&
              bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4E &&
              bytes[3] == 0x47
          ? 'image/png'
          : 'image/jpeg';

  @override
  Future<void> updatePhoto(AuthUser user, {required Uint8List bytes}) async {
    final key = await _uploader.upload(
      purpose: 'avatar',
      filename: 'avatar.${_photoContentType(bytes) == 'image/png' ? 'png' : 'jpg'}',
      contentType: _photoContentType(bytes),
      bytes: bytes,
    );
    final res = await _client.put(
      Uri.parse('$_base/profile/photo'),
      headers: await _h(),
      body: jsonEncode({'key': key}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
  }

  @override
  Future<void> removePhoto(AuthUser user) async {
    final res = await _client.delete(
      Uri.parse('$_base/profile/photo'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
  }

  @override
  Future<void> changePassword(
    AuthUser user, {
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/profile/change-password'),
      headers: await _h(),
      body: jsonEncode({
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      }),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
  }

  @override
  Future<EmployeeProfile> updateContactInfo(
    AuthUser user, {
    required ContactInfoDraft draft,
  }) async {
    final res = await _client.put(
      Uri.parse('$_base/profile/contact'),
      headers: await _h(),
      body: jsonEncode({
        'phone': draft.phone,
        'address': draft.address,
        'emergencyName': draft.emergencyContact.name,
        'emergencyRelation': draft.emergencyContact.relation.name,
        'emergencyPhone': draft.emergencyContact.phone,
      }),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    return _profile(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<EmployeeProfile> completeProfile(
    AuthUser user, {
    required ProfileCompletionDraft draft,
  }) async {
    final res = await _client.put(
      Uri.parse('$_base/profile/complete'),
      headers: await _h(),
      body: jsonEncode({
        'fullName': draft.fullName,
        'nik': draft.nik,
        'birthPlace': draft.birthPlace,
        'birthDate': draft.birthDate.toIso8601String().substring(0, 10),
        'gender': draft.gender.name,
        'address': draft.address,
        'email': draft.email,
        'phone': draft.phone,
        'emergencyName': draft.emergencyContact.name,
        'emergencyRelation': draft.emergencyContact.relation.name,
        'emergencyPhone': draft.emergencyContact.phone,
      }),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    return _profile(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
