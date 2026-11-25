import 'package:prasasti_server/dates.dart';
import 'package:test/test.dart';

void main() {
  group('isLate mengikuti batas masuk divisi (WIB)', () {
    // WIB = UTC+7, jadi 08.00 WIB = 01.00 UTC.
    DateTime wib(int hour, int minute, [int second = 0]) =>
        DateTime.utc(2026, 11, 23, hour - 7, minute, second);

    test('Produksi Mutiari batas 08.00', () {
      expect(isLate(wib(8, 0), division: 'produksiMutiari'), isFalse);
      expect(isLate(wib(8, 0, 1), division: 'produksiMutiari'), isTrue);
      expect(isLate(wib(8, 30), division: 'Produksi Mutiari'), isTrue);
    });

    test('divisi lain batas 09.00', () {
      expect(isLate(wib(9, 0), division: 'hrIt'), isFalse);
      expect(isLate(wib(9, 0, 1), division: 'hrIt'), isTrue);
      expect(isLate(wib(8, 30), division: 'hrIt'), isFalse);
    });

    test('tanpa divisi memakai batas 09.00', () {
      expect(isLate(wib(8, 59)), isFalse);
      expect(isLate(wib(9, 1)), isTrue);
    });
  });

  group('wibWallClockToUtc', () {
    final day = DateTime(2026, 11, 24);

    test('jam dinding pagi dipertahankan saat ditampilkan kembali', () {
      final utc = wibWallClockToUtc(day, 5, 0);
      expect(utc.toIso8601String(), '2026-11-23T22:00:00.000Z');
      expect(utc.add(const Duration(hours: 7)).hour, 5);
    });

    test('jam dinding malam dipertahankan', () {
      final utc = wibWallClockToUtc(day, 20, 30);
      expect(utc.toIso8601String(), '2026-11-24T13:30:00.000Z');
      expect(utc.add(const Duration(hours: 7)).hour, 20);
    });
  });
}
