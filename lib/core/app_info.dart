import 'package:package_info_plus/package_info_plus.dart';

/// Identitas aplikasi di satu tempat.
abstract final class AppInfo {
  static const String appName = 'Prasasti Connect';
  static const String companyName = 'Prasasti Group';

  /// Diisi dari paket terpasang saat aplikasi mulai. Kosong = belum terbaca.
  static String version = '';
  static String buildNumber = '';

  /// Versi yang tampil, mis. "1.0.7 (10)".
  static String get versionLabel =>
      buildNumber.isEmpty ? version : '$version ($buildNumber)';

  /// Nama aplikasi tidak ditulis di sini karena logo lengkap (yang sudah
  /// memuat tulisan "Prasasti Connect") selalu tampil di atas footer.
  static String get footer => version.isEmpty
      ? '© 2026 $companyName'
      : '© 2026 $companyName  ·  v$versionLabel';

  /// Dipanggil sekali saat startup supaya nomor versi sama dengan build
  /// yang benar-benar terpasang.
  static Future<void> load() async {
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = info.buildNumber;
    } catch (_) {
      // Info paket tidak tersedia (mis. lingkungan tes): footer tanpa versi.
    }
  }

  /// Domain email karyawan (placeholder .example — ganti dengan domain
  /// perusahaan). Dipakai untuk mengisi otomatis email akun baru.
  static const String emailDomain = 'prasasti.example';
}
