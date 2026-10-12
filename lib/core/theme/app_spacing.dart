/// Design tokens: spacing & radius.
///
/// Skala 4pt. Radius sengaja kecil agar terasa seperti aplikasi kerja,
/// bukan aplikasi konsumen.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Lebar maksimal kolom formulir.
  static const double formMaxWidth = 400;

  /// Breakpoint untuk tata letak dua panel (desktop/tablet landscape).
  static const double splitBreakpoint = 960;

  /// Di atas lebar ini: menu samping. Di bawahnya: menu bawah (HP/tablet).
  static const double sidebarBreakpoint = 960;

  static bool isSidebarLayout(double width) => width >= sidebarBreakpoint;
}

abstract final class AppRadius {
  static const double control = 6; // input, tombol
  static const double panel = 8; // banner, kartu informasi
}
