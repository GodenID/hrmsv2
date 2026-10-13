import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Akses warna semantik terpusat agar konsisten di semua widget.
///
/// Contoh: `color: Colors.white` (permukaan) -> `color: context.surface`;
/// `color: AppColors.inkSecondary` (teks sekunder) -> `color:
/// context.inkSecondary`.
extension ThemeColors on BuildContext {
  /// Selalu false — mode gelap dihapus, aplikasi terang saja.
  /// Getter dipertahankan agar call-site `context.isDark ? a : b`
  /// tetap kompilasi tanpa perubahan massal.
  bool get isDark => false;

  /// Latar permukaan.
  Color get surface => Colors.white;

  /// Latar lembut.
  Color get surfaceMuted => AppColors.surfaceMuted;

  /// Teks/ikon utama.
  Color get ink => AppColors.ink;

  /// Teks/ikon sekunder.
  Color get inkSecondary => AppColors.inkSecondary;

  /// Teks petunjuk.
  Color get inkTertiary => AppColors.inkTertiary;

  /// Garis pembatas.
  Color get border => AppColors.border;

  /// Garis tegas.
  Color get borderStrong => AppColors.borderStrong;

  /// Aksen untuk teks/ikon di atas latar.
  /// Isian tombol tetap memakai [AppColors.accent].
  Color get accentText => AppColors.accent;

  /// Latar aksen lembut.
  Color get accentSubtle => AppColors.accentSubtle;

  Color get success => AppColors.success;

  Color get successSubtle => AppColors.successSubtle;

  Color get warning => AppColors.warning;

  Color get warningSubtle => AppColors.warningSubtle;

  Color get danger => AppColors.danger;

  Color get dangerSubtle => AppColors.dangerSubtle;

  /// Isi kalender kehadiran.
  Color get presentFill => AppColors.presentFill;

  Color get leaveFill => AppColors.annualLeaveFill;

  Color get sickFill => AppColors.sickFill;

  Color get permitFill => AppColors.permissionFill;

  Color get missingFill => AppColors.missingFill;

  Color get overtimeTint => AppColors.overtimeFlag;
}
