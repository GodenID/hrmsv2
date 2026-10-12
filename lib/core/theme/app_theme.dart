import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';

/// Tema aplikasi HRMS.
///
/// Font: memakai font sistem (Segoe UI / SF / Roboto) secara sengaja —
/// ini aplikasi internal karyawan, jadi prioritasnya keterbacaan,
/// performa, dan tidak bergantung pada unduhan font.
abstract final class AppTheme {
  static ThemeData light() {
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.accent,
          onPrimary: Colors.white,
          surface: AppColors.background,
          onSurface: AppColors.ink,
          onSurfaceVariant: AppColors.inkSecondary,
          error: AppColors.danger,
          onError: Colors.white,
          outline: AppColors.borderStrong,
          outlineVariant: AppColors.border,
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: Brightness.light,
    );

    // merge (bukan copyWith) agar font keluarga bawaan platform tetap dipakai.
    final textTheme = base.textTheme.merge(
      const TextTheme(
        // Judul halaman (mis. "Masuk")
        headlineSmall: TextStyle(
          fontSize: 26,
          height: 32 / 26,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: AppColors.ink,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 22 / 16,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          height: 22 / 15,
          color: AppColors.ink,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 20 / 14,
          color: AppColors.ink,
        ),
        bodySmall: TextStyle(
          fontSize: 13,
          height: 18 / 13,
          color: AppColors.inkSecondary,
        ),
        // Label tombol
        labelLarge: TextStyle(
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
        ),
        // Label field formulir
        labelMedium: TextStyle(
          fontSize: 13,
          height: 18 / 13,
          fontWeight: FontWeight.w500,
          color: AppColors.ink,
        ),
        // Overline / keterangan kecil berhuruf kapital
        labelSmall: TextStyle(
          fontSize: 11,
          height: 16 / 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
          color: AppColors.inkSecondary,
        ),
      ),
    );

    OutlineInputBorder border(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: AppColors.inkTertiary, fontSize: 14),
        prefixIconColor: WidgetStateColor.resolveWith((states) {
          if (states.contains(WidgetState.error)) return AppColors.danger;
          if (states.contains(WidgetState.focused)) return AppColors.accent;
          return AppColors.inkTertiary;
        }),
        suffixIconColor: AppColors.inkSecondary,
        border: border(AppColors.borderStrong),
        enabledBorder: border(AppColors.borderStrong),
        disabledBorder: border(AppColors.border),
        focusedBorder: border(AppColors.accent, 1.6),
        errorBorder: border(AppColors.danger),
        focusedErrorBorder: border(AppColors.danger, 1.6),
        errorStyle: const TextStyle(
          color: AppColors.danger,
          fontSize: 12.5,
          height: 1.3,
        ),
        helperStyle: const TextStyle(
          color: AppColors.inkSecondary,
          fontSize: 12.5,
          height: 1.3,
        ),
        counterStyle: const TextStyle(
          color: AppColors.inkSecondary,
          fontSize: 12,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
        errorMaxLines: 2,
        helperMaxLines: 2,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
          elevation: const WidgetStatePropertyAll(0),
          textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          backgroundColor: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.accent.withValues(alpha: 0.72);
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.accentPressed;
            }
            return AppColors.accent;
          }),
          overlayColor: WidgetStatePropertyAll(
            Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.accent),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontSize: 13.5),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 10),
          ),
          minimumSize: const WidgetStatePropertyAll(Size(48, 40)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
          overlayColor: WidgetStatePropertyAll(
            AppColors.accent.withValues(alpha: 0.08),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.inkSecondary),
          overlayColor: WidgetStatePropertyAll(
            AppColors.ink.withValues(alpha: 0.06),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(64, 40)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14),
          ),
          foregroundColor: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? AppColors.inkTertiary
                : AppColors.ink,
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.borderStrong),
          ),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontSize: 13.5),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
            ),
          ),
          overlayColor: WidgetStatePropertyAll(
            AppColors.ink.withValues(alpha: 0.05),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
        ),
        titleTextStyle: textTheme.titleMedium?.copyWith(fontSize: 18),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.inkSecondary,
          height: 1.5,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
          side: const BorderSide(color: AppColors.border),
        ),
        textStyle: textTheme.bodyMedium,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: AppColors.accentSubtle,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.inkSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.inkSecondary,
          ),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: Colors.white,
        headerForegroundColor: AppColors.ink,
        dividerColor: AppColors.border,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
        ),
        todayBorder: const BorderSide(color: AppColors.accent),
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
        ),
        dialBackgroundColor: AppColors.surfaceMuted,
        hourMinuteShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: AppColors.borderStrong,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

}
