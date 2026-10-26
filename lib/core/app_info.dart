/// Identitas aplikasi di satu tempat.
abstract final class AppInfo {
  static const String appName = 'Prasasti Connect';
  static const String companyName = 'Prasasti Group';
  static const String version = '1.0.1';

  /// Nama aplikasi tidak ditulis di sini karena logo lengkap (yang sudah
  /// memuat tulisan "Prasasti Connect") selalu tampil di atas footer.
  static const String footer = '© 2026 $companyName  ·  v$version';

  /// Domain email karyawan (placeholder .example — ganti dengan domain
  /// perusahaan). Dipakai untuk mengisi otomatis email akun baru.
  static const String emailDomain = 'prasasti.example';
}
