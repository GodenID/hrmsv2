import 'dart:typed_data';

import '../../core/utils/validators.dart';
import '../../core/utils/work_calendar.dart';
import '../auth_repository.dart';
import '../employee_repository.dart';
import '../profile_repository.dart';
import 'mock_store.dart';

class MockProfileRepository implements ProfileRepository {
  MockProfileRepository(
    this.store, {
    this.latency = const Duration(milliseconds: 500),
  });

  final MockStore store;
  final Duration latency;

  MockAccount _account(AuthUser user) {
    final account = store.account(user.username);
    if (account == null) {
      throw const AppException('Akun tidak ditemukan. Silakan masuk ulang.');
    }
    return account;
  }

  static String _maskNik(String nik) {
    if (nik.length != 16) return '•••• •••• •••• ••••';
    return '${nik.substring(0, 4)} •••• •••• ${nik.substring(12)}';
  }

  @override
  Future<EmployeeProfile> fetchProfile(AuthUser user) async {
    await Future<void>.delayed(latency);
    return _toProfile(_account(user));
  }

  /// Batas ukuran unggahan foto (hasil editor ~100–400 KB).
  static const int maxPhotoBytes = 2 * 1024 * 1024;

  /// Hanya PNG / JPEG yang diterima (dicek dari tanda tangan file,
  /// bukan dari nama file).
  static bool _isPngOrJpeg(Uint8List b) {
    if (b.length >= 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return true;
    }
    return b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
  }

  @override
  Future<Uint8List?> fetchPhoto(AuthUser user) async {
    await Future<void>.delayed(latency);
    return _account(user).photo;
  }

  @override
  Future<void> updatePhoto(AuthUser user, {required Uint8List bytes}) async {
    await Future<void>.delayed(latency);
    final a = _account(user);
    if (!a.active) {
      throw const AuthException('Akun Anda sudah dinonaktifkan.');
    }
    if (bytes.length > maxPhotoBytes) {
      throw const AppException('Ukuran foto terlalu besar (maks. 2 MB).');
    }
    if (!_isPngOrJpeg(bytes)) {
      throw const AppException('Foto harus berformat PNG atau JPG.');
    }
    a.photo = Uint8List.fromList(bytes);
  }

  @override
  Future<void> removePhoto(AuthUser user) async {
    await Future<void>.delayed(latency);
    final a = _account(user);
    if (!a.active) {
      throw const AuthException('Akun Anda sudah dinonaktifkan.');
    }
    a.photo = null;
  }

  EmployeeProfile _toProfile(MockAccount a) {
    final manager = a.managerUsername == null
        ? null
        : store.account(a.managerUsername!);
    return EmployeeProfile(
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
      managerName: manager?.fullName,
      gender: a.gender,
      birthPlace: a.birthPlace,
      birthDate: a.birthDate,
      address: a.address,
      emergencyContact: a.emergencyContact,
    );
  }

  static void _check(String? error) {
    if (error != null) throw AppException(error);
  }

  @override
  Future<EmployeeProfile> updateContactInfo(
    AuthUser user, {
    required ContactInfoDraft draft,
  }) async {
    await Future<void>.delayed(latency);
    final a = _account(user);
    if (!a.active) {
      throw const AuthException('Akun Anda sudah dinonaktifkan.');
    }
    final phone = draft.phone.trim();
    final ec = draft.emergencyContact;
    _check(EmployeeRules.validatePhone(phone));
    _check(RegistrationRules.validateAddress(draft.address));
    _check(RegistrationRules.validateEmergencyName(ec.name));
    _check(EmployeeRules.validatePhone(ec.phone));
    _check(RegistrationRules.emergencyPhoneConflict(ec.phone, phone));

    a
      ..phone = phone
      ..address = draft.address.trim()
      ..emergencyContact = EmergencyContact(
        name: ec.name.trim(),
        relation: ec.relation,
        phone: ec.phone.trim(),
      );
    // Menu Karyawan (Manager/HR) ikut menampilkan data terbaru.
    store.employeeChanges.ping();
    return _toProfile(a);
  }

  @override
  Future<EmployeeProfile> completeProfile(
    AuthUser user, {
    required ProfileCompletionDraft draft,
  }) async {
    await Future<void>.delayed(latency);
    final a = _account(user);
    if (!a.active) {
      throw const AuthException('Akun Anda sudah dinonaktifkan.');
    }
    _check(EmployeeRules.validateFullName(draft.fullName));
    _check(EmployeeRules.validateNik(draft.nik));
    _check(RegistrationRules.validateBirthPlace(draft.birthPlace));
    _check(
      RegistrationRules.validateBirthDate(draft.birthDate, now: store.now()),
    );
    _check(
      RegistrationRules.validateAddress(draft.address),
    );
    _check(EmployeeRules.validateEmail(draft.email));
    _check(EmployeeRules.validatePhone(draft.phone));
    final ec = draft.emergencyContact;
    _check(RegistrationRules.validateEmergencyName(ec.name));
    _check(EmployeeRules.validatePhone(ec.phone));
    _check(RegistrationRules.emergencyPhoneConflict(ec.phone, draft.phone));
    final nik = draft.nik.trim();
    final email = draft.email.trim().toLowerCase();
    final phoneCanon = PhoneNumbers.canonical(draft.phone.trim());
    for (final other in store.accounts.values) {
      if (other.username == a.username) continue;
      if (other.nik == nik) {
        throw const AppException('NIK ini sudah dipakai akun lain.');
      }
      if (other.email.toLowerCase() == email) {
        throw const AppException('Email ini sudah dipakai akun lain.');
      }
      if (phoneCanon.isNotEmpty &&
          PhoneNumbers.canonical(other.phone) == phoneCanon) {
        throw const AppException('Nomor HP ini sudah dipakai akun lain.');
      }
    }
    a
      ..fullName = draft.fullName.trim()
      ..nik = nik
      ..birthPlace = draft.birthPlace.trim()
      ..birthDate = WorkCalendar.dateOnly(draft.birthDate)
      ..gender = draft.gender
      ..address = draft.address.trim()
      ..email = email
      ..phone = draft.phone.trim()
      ..emergencyContact = EmergencyContact(
        name: ec.name.trim(),
        relation: ec.relation,
        phone: ec.phone.trim(),
      )
      ..profileComplete = true;
    store.employeeChanges.ping();
    return _toProfile(a);
  }

  @override
  Future<void> changePassword(
    AuthUser user, {
    required String currentPassword,
    required String newPassword,
  }) async {
    await Future<void>.delayed(latency);
    final a = _account(user);
    if (a.password != currentPassword) {
      throw const AppException('Password saat ini salah.');
    }
    if (!(passwordStrength(newPassword, username: a.username) >=
        Validators.minimumPasswordStrength)) {
      throw const AppException(
        'Password terlalu lemah. Buat password yang lebih kuat.',
      );
    }
    if (newPassword == currentPassword) {
      throw const AppException(
        'Password baru tidak boleh sama dengan password saat ini.',
      );
    }
    a.password = newPassword;
    a.mustChangePassword = false;
  }
}
