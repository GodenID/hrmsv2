import 'package:flutter/material.dart';

/// Design tokens: palette.
///
/// Arah visual: "Enterprise Control Plane" versi terang.
/// Latar putih, tinta biru-arang, satu aksen hijau-teal tua (pine)
/// yang dipakai hanya untuk aksi utama & status fokus.
abstract final class AppColors {
  // Permukaan
  static const Color background = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF5F7F8);

  // Tinta (teks)
  static const Color ink = Color(0xFF14212B);
  static const Color inkSecondary = Color(
    0xFF55636E,
  ); // kontras ~6:1 di atas putih
  static const Color inkTertiary = Color(
    0xFF6F7C86,
  ); // kontras ~4.5:1, untuk hint

  // Garis
  static const Color border = Color(0xFFDDE2E6);
  static const Color borderStrong = Color(0xFFBCC5CC);

  // Aksen
  static const Color accent = Color(0xFF0F5F5C);
  static const Color accentPressed = Color(0xFF0A4846);
  static const Color accentSubtle = Color(0xFFE8F1F0);

  // Semantik
  static const Color danger = Color(0xFFB42318);
  static const Color dangerSubtle = Color(0xFFFEF3F2);
  static const Color dangerBorder = Color(0xFFF5C2BC);
  static const Color success = Color(0xFF067647);
  static const Color successSubtle = Color(0xFFECF8F1);
  static const Color warning = Color(0xFF93370D); // kontras ~7:1 di atas putih
  static const Color warningSubtle = Color(0xFFFEF6E7);

  /// Isi indikator non-teks (mis. bar kekuatan password "Sedang").
  /// Jangan dipakai untuk teks — kontrasnya di bawah 4.5:1.
  static const Color warningIndicator = Color(0xFFDC8A06);

  // Kalender absensi: (isi, garis, tinta). Tinta dipilih agar kontras
  // >= 4.5:1 di atas isinya.
  static const Color presentFill = Color(0xFFCDEFD9);
  static const Color presentBorder = Color(0xFF8FD3AA);
  static const Color presentInk = Color(0xFF05603A);

  static const Color annualLeaveFill = Color(0xFFD6E4FD);
  static const Color annualLeaveBorder = Color(0xFF9FBEF6);
  static const Color annualLeaveInk = Color(0xFF1849A9);

  static const Color sickFill = Color(0xFFFCDCEA);
  static const Color sickBorder = Color(0xFFF2A6C7);
  static const Color sickInk = Color(0xFF9E1C56);

  static const Color permissionFill = Color(0xFFE7DEFB);
  static const Color permissionBorder = Color(0xFFC4B1F2);
  static const Color permissionInk = Color(0xFF5B2BB5);

  static const Color missingFill = Color(0xFFE6EAED);
  static const Color missingBorder = Color(0xFFD0D7DC);

  /// Penanda lembur (titik/bintang di sel kalender & baris Excel).
  static const Color overtimeFlag = Color(0xFF2563EB);
}
