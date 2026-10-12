import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/core/utils/work_calendar.dart';
import 'package:hrms_app/data/attendance_repository.dart';
import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/mock/mock_attendance_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';

/// Jam kerja 09.00–17.00. Clock in/out bebas jam berapa pun; yang dinilai
/// hanya keterlambatan datang (tidak ada status pulang cepat).
void main() {
  group('WorkPolicy', () {
    test('jam kerja 09.00–17.00', () {
      expect(WorkPolicy.workStartHour, 9);
      expect(WorkPolicy.workEndHour, 17);
      expect(WorkPolicy.hoursLabel, '09.00–17.00');
    });

    test('terlambat bila datang setelah 09.00', () {
      expect(WorkPolicy.isLate(DateTime(2026, 10, 9, 9, 1)), isTrue);
      expect(WorkPolicy.isLate(DateTime(2026, 10, 9, 9)), isFalse);
    });
  });

  group('clock in/out bebas jam', () {
    late DateTime now;
    late MockStore store;
    late MockAttendanceRepository attendance;

    const staff = AuthUser(
      username: 'budi.santoso',
      fullName: 'Budi Santoso',
      role: UserRole.staff,
    );
    const office = GeoPoint(latitude: -6.175392, longitude: 106.827153);

    setUp(() {
      now = DateTime(2026, 10, 9, 8);
      store = MockStore(clock: () => now);
      attendance = MockAttendanceRepository(store, latency: Duration.zero);
    });

    test('pulang 16.00 setelah masuk 08.00 = tepat waktu', () async {
      await attendance.clockIn(staff, position: office);
      now = DateTime(2026, 10, 9, 16);
      await attendance.clockOut(staff, position: office);
      final days = await attendance.fetchMonth(staff, year: 2026, month: 10);
      final day = days.firstWhere((d) => d.date.day == 9);
      expect(day.status, AttendanceDayStatus.onTime);
    });
  });
}
