import 'package:flutter/foundation.dart';

import 'auth_repository.dart';

/// Kontrak kelola karyawan (menu Karyawan).
///
/// Hak akses (WAJIB ditegakkan di server):
/// - SEMUA role dapat melihat daftar & detail karyawan, tetapi akun Super
///   Admin disembunyikan dari non-Super Admin (tidak muncul di daftar,
///   tidak bisa dibuka).
/// - Membuat / mengubah / menonaktifkan / mereset password: HANYA Super
///   Admin. Manager & Staff read-only.
/// - Akun nonaktif tidak bisa login dan sesinya dicabut.
abstract class EmployeeRepository {
  Listenable get changes;

  /// Semua akun (aktif & nonaktif), urut nama.
  Future<List<EmployeeAccount>> fetchEmployees(AuthUser actor);

  Future<EmployeeAccount> fetchEmployee(
    AuthUser actor, {
    required String username,
  });

  /// Membuat akun baru dengan password sementara yang dibuat server.
  Future<EmployeeCreated> createEmployee(
    AuthUser actor, {
    required String username,
    required EmployeeDraft draft,
  });

  /// Membuat banyak akun sekaligus dengan username & password acak.
  /// Hanya Super Admin. Password sementara hanya dikembalikan sekali
  /// (untuk dibagikan ke karyawan); akun wajib ganti password + lengkapi
  /// profil saat login pertama.
  /// Bila [accounts] diisi, membuat akun sesuai daftar baris
  /// `username:password:role` (password/role opsional). Bila [accounts]
  /// kosong, memakai [count] akun random.
  Future<List<EmployeeCredential>> createBulk(
    AuthUser actor, {
    int? count,
    List<BulkAccountSpec>? accounts,
    UserRole role = UserRole.staff,
    required Division division,
    required EmploymentStatus employmentStatus,
    int? contractMonths,
  });

  Future<EmployeeAccount> updateEmployee(
    AuthUser actor, {
    required String username,
    required EmployeeDraft draft,
  });

  Future<EmployeeAccount> setActive(
    AuthUser actor, {
    required String username,
    required bool active,
  });

  Future<void> deleteEmployee(
    AuthUser actor, {
    required String username,
  });

  /// Mengganti password dengan password sementara baru (ditampilkan sekali
  /// ke Manager untuk diserahkan ke karyawan).
  Future<String> resetPassword(AuthUser actor, {required String username});
}

/// Status kepegawaian memakai enum [EmploymentStatus] (di registration.dart,
/// diekspor lewat auth_repository) + durasi [contractMonths].
/// Data akun karyawan untuk menu Karyawan.
class EmployeeAccount {
  const EmployeeAccount({
    required this.username,
    required this.fullName,
    required this.role,
    required this.employeeId,
    required this.position,
    required this.division,
    required this.employmentStatus,
    required this.joinDate,
    required this.email,
    required this.phone,
    required this.nikMasked,
    required this.active,
    required this.canEdit,
    required this.canChangeRole,
    required this.canChangeStatus,
    required this.canResetPassword,
    this.nik,
    this.managerUsername,
    this.managerName,
    this.gender,
    this.birthPlace,
    this.birthDate,
    this.address,
    this.emergencyContact,
    this.contractMonths,
    this.photoUrl,
  });

  final String username;
  final String fullName;
  final UserRole role;
  final String employeeId;
  final String position;

  /// Divisi tempat karyawan bekerja — satu-satunya taksonomi unit kerja
  /// (tidak ada "departemen" teks bebas agar laporan konsisten).
  final Division division;
  final EmploymentStatus employmentStatus;

  /// Durasi (bulan) untuk status yang membutuhkannya; null untuk External
  /// Relations atau akun lama.
  final int? contractMonths;
  final DateTime joinDate;
  final String email;
  final String phone;
  final String nikMasked;

  /// NIK lengkap — hanya dikirim server bila [canEdit] (dibutuhkan formulir).
  final String? nik;
  final String? managerUsername;
  final String? managerName;
  final bool active;

  /// Data pribadi (dari pendaftaran / diperbarui karyawan sendiri).
  /// null = belum diisi.
  final Gender? gender;

  /// Tempat & tanggal lahir — seperti NIK lengkap, hanya dikirim server
  /// bila [canEdit]. Lihat [hasPrivateData].
  final String? birthPlace;
  final DateTime? birthDate;

  /// Alamat & kontak darurat — seperti NIK lengkap, hanya dikirim server
  /// bila [canEdit]. Lihat [hasPrivateData].
  final String? address;
  final EmergencyContact? emergencyContact;

  /// Apakah peminta berhak melihat alamat & kontak darurat.
  bool get hasPrivateData => canEdit;

  // Hak peminta terhadap akun ini (dihitung server).
  final bool canEdit;
  final bool canChangeRole;
  final bool canChangeStatus;
  final bool canResetPassword;

  /// URL foto profil (S3 publik / presigned). null = avatar inisial.
  final String? photoUrl;
}

/// Isi formulir tambah / ubah karyawan. Username tidak bisa diubah.
class EmployeeDraft {
  const EmployeeDraft({
    required this.fullName,
    required this.role,
    required this.nik,
    required this.employeeId,
    required this.position,
    required this.division,
    required this.employmentStatus,
    this.contractMonths,
    required this.joinDate,
    required this.email,
    required this.phone,
    this.managerUsername,
    this.gender,
    this.address,
    this.emergencyContact,
  });

  final String fullName;
  final UserRole role;
  final String nik;
  final String employeeId;
  final String position;
  final Division division;
  final EmploymentStatus employmentStatus;
  final int? contractMonths;
  final DateTime joinDate;
  final String email;
  final String phone;
  final String? managerUsername;

  /// Data pribadi (opsional). null = kosong / dihapus.
  final Gender? gender;
  final String? address;
  final EmergencyContact? emergencyContact;
}

class EmployeeCreated {
  const EmployeeCreated({
    required this.account,
    required this.temporaryPassword,
  });

  final EmployeeAccount account;
  final String temporaryPassword;
}

/// Spesifikasi akun tunggal dalam bulk (username wajib; password/role opsional).
class BulkAccountSpec {
  const BulkAccountSpec({
    required this.username,
    this.password,
    this.role,
  });

  final String username;
  final String? password;
  final UserRole? role;
}

/// Kredensial akun massal (tampilkan SEKALI ke Super Admin untuk dibagikan).
class EmployeeCredential {
  const EmployeeCredential({
    required this.username,
    required this.temporaryPassword,
  });

  final String username;
  final String temporaryPassword;
}

/// Aturan validasi yang sama dipakai di formulir; server menegakkan ulang.
abstract final class EmployeeRules {
  static final RegExp username = RegExp(r'^[a-z][a-z0-9._]{2,29}$');
  static final RegExp nik = RegExp(r'^\d{16}$');
  static final RegExp email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp phone = RegExp(r'^\+?[\d\s-]{9,20}$');

  static String? validateUsername(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Username wajib diisi';
    if (!username.hasMatch(v)) {
      return '3–30 karakter: huruf kecil, angka, titik, atau garis bawah; '
          'diawali huruf';
    }
    return null;
  }

  static String? validateFullName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Nama lengkap wajib diisi';
    if (v.length < 3) return 'Minimal 3 karakter';
    return null;
  }

  static String? validateNik(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'NIK wajib diisi';
    if (!nik.hasMatch(v)) {
      return 'NIK harus 16 digit angka (saat ini ${v.length} digit)';
    }
    return null;
  }

  static String? validateEmployeeId(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'ID karyawan wajib diisi';
    if (v.length > 20) return 'Maksimal 20 karakter';
    return null;
  }

  static String? validateRequired(String? value, String label) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return '$label wajib diisi';
    if (v.length < 2) return 'Minimal 2 karakter';
    return null;
  }

  static String? validateEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email wajib diisi';
    if (!email.hasMatch(v)) return 'Format email tidak valid';
    return null;
  }

  static String? validatePhone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Nomor telepon wajib diisi';
    final digits = v.replaceAll(RegExp(r'\D'), '').length;
    if (!phone.hasMatch(v) || digits < 9 || digits > 13) {
      return 'Nomor telepon 9–13 digit, mis. 0812-3456-7890';
    }
    return null;
  }
}
