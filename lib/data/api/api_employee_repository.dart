import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/session_storage.dart';
import '../auth_repository.dart';
import '../employee_repository.dart';

/// [EmployeeRepository] via REST. Token diambil dari [SessionStorage].
class ApiEmployeeRepository implements EmployeeRepository {
  ApiEmployeeRepository({
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

  EmployeeAccount _parse(Map<String, dynamic> m) {
    T enumOf<T extends Enum>(List<T> values, Object? raw, T fallback) {
      for (final v in values) {
        if (v.name == raw) return v;
      }
      return fallback;
    }

    EmergencyContact? ec;
    final ecm = m['emergencyContact'];
    if (ecm is Map) {
      ec = EmergencyContact(
        name: (ecm['name'] ?? '').toString(),
        relation: enumOf(
          EmergencyRelation.values,
          ecm['relation'],
          EmergencyRelation.other,
        ),
        phone: (ecm['phone'] ?? '').toString(),
      );
    }
    DateTime? dt(Object? v) {
      if (v == null || (v as String).isEmpty) return null;
      return DateTime.tryParse(v);
    }

    return EmployeeAccount(
      username: (m['username'] ?? '').toString(),
      fullName: (m['fullName'] ?? '').toString(),
      role: enumOf(UserRole.values, m['role'], UserRole.staff),
      employeeId: (m['employeeId'] ?? '').toString(),
      position: (m['position'] ?? '').toString(),
      division: enumOf(Division.values, m['division'], Division.hrIt),
      employmentStatus: enumOf(
        EmploymentStatus.values,
        m['employmentStatus'],
        EmploymentStatus.permanent,
      ),
      contractMonths: (m['contractMonths'] as num?)?.toInt(),
      joinDate: dt(m['joinDate']) ?? DateTime.now(),
      email: (m['email'] ?? '').toString(),
      phone: (m['phone'] ?? '').toString(),
      nikMasked: (m['nikMasked'] ?? '').toString(),
      active: (m['active'] as bool?) ?? true,
      canEdit: (m['canEdit'] as bool?) ?? false,
      canChangeRole: (m['canChangeRole'] as bool?) ?? false,
      canChangeStatus: (m['canChangeStatus'] as bool?) ?? false,
      canResetPassword: (m['canResetPassword'] as bool?) ?? false,
      nik: m['nik'] as String?,
      managerUsername: m['managerUsername'] as String?,
      gender: m['gender'] == null
          ? null
          : enumOf(Gender.values, m['gender'], Gender.male),
      birthPlace: m['birthPlace'] as String?,
      birthDate: dt(m['birthDate']),
      address: m['address'] as String?,
      emergencyContact: ec,
    );
  }

  Map<String, dynamic> _draft(EmployeeDraft d) => {
        'fullName': d.fullName,
        'role': d.role.name,
        'nik': d.nik,
        'employeeId': d.employeeId,
        'position': d.position,
        'division': d.division.name,
        'employmentStatus': d.employmentStatus.name,
        'contractMonths': d.contractMonths,
        'joinDate': d.joinDate.toIso8601String().substring(0, 10),
        'email': d.email,
        'phone': d.phone,
        'managerUsername': d.managerUsername,
        'gender': d.gender?.name,
        'address': d.address,
        'emergencyName': d.emergencyContact?.name,
        'emergencyRelation': d.emergencyContact?.relation.name,
        'emergencyPhone': d.emergencyContact?.phone,
      };

  @override
  Future<List<EmployeeAccount>> fetchEmployees(AuthUser actor) async {
    final res = await _client.get(
      Uri.parse('$_base/employees'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (m['employees'] as List? ?? []);
    return List.unmodifiable(
      list.map((e) => _parse(e as Map<String, dynamic>)),
    );
  }

  @override
  Future<EmployeeAccount> fetchEmployee(
    AuthUser actor, {
    required String username,
  }) async {
    final res = await _client.get(
      Uri.parse('$_base/employees/$username'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    return _parse(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<EmployeeCreated> createEmployee(
    AuthUser actor, {
    required String username,
    required EmployeeDraft draft,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/employees'),
      headers: await _h(),
      body: jsonEncode({'username': username, ..._draft(draft)}),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      _throw(res.body, res.statusCode);
    }
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    _ping();
    return EmployeeCreated(
      account: _parse(m['account'] as Map<String, dynamic>),
      temporaryPassword: (m['temporaryPassword'] ?? '').toString(),
    );
  }

  @override
  Future<EmployeeAccount> updateEmployee(
    AuthUser actor, {
    required String username,
    required EmployeeDraft draft,
  }) async {
    final res = await _client.put(
      Uri.parse('$_base/employees/$username'),
      headers: await _h(),
      body: jsonEncode(_draft(draft)),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _parse(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<EmployeeAccount> setActive(
    AuthUser actor, {
    required String username,
    required bool active,
  }) async {
    final res = await _client.patch(
      Uri.parse('$_base/employees/$username/active'),
      headers: await _h(),
      body: jsonEncode({'active': active}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    _ping();
    return _parse(jsonDecode(res.body) as Map<String, dynamic>);
  }

  @override
  Future<String> resetPassword(AuthUser actor, {required String username}) async {
    final res = await _client.post(
      Uri.parse('$_base/employees/$username/reset-password'),
      headers: await _h(),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (m['temporaryPassword'] ?? '').toString();
  }

  @override
  Future<bool> setRegistrationOpen(AuthUser actor, {required bool open}) async {
    final res = await _client.put(
      Uri.parse('$_base/settings/registration'),
      headers: await _h(),
      body: jsonEncode({'open': open}),
    );
    if (res.statusCode != 200) _throw(res.body, res.statusCode);
    final m = jsonDecode(res.body) as Map<String, dynamic>;
    return (m['open'] as bool?) ?? open;
  }
}
