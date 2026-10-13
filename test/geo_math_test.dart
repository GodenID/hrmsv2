import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/attendance_location.dart';

void main() {
  group('GeoMath.distanceMeters', () {
    test('titik sama = 0', () {
      expect(GeoMath.distanceMeters(-6.175392, 106.827153, -6.175392, 106.827153), 0);
    });

    test('Jakarta–Bandung sekitar 116 km', () {
      final d = GeoMath.distanceMeters(-6.2, 106.8, -6.9, 107.6);
      expect(d, greaterThan(100000));
      expect(d, lessThan(130000));
    });
  });

  group('GeoMath.formatDistance', () {
    test('meter vs kilometer', () {
      expect(GeoMath.formatDistance(85.4), '85 m');
      expect(GeoMath.formatDistance(1200), '1,2 km');
    });
  });
}
