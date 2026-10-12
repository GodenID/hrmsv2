/// Rute tingkat atas. Rute di dalam aplikasi (setelah login) ada di
/// `ShellRoutes`.
abstract final class AppRoutes {
  static const String login = '/';
  static const String startup = '/memuat';
  static const String forgotPassword = '/lupa-password';
  static const String register = '/daftar';
  static const String home = '/beranda';
}
