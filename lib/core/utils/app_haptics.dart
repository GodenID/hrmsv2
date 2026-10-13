import 'package:flutter/services.dart';

/// Getar haptic yang seragam (semua dibungkus aman untuk web/desktop).
abstract final class AppHaptics {
  /// Aksi berhasil (clock in/out tercatat, pengajuan terkirim).
  static Future<void> success() => _run(HapticFeedback.mediumImpact);

  /// Persetujuan (setujui pengajuan).
  static Future<void> confirm() => _run(HapticFeedback.lightImpact);

  /// Penolakan / aksi destruktif.
  static Future<void> reject() => _run(HapticFeedback.heavyImpact);

  static Future<void> _run(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (_) {
      // Perangkat tidak mendukung haptic: abaikan.
    }
  }
}
