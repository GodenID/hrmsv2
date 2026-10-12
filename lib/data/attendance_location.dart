import 'dart:math' as math;

/// Posisi perangkat saat clock in / clock out.
class GeoPoint {
  const GeoPoint({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.isMocked = false,
  });

  final double latitude;
  final double longitude;

  /// Perkiraan akurasi (radius ketidakpastian) dari perangkat.
  final double? accuracyMeters;

  /// true bila perangkat melaporkan lokasi palsu (Android: mock location).
  final bool isMocked;
}

/// Titik lokasi absen + radius yang diizinkan. Diatur Super Admin.
class AttendanceLocation {
  const AttendanceLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;

  /// Karyawan harus berada dalam jarak ini (meter) dari titik lokasi.
  final int radiusMeters;

  /// Jarak titik (lat, lng) ke titik lokasi ini (meter).
  double distanceTo(double lat, double lng) =>
      GeoMath.distanceMeters(latitude, longitude, lat, lng);

  String get coordinatesLabel =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
}

class AttendanceLocationDraft {
  const AttendanceLocationDraft({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final String name;
  final double latitude;
  final double longitude;
  final int radiusMeters;
}

/// Aturan validasi lokasi absen (dipakai formulir & mock server).
abstract final class LocationRules {
  static const int minRadius = 25;
  static const int maxRadius = 1000;
  static const int radiusStep = 25;
  static const int defaultRadius = 100;

  /// Jumlah lokasi yang direncanakan perusahaan (informasi di UI).
  static const int plannedCount = 4;

  static String? validateName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Nama lokasi wajib diisi';
    if (v.length < 3) return 'Minimal 3 karakter';
    if (v.length > 60) return 'Maksimal 60 karakter';
    return null;
  }

  static double? parseCoordinate(String? value) =>
      double.tryParse((value ?? '').trim().replaceAll(',', '.'));

  static String? validateLatitude(String? value) {
    final v = parseCoordinate(value);
    if ((value ?? '').trim().isEmpty) return 'Latitude wajib diisi';
    if (v == null || v < -90 || v > 90) {
      return 'Latitude antara -90 dan 90, mis. -6.175392';
    }
    return null;
  }

  static String? validateLongitude(String? value) {
    final v = parseCoordinate(value);
    if ((value ?? '').trim().isEmpty) return 'Longitude wajib diisi';
    if (v == null || v < -180 || v > 180) {
      return 'Longitude antara -180 dan 180, mis. 106.827153';
    }
    return null;
  }

  static String? validateRadius(int radius) {
    if (radius < minRadius || radius > maxRadius) {
      return 'Radius $minRadius–$maxRadius meter';
    }
    return null;
  }
}

abstract final class GeoMath {
  static const double _earthRadius = 6371000;

  /// Jarak dua koordinat (meter), rumus haversine.
  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) *
            math.cos(rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * _earthRadius * math.asin(math.min(1, math.sqrt(a)));
  }

  /// Arah dari (lat1, lng1) ke (lat2, lng2), derajat 0–360
  /// (0 = utara, 90 = timur). Dipakai menempatkan titik pengguna pada
  /// radar area absen.
  static double bearingDegrees(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    double rad(double d) => d * math.pi / 180;
    final dLng = rad(lng2 - lng1);
    final y = math.sin(dLng) * math.cos(rad(lat2));
    final x =
        math.cos(rad(lat1)) * math.sin(rad(lat2)) -
        math.sin(rad(lat1)) * math.cos(rad(lat2)) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// "85 m", "1,2 km", "12 km".
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    final km = meters / 1000;
    final text = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
    return '${text.replaceAll('.', ',')} km';
  }
}
