import 'dart:typed_data';

import 'auth_repository.dart';

/// Kontrak profil karyawan yang sedang login.
abstract class ProfileRepository {
  Future<EmployeeProfile> fetchProfile(AuthUser user);

  /// Foto profil [user] (PNG / JPEG), null bila belum ada.
  Future<Uint8List?> fetchPhoto(AuthUser user);

  /// Menyimpan foto profil baru milik [user] sendiri. Foto sudah dipotong
  /// persegi & diperkecil di aplikasi (PNG 512 x 512).
  /// Server WAJIB memvalidasi ulang tipe & ukuran file.
  Future<void> updatePhoto(AuthUser user, {required Uint8List bytes});

  /// Menghapus foto profil [user]; avatar kembali ke inisial nama.
  Future<void> removePhoto(AuthUser user);

  /// Password baru wajib memenuhi kekuatan minimum yang sama dengan
  /// pendaftaran. Server WAJIB memvalidasi ulang.
  Future<void> changePassword(
    AuthUser user, {
    required String currentPassword,
    required String newPassword,
  });

  /// Karyawan memperbarui data kontaknya sendiri: nomor HP, alamat, dan
  /// kontak darurat. Data identitas & kepegawaian (nama, NIK, jenis
  /// kelamin, email, jabatan, divisi) tetap dikelola Tim HR.
  /// Server WAJIB memvalidasi ulang dan hanya mengubah akun [user] sendiri.
  Future<EmployeeProfile> updateContactInfo(
    AuthUser user, {
    required ContactInfoDraft draft,
  });

  /// Melengkapi data diri (login pertama akun bulk): nama, NIK, tempat &
  /// tanggal lahir, jenis kelamin, alamat, email, HP, kontak darurat.
  /// Menandai profil lengkap. Server WAJIB memvalidasi ulang termasuk
  /// keunikan NIK / email / HP terhadap akun lain.
  Future<EmployeeProfile> completeProfile(
    AuthUser user, {
    required ProfileCompletionDraft draft,
  });
}

/// Isi formulir "Ubah data kontak".
class ContactInfoDraft {
  const ContactInfoDraft({
    required this.phone,
    required this.address,
    required this.emergencyContact,
  });

  final String phone;
  final String address;
  final EmergencyContact emergencyContact;
}

/// Isi formulir "Lengkapi data diri" (login pertama akun bulk).
class ProfileCompletionDraft {
  const ProfileCompletionDraft({
    required this.fullName,
    required this.nik,
    required this.birthPlace,
    required this.birthDate,
    required this.gender,
    required this.address,
    required this.email,
    required this.phone,
    required this.emergencyContact,
  });

  final String fullName;
  final String nik;
  final String birthPlace;
  final DateTime birthDate;
  final Gender gender;
  final String address;
  final String email;
  final String phone;
  final EmergencyContact emergencyContact;
}

class EmployeeProfile {
  const EmployeeProfile({
    required this.username,
    required this.fullName,
    required this.role,
    required this.employeeId,
    required this.position,
    required this.division,
    required this.employmentStatus,
    this.contractMonths,
    required this.joinDate,
    required this.email,
    required this.phone,
    required this.nikMasked,
    this.managerName,
    this.gender,
    this.birthPlace,
    this.birthDate,
    this.address,
    this.emergencyContact,
  });

  final String username;
  final String fullName;
  final UserRole role;
  final String employeeId;
  final String position;
  final Division division;
  final EmploymentStatus employmentStatus;
  final int? contractMonths;
  final DateTime joinDate;
  final String email;
  final String phone;

  /// NIK sudah disamarkan oleh server, mis. "3201 •••• •••• 0001".
  /// NIK lengkap sebaiknya tidak pernah dikirim ke aplikasi.
  final String nikMasked;
  final String? managerName;

  /// null = belum diisi (mis. akun lama yang dibuat Manager).
  final Gender? gender;

  /// Tempat & tanggal lahir (null = belum diisi).
  final String? birthPlace;
  final DateTime? birthDate;

  final String? address;
  final EmergencyContact? emergencyContact;
}
