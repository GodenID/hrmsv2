import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/utils/work_calendar.dart';
import '../auth_repository.dart';
import '../employee_repository.dart';
import 'mock_store.dart';

/// Kelola karyawan palsu. Aturan hak akses & validasi di sini meniru yang
/// WAJIB ditegakkan server (lihat [EmployeeRepository]).
class MockEmployeeRepository implements EmployeeRepository {
  MockEmployeeRepository(
    this.store, {
    this.latency = const Duration(milliseconds: 500),
  });

  final MockStore store;
  final Duration latency;

  static final Random _random = Random.secure();

  @override
  Listenable get changes => store.employeeChanges;

  // ---------------------------------------------------------------------------
  // Bantuan
  // ---------------------------------------------------------------------------

  void _requireSuperAdmin(AuthUser actor) {
    if (actor.role != UserRole.superadmin) {
      throw const PermissionDeniedException(
        'Hanya Super Admin yang dapat mengelola data karyawan.',
      );
    }
  }

  MockAccount _find(String username) {
    final a = store.account(username);
    if (a == null) {
      throw const AppException('Karyawan tidak ditemukan.');
    }
    return a;
  }

  /// Akun Super Admin disembunyikan dari non-Super Admin.
  bool _hiddenFrom(AuthUser actor, MockAccount a) =>
      a.role == UserRole.superadmin && actor.role != UserRole.superadmin;

  static String _maskNik(String nik) {
    if (nik.length != 16) return '•••• •••• •••• ••••';
    return '${nik.substring(0, 4)} •••• •••• ${nik.substring(12)}';
  }

  EmployeeAccount _toAccount(AuthUser actor, MockAccount a) {
    final isSuper = actor.role == UserRole.superadmin;
    final canEdit = isSuper && actor.role.canManageRole(a.role);
    final canActOn = isSuper && store.canActOn(actor, a);
    final manager = a.managerUsername == null
        ? null
        : store.account(a.managerUsername!);
    return EmployeeAccount(
      username: a.username,
      fullName: a.fullName,
      role: a.role,
      employeeId: a.employeeId,
      position: a.position,
      division: a.division,
      employmentStatus: a.employmentStatus,
      contractMonths: a.contractMonths,
      joinDate: a.joinDate,
      email: a.email,
      phone: a.phone,
      nikMasked: _maskNik(a.nik),
      // NIK lengkap hanya untuk yang berhak mengubah data.
      nik: canEdit ? a.nik : null,
      managerUsername: a.managerUsername,
      managerName: manager?.fullName,
      gender: a.gender,
      // Data pribadi mengikuti aturan NIK lengkap.
      birthPlace: canEdit ? a.birthPlace : null,
      birthDate: canEdit ? a.birthDate : null,
      address: canEdit ? a.address : null,
      emergencyContact: canEdit ? a.emergencyContact : null,
      active: a.active,
      canEdit: canEdit,
      canChangeRole: canEdit && a.username != actor.username,
      canChangeStatus: canActOn,
      canResetPassword: canActOn && a.active,
      // Mock tidak menyimpan foto (lihat ApiEmployeeRepository untuk S3).
      photoUrl: null,
    );
  }

  /// Password sementara yang memenuhi aturan kekuatan password.
  static String _temporaryPassword() {
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lower = 'abcdefghijkmnpqrstuvwxyz';
    const digits = '23456789';
    const all = upper + lower + digits;
    String pick(String set) => set[_random.nextInt(set.length)];
    final chars = [
      pick(upper),
      pick(lower),
      pick(digits),
      for (var i = 0; i < 7; i++) pick(all),
    ]..shuffle(_random);
    return '${chars.sublist(0, 5).join()}-${chars.sublist(5).join()}';
  }

  void _check(String? error) {
    if (error != null) throw AppException(error);
  }

  void _validate(
    AuthUser actor,
    String username,
    EmployeeDraft d, {
    MockAccount? existing,
  }) {
    _requireSuperAdmin(actor);
    _check(EmployeeRules.validateFullName(d.fullName));
    _check(EmployeeRules.validateNik(d.nik));
    _check(EmployeeRules.validateEmployeeId(d.employeeId));
    _check(EmployeeRules.validateRequired(d.position, 'Jabatan'));
    // Divisi & status berupa enum wajib (non-null) — yang divalidasi
    // hanya durasinya.
    _check(
      RegistrationRules.validateContractMonths(
        d.contractMonths?.toString(),
        d.employmentStatus,
      ),
    );
    _check(EmployeeRules.validateEmail(d.email));
    _check(EmployeeRules.validatePhone(d.phone));
    final address = d.address?.trim() ?? '';
    if (address.isNotEmpty) _check(RegistrationRules.validateAddress(address));
    final ec = d.emergencyContact;
    if (ec != null) {
      _check(RegistrationRules.validateEmergencyName(ec.name));
      _check(EmployeeRules.validatePhone(ec.phone));
      _check(RegistrationRules.emergencyPhoneConflict(ec.phone, d.phone));
    }
    if (!EmploymentStatus.values.contains(d.employmentStatus)) {
      throw const AppException('Status kepegawaian tidak dikenal.');
    }

    if (!actor.role.canManageRole(d.role)) {
      throw PermissionDeniedException(
        'Anda tidak berhak memberikan role ${d.role.label}.',
      );
    }
    if (existing != null &&
        existing.username == actor.username &&
        d.role != existing.role) {
      throw const PermissionDeniedException(
        'Anda tidak dapat mengganti role akun Anda sendiri.',
      );
    }

    final today = WorkCalendar.dateOnly(store.now());
    final join = WorkCalendar.dateOnly(d.joinDate);
    if (join.isAfter(today.add(const Duration(days: 90)))) {
      throw const AppException(
        'Tanggal bergabung paling jauh 90 hari ke depan.',
      );
    }
    if (join.year < 1970) {
      throw const AppException('Tanggal bergabung tidak valid.');
    }

    for (final other in store.accounts.values) {
      if (other.username == username) continue;
      if (other.nik == d.nik.trim()) {
        throw AppException('NIK sudah terdaftar atas nama ${other.fullName}.');
      }
      if (other.employeeId.toLowerCase() == d.employeeId.trim().toLowerCase()) {
        throw AppException('ID karyawan sudah dipakai oleh ${other.fullName}.');
      }
      if (other.email.toLowerCase() == d.email.trim().toLowerCase()) {
        throw AppException('Email sudah dipakai oleh ${other.fullName}.');
      }
    }

    final managerUsername = d.managerUsername;
    if (managerUsername != null) {
      if (managerUsername == username) {
        throw const AppException(
          'Karyawan tidak bisa menjadi atasan dirinya sendiri.',
        );
      }
      final manager = store.account(managerUsername);
      if (manager == null || !manager.active) {
        throw const AppException('Atasan harus karyawan yang masih aktif.');
      }
      // Cegah rantai atasan berputar (A -> B -> A).
      final seen = <String>{username};
      MockAccount? cursor = manager;
      while (cursor != null) {
        if (!seen.add(cursor.username)) {
          throw const AppException(
            'Atasan tidak valid: membentuk rantai atasan yang berputar.',
          );
        }
        final next = cursor.managerUsername;
        cursor = next == null ? null : store.account(next);
      }
    }
  }

  void _apply(MockAccount a, EmployeeDraft d) {
    a
      ..fullName = d.fullName.trim()
      ..role = d.role
      ..nik = d.nik.trim()
      ..employeeId = d.employeeId.trim()
      ..position = d.position.trim()
      ..division = d.division
      ..employmentStatus = d.employmentStatus
      ..contractMonths = d.contractMonths
      ..joinDate = WorkCalendar.dateOnly(d.joinDate)
      ..email = d.email.trim().toLowerCase()
      ..phone = d.phone.trim()
      ..managerUsername = d.managerUsername
      ..gender = d.gender
      ..address = (d.address?.trim().isEmpty ?? true) ? null : d.address!.trim()
      ..emergencyContact = d.emergencyContact == null
          ? null
          : EmergencyContact(
              name: d.emergencyContact!.name.trim(),
              relation: d.emergencyContact!.relation,
              phone: d.emergencyContact!.phone.trim(),
            );
  }

  // ---------------------------------------------------------------------------
  // API
  // ---------------------------------------------------------------------------

  @override
  Future<List<EmployeeAccount>> fetchEmployees(AuthUser actor) async {
    await Future<void>.delayed(latency);
    final sorted = [...store.accounts.values]
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    return List.unmodifiable([
      for (final a in sorted)
        if (!_hiddenFrom(actor, a)) _toAccount(actor, a),
    ]);
  }

  @override
  Future<EmployeeAccount> fetchEmployee(
    AuthUser actor, {
    required String username,
  }) async {
    await Future<void>.delayed(latency);
    final a = _find(username);
    if (_hiddenFrom(actor, a)) {
      throw const AppException('Karyawan tidak ditemukan.');
    }
    return _toAccount(actor, a);
  }

  @override
  Future<EmployeeCreated> createEmployee(
    AuthUser actor, {
    required String username,
    required EmployeeDraft draft,
  }) async {
    await Future<void>.delayed(latency);
    _requireSuperAdmin(actor);
    final name = username.trim().toLowerCase();
    _check(EmployeeRules.validateUsername(name));
    if (store.account(name) != null) {
      throw const AppException(
        'Username sudah dipakai (termasuk akun nonaktif). Pilih yang lain.',
      );
    }
    _validate(actor, name, draft);

    final password = _temporaryPassword();
    final account = MockAccount(
      username: name,
      fullName: '',
      role: draft.role,
      nik: '',
      employeeId: '',
      position: '',
      division: draft.division,
      employmentStatus: draft.employmentStatus,
      joinDate: draft.joinDate,
      email: '',
      phone: '',
      password: password,
    );
    _apply(account, draft);
    store.accounts[name] = account;
    store.employeeChanges.ping();
    return EmployeeCreated(
      account: _toAccount(actor, account),
      temporaryPassword: password,
    );
  }

  @override
  Future<EmployeeAccount> updateEmployee(
    AuthUser actor, {
    required String username,
    required EmployeeDraft draft,
  }) async {
    await Future<void>.delayed(latency);
    _requireSuperAdmin(actor);
    final a = _find(username);
    if (!actor.role.canManageRole(a.role)) {
      throw PermissionDeniedException(
        '${actor.role.label} tidak dapat mengubah data akun ${a.role.label}.',
      );
    }
    _validate(actor, a.username, draft, existing: a);
    _apply(a, draft);
    store.employeeChanges.ping();
    return _toAccount(actor, a);
  }

  @override
  Future<EmployeeAccount> setActive(
    AuthUser actor, {
    required String username,
    required bool active,
  }) async {
    await Future<void>.delayed(latency);
    _requireSuperAdmin(actor);
    final a = _find(username);
    if (a.username == actor.username) {
      throw const PermissionDeniedException(
        'Anda tidak dapat menonaktifkan akun Anda sendiri.',
      );
    }
    if (!store.canActOn(actor, a)) {
      throw PermissionDeniedException(
        '${actor.role.label} tidak dapat mengubah status akun ${a.role.label}.',
      );
    }
    if (a.active != active) {
      // Server sungguhan juga WAJIB mencabut semua sesi akun ini.
      a.active = active;
      store.employeeChanges.ping();
    }
    return _toAccount(actor, a);
  }

  @override
  Future<String> resetPassword(
    AuthUser actor, {
    required String username,
  }) async {
    await Future<void>.delayed(latency);
    _requireSuperAdmin(actor);
    final a = _find(username);
    if (a.username == actor.username) {
      throw const PermissionDeniedException(
        'Untuk akun Anda sendiri, gunakan Profil > Ganti password.',
      );
    }
    if (!store.canActOn(actor, a)) {
      throw PermissionDeniedException(
        '${actor.role.label} tidak dapat mereset password akun '
        '${a.role.label}.',
      );
    }
    if (!a.active) {
      throw const AppException('Akun nonaktif. Aktifkan akun terlebih dahulu.');
    }
    final password = _temporaryPassword();
    // Server sungguhan juga WAJIB mencabut semua sesi akun ini.
    a.password = password;
    return password;
  }

  @override
  Future<bool> setRegistrationOpen(AuthUser actor, {required bool open}) async {
    await Future<void>.delayed(latency);
    if (!actor.role.canManageRegistration) {
      throw const PermissionDeniedException(
        'Hanya Super Admin yang dapat membuka atau menutup pendaftaran.',
      );
    }
    if (store.registrationOpen != open) {
      store.registrationOpen = open;
      store.employeeChanges.ping();
    }
    return store.registrationOpen;
  }
}
