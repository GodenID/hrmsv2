/// Referensi ringkas karyawan (untuk daftar "sudah/belum melihat").
class EmployeeRef {
  const EmployeeRef({required this.username, required this.fullName, this.photoUrl});

  final String username;
  final String fullName;

  /// URL foto profil (S3 publik / presigned). null = pakai inisial.
  final String? photoUrl;
}
