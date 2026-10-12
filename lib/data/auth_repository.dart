import 'app_exception.dart';
import 'registration.dart';

export 'app_exception.dart';
export 'registration.dart';

/// Kontrak autentikasi. Implementasi saat ini hanya mock (frontend saja);
/// nanti cukup buat `ApiAuthRepository implements AuthRepository`
/// tanpa mengubah halaman.
abstract class AuthRepository {
  /// Mengembalikan sesi berisi token yang disimpan aplikasi agar pengguna
  /// tetap masuk setelah aplikasi dibuka ulang / web di-refresh.
  ///
  /// Pesan galat dibedakan: username tak dikenal → "tidak ditemukan",
  /// password salah → "password salah" (keputusan produk: kejelasan bagi
  /// pengguna didahulukan; akibatnya keberadaan suatu akun memang bisa
  /// ditebak dari pesan ini). Server WAJIB membatasi laju: 5x gagal
  /// beruntun untuk satu username mengunci login selama 15 menit. Pesan
  /// galat menyebut sisa waktu tunggu; login yang berhasil menghapus
  /// hitungan gagal.
  Future<AuthSession> login({
    required String username,
    required String password,
  });

  /// Memulihkan sesi dari token tersimpan. Melempar [AuthException] bila
  /// token tidak valid, kedaluwarsa (umur sesi 30 hari sejak login), atau
  /// akun sudah dinonaktifkan.
  Future<AuthUser> restoreSession(String token);

  /// Mencabut token di server. Aplikasi tetap menghapus token lokal
  /// walaupun panggilan ini gagal.
  Future<void> logout(String token);

  /// Mencabut SEMUA sesi milik [user] kecuali [currentToken] (mis. "keluar
  /// dari semua perangkat lain"). Server WAJIB mencatat semua token yang
  /// diterbitkannya agar bisa mencabut yang lain.
  Future<void> logoutOthers(AuthUser user, {required String currentToken});

  /// Langkah 1 lupa password: memastikan username terdaftar.
  /// Server WAJIB membatasi laju (5x gagal → kunci 15 menit).
  Future<void> verifyUsername(String username);

  /// Langkah 2 lupa password: mencocokkan NIK KTP dengan username.
  /// Mengembalikan token reset yang wajib dipakai di langkah 3.
  /// Token hanya berlaku 30 menit dan sekali pakai; permintaan baru
  /// menggugurkan token sebelumnya milik akun yang sama.
  /// Server WAJIB membatasi laju (5x gagal → kunci 15 menit).
  Future<String> verifyNik({required String username, required String nik});

  /// Langkah 3 lupa password: menyimpan password baru. Token kedaluwarsa
  /// atau sudah dipakai melempar [AuthException] dan alur harus diulang
  /// dari langkah 1. Password baru wajib memenuhi kekuatan minimum yang
  /// sama dengan pendaftaran.
  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  });

  /// Apakah pendaftaran akun mandiri sedang dibuka (endpoint publik, tanpa
  /// login). Halaman masuk menyembunyikan tombol "Daftar akun" bila false.
  Future<bool> isRegistrationOpen();

  /// Pendaftaran langkah 1: memastikan username valid & belum dipakai.
  /// Melempar [RegistrationException] bila tidak tersedia atau pendaftaran
  /// sedang ditutup.
  Future<void> checkUsernameAvailable(String username);

  /// Membuat akun dari pendaftaran mandiri. Akun selalu ber-role
  /// [UserRole.staff]; perubahan role hanya oleh Super Admin.
  /// Melempar [RegistrationException] (dengan `field` bila diketahui)
  /// bila data ditolak, mis. NIK / email sudah terdaftar, atau pendaftaran
  /// sedang ditutup.
  Future<RegisteredAccount> register(RegistrationDraft draft);
}

/// Tiga role pengguna Prasasti Connect.
enum UserRole {
  staff('Staff'),
  manager('Manager'),
  superadmin('Super Admin');

  const UserRole(this.label);

  final String label;

  /// Hak kelola pengumuman (tambah/ubah/hapus) — hanya Super Admin.
  bool get canManageAnnouncements => this == UserRole.superadmin;

  /// Hak melihat siapa saja yang sudah/belum membaca pengumuman — semua
  /// role.
  bool get canViewAnnouncementReaders => true;

  /// Membuat, mengubah & menghapus event — Manager & Super Admin.
  bool get canManageEvents =>
      this == UserRole.manager || this == UserRole.superadmin;

  /// Mengatur ambang nilai PO (event kecil/sedang/besar) — Manager &
  /// Super Admin.
  bool get canManageEventThresholds =>
      this == UserRole.manager || this == UserRole.superadmin;

  /// Melihat nilai PO event (data keuangan).
  bool get canViewEventPo =>
      this == UserRole.manager || this == UserRole.superadmin;

  /// Menyetujui / menolak cuti & koreksi absensi karyawan lain.
  bool get canReviewRequests =>
      this == UserRole.manager || this == UserRole.superadmin;

  /// Membuka menu Karyawan (daftar, tambah, ubah, nonaktifkan, reset
  /// password).
  bool get canManageEmployees =>
      this == UserRole.manager || this == UserRole.superadmin;

  /// Membuka / menutup pendaftaran akun mandiri — hanya Super Admin.
  bool get canManageRegistration => this == UserRole.superadmin;

  /// Mengatur lokasi & radius absen — hanya Super Admin.
  bool get canManageAttendanceLocations => this == UserRole.superadmin;

  /// Apakah role ini boleh mengelola (dan memberikan) role [target].
  /// - Super Admin: semua role.
  /// - Manager: hanya Staff.
  /// Aturan yang sama dipakai untuk persetujuan cuti/koreksi.
  bool canManageRole(UserRole target) => switch (this) {
    UserRole.superadmin => true,
    UserRole.manager => target == UserRole.staff,
    UserRole.staff => false,
  };

  /// Role yang boleh dipilih saat membuat / mengubah akun.
  List<UserRole> get assignableRoles => [
    for (final r in UserRole.values)
      if (canManageRole(r)) r,
  ];
}

class AuthUser {
  const AuthUser({
    required this.username,
    required this.fullName,
    required this.role,
  });

  final String username;
  final String fullName;
  final UserRole role;

  /// Inisial untuk avatar, mis. "Budi Santoso" -> "BS".
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  /// Nama depan untuk sapaan.
  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;
}

/// Pengguna yang login + token sesinya.
class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final AuthUser user;
}

class AuthException extends AppException {
  const AuthException(super.message);
}
