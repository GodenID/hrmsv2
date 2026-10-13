import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/attendance_repository.dart';
import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/mock/mock_attendance_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';

/// Skenario user: H-6 hari kerja (Rabu 7 Okt 2026, posisi Selasa 13 Okt 2026)
/// bisa diketuk lalu diajukan koreksi; Sabtu dalam jendela juga bisa;
/// tanggal ke depan tetap tidak bisa.
void main() {
  late DateTime now;
  late MockStore store;
  late MockAttendanceRepository attendance;

  const staff = AuthUser(
    username: 'budi.santoso',
    fullName: 'Budi Santoso',
    role: UserRole.staff,
  );

  setUp(() {
    now = DateTime(2026, 10, 13, 8);
    store = MockStore(clock: () => now);
    attendance = MockAttendanceRepository(store, latency: Duration.zero);
  });

  Future<List<AttendanceDay>> october() =>
      attendance.fetchMonth(staff, year: 2026, month: 10);

  AttendanceDay dayOf(List<AttendanceDay> days, int d) =>
      days.firstWhere((e) => e.date.day == d);

  group('koreksi backdate', () {
    test('Rabu 7 Okt tampil & bisa diajukan', () async {
      final day = dayOf(await october(), 7);
      expect(day.canRequestCorrection(now), isTrue);
      final c = await attendance.submitCorrection(
        staff,
        date: DateTime(2026, 10, 7),
        clockIn: DateTime(2026, 10, 7, 8),
        clockOut: DateTime(2026, 10, 7, 17),
        reason: 'Lupa absen pagi hari itu.',
      );
      expect(c.status, RequestStatus.pending);
    });

    test('Sabtu 10 Okt tampil sebagai Libur & bisa diajukan', () async {
      final day = dayOf(await october(), 10);
      expect(day.status, AttendanceDayStatus.dayOff);
      expect(day.canRequestCorrection(now), isTrue);
      final c = await attendance.submitCorrection(
        staff,
        date: DateTime(2026, 10, 10),
        clockIn: DateTime(2026, 10, 10, 8),
        clockOut: DateTime(2026, 10, 10, 12),
        reason: 'Piket Sabtu pagi sampai siang.',
      );
      expect(c.status, RequestStatus.pending);
    });

    test('tanggal depan tetap tidak bisa', () async {
      final days = await october();
      // Hari depan tanpa cuti bahkan tidak muncul di daftar (tak bisa diketuk).
      expect(days.any((e) => e.date.day == 20), isFalse);
      await expectLater(
        attendance.submitCorrection(
          staff,
          date: DateTime(2026, 10, 20),
          clockIn: DateTime(2026, 10, 20, 8),
          clockOut: DateTime(2026, 10, 20, 17),
          reason: 'Tidak mungkin diajukan.',
        ),
        throwsA(isA<AppException>()),
      );
    });
  });
}
