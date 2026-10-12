import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/attendance_repository.dart';
import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/mock/mock_attendance_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';

/// Pembatalan pengajuan koreksi & luar area oleh karyawan sendiri.
void main() {
  late DateTime now;
  late MockStore store;
  late MockAttendanceRepository attendance;

  const staff = AuthUser(
    username: 'budi.santoso',
    fullName: 'Budi Santoso',
    role: UserRole.staff,
  );
  const manager = AuthUser(
    username: 'siti.rahma',
    fullName: 'Siti Rahma',
    role: UserRole.manager,
  );
  const outside = GeoPoint(latitude: -6.18, longitude: 106.83);

  setUp(() {
    now = DateTime(2026, 10, 9, 8);
    store = MockStore(clock: () => now);
    attendance = MockAttendanceRepository(store, latency: Duration.zero);
  });

  Future<AttendanceCorrection> submitCorrection() {
    final day = DateTime(2026, 10, 8);
    return attendance.submitCorrection(
      staff,
      date: day,
      clockIn: DateTime(2026, 10, 8, 8, 5),
      clockOut: DateTime(2026, 10, 8, 17, 10),
      reason: 'Lupa clock out karena langsung ke venue.',
    );
  }

  group('batalkan koreksi', () {
    test('menunggu bisa dibatalkan, hilang dari antrean', () async {
      final correction = await submitCorrection();
      final cancelled = await attendance.cancelCorrection(
        staff,
        id: correction.id,
      );
      expect(cancelled.status, RequestStatus.cancelled);
      final queue = await attendance.fetchCorrectionQueue(manager);
      expect(
        queue.where((i) => i.correction.id == correction.id),
        isEmpty,
      );
    });

    test('yang sudah diproses / tidak ada ditolak', () async {
      final correction = await submitCorrection();
      await attendance.reviewCorrection(
        manager,
        id: correction.id,
        approve: true,
      );
      await expectLater(
        attendance.cancelCorrection(staff, id: correction.id),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('menunggu'),
          ),
        ),
      );
      await expectLater(
        attendance.cancelCorrection(staff, id: 'KR-tidak-ada'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('tidak ditemukan'),
          ),
        ),
      );
    });
  });

  group('batalkan luar area', () {
    test('menunggu bisa dibatalkan, hilang dari antrean', () async {
      final request = await attendance.submitOutOfArea(
        staff,
        kind: OutOfAreaKind.clockIn,
        position: outside,
        reason: 'Bertugas di venue klien sejak pagi.',
      );
      final cancelled = await attendance.cancelOutOfArea(
        staff,
        id: request.id,
      );
      expect(cancelled.status, RequestStatus.cancelled);
      final queue = await attendance.fetchOutOfAreaQueue(manager);
      expect(
        queue.where((i) => i.request.id == request.id),
        isEmpty,
      );
      expect(await attendance.fetchMyOutOfArea(staff), hasLength(1));
    });

    test('yang sudah diproses tidak bisa dibatalkan', () async {
      final request = await attendance.submitOutOfArea(
        staff,
        kind: OutOfAreaKind.clockIn,
        position: outside,
        reason: 'Bertugas di venue klien sejak pagi.',
      );
      await attendance.reviewOutOfArea(manager, id: request.id, approve: true);
      await expectLater(
        attendance.cancelOutOfArea(staff, id: request.id),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('menunggu'),
          ),
        ),
      );
    });
  });
}
