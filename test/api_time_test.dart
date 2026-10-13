import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/api/api_time.dart';

/// Jam API selalu tampil zona lokal (WIB), tidak pernah mentah UTC.
void main() {
  test('instant UTC dikonversi ke lokal', () {
    // 04:26 UTC = 11:26 WIB (mesin penguji di WIB).
    final d = apiDateTime('2026-10-13T04:26:00.000Z');
    expect(d.isUtc, isFalse);
    expect(
      d,
      DateTime.utc(2026, 10, 13, 4, 26).toLocal(),
    );
  });

  test('tanggal-only tetap tanggal yang sama', () {
    final d = apiDateTime('2026-10-13');
    expect(d.year, 2026);
    expect(d.month, 10);
    expect(d.day, 13);
  });

  test('null & kosong -> fallback & null', () {
    expect(apiDateTimeOpt(null), isNull);
    expect(apiDateTimeOpt(''), isNull);
    final fb = DateTime(2020);
    expect(apiDateTime(null, fb), fb);
  });
}
