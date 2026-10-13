import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/attendance_repository.dart';
import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/mock/mock_attendance_repository.dart';
import 'package:hrms_app/data/mock/mock_notification_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';
import 'package:hrms_app/data/notification_repository.dart';

/// Pengajuan clock in / clock out dari luar area: submit, antrean,
/// persetujuan menulis jam, dan riwayat.
void main() {
  late DateTime now;
  late MockStore store;
  late MockAttendanceRepository attendance;
  late MockNotificationRepository notifications;

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

  // Tepat di titik Kantor Pusat (contoh).
  const inside = GeoPoint(latitude: -6.175392, longitude: 106.827153);
  // ±600 m dari Kantor Pusat: di luar radius 100 m.
  const outside = GeoPoint(latitude: -6.18, longitude: 106.83);
  const mocked = GeoPoint(
    latitude: -6.175392,
    longitude: 106.827153,
    isMocked: true,
  );

  setUp(() {
    now = DateTime(2026, 10, 9, 8);
    store = MockStore(clock: () => now);
    attendance = MockAttendanceRepository(store, latency: Duration.zero);
    notifications = MockNotificationRepository(store, latency: Duration.zero);
  });

  Matcher attendanceError(String part) => throwsA(
    isA<AppException>().having((e) => e.message, 'message', contains(part)),
  );

  Future<OutOfAreaRequest> submitIn({String reason = 'Bertugas di venue klien sejak pagi.'}) {
    return attendance.submitOutOfArea(
      staff,
      kind: OutOfAreaKind.clockIn,
      position: outside,
      reason: reason,
    );
  }

  group('submit', () {
    test('di luar area menjadi pengajuan menunggu', () async {
      final request = await submitIn();
      expect(request.status, RequestStatus.pending);
      expect(request.kind, OutOfAreaKind.clockIn);
      expect(request.requestedAt, now);
      expect(request.nearestLocationName, isNotEmpty);
      expect(request.distanceMeters, greaterThan(100));
      // Jam belum tercatat sebelum disetujui.
      expect((await attendance.fetchToday(staff)).clockIn, isNull);
      // Reviewer diberi tahu.
      final forManager = await notifications.fetch(manager);
      expect(
        forManager.any(
          (n) =>
              n.kind == NotificationKind.reviewRequested &&
              n.title.contains('luar area'),
        ),
        isTrue,
      );
    });

    test('di dalam area ditolak, pakai tombol biasa', () async {
      await expectLater(
        attendance.submitOutOfArea(
          staff,
          kind: OutOfAreaKind.clockIn,
          position: inside,
          reason: 'Alasan yang cukup panjang.',
        ),
        attendanceError('tombol Clock in biasa'),
      );
    });

    test('lokasi palsu ditolak', () async {
      await expectLater(
        attendance.submitOutOfArea(
          staff,
          kind: OutOfAreaKind.clockIn,
          position: mocked,
          reason: 'Alasan yang cukup panjang.',
        ),
        attendanceError('palsu'),
      );
    });

    test('alasan terlalu pendek ditolak', () async {
      await expectLater(
        attendance.submitOutOfArea(
          staff,
          kind: OutOfAreaKind.clockIn,
          position: outside,
          reason: 'Sakit',
        ),
        attendanceError('minimal 10 karakter'),
      );
    });

    test('ajukan ulang sisi sama = diperbarui, bukan ditolak', () async {
      final first = await submitIn();
      now = now.add(const Duration(hours: 2));
      final second = await submitIn(
        reason: 'Masih di venue klien hingga siang.',
      );
      // ID sama, jam & alasan ikut waktu pengajuan terbaru.
      expect(second.id, first.id);
      expect(second.requestedAt, now);
      expect(second.reason, 'Masih di venue klien hingga siang.');
      expect(second.status, RequestStatus.pending);
      final mine = await attendance.fetchMyOutOfArea(staff);
      expect(mine.length, 1);
    });

    test('clock biasa membatalkan pengajuan menunggu sisi sama', () async {
      await submitIn();
      await attendance.clockIn(staff, position: inside);
      final mine = await attendance.fetchMyOutOfArea(staff);
      expect(mine.single.status, RequestStatus.cancelled);
      expect((await attendance.fetchToday(staff)).clockIn, isNotNull);
    });

    test('clock out luar area butuh clock in dulu', () async {
      await expectLater(
        attendance.submitOutOfArea(
          staff,
          kind: OutOfAreaKind.clockOut,
          position: outside,
          reason: 'Pulang dari venue klien sore ini.',
        ),
        attendanceError('sudah clock in'),
      );
    });

    test('jam yang disetujui diakui validasi sisi', () async {
      // Clock in disetujui (luar area) -> clock out boleh diajukan
      // maupun dicatat biasa, tanpa "clock in dulu".
      final request = await submitIn();
      await attendance.reviewOutOfArea(
        manager,
        id: request.id,
        approve: true,
      );
      final out = await attendance.submitOutOfArea(
        staff,
        kind: OutOfAreaKind.clockOut,
        position: outside,
        reason: 'Pulang dari venue klien sore ini.',
      );
      expect(out.status, RequestStatus.pending);
      final record = await attendance.clockOut(staff, position: inside);
      expect(record.clockOut, isNotNull);
    });
  });

  group('review', () {
    test('disetujui = jam tercatat bertanda luar area', () async {
      final request = await submitIn();
      final reviewed = await attendance.reviewOutOfArea(
        manager,
        id: request.id,
        approve: true,
      );
      expect(reviewed.request.status, RequestStatus.approved);
      final record = await attendance.fetchToday(staff);
      expect(record.clockIn, now);
      expect(record.clockInLocation, contains('luar area'));
      // Karyawan diberi notifikasi hasil.
      final mine = await notifications.fetch(staff);
      expect(
        mine.any((n) => n.kind == NotificationKind.outOfAreaApproved),
        isTrue,
      );
    });

    test('ditolak = jam tidak tercatat + wajib alasan', () async {
      final request = await submitIn();
      await expectLater(
        attendance.reviewOutOfArea(manager, id: request.id, approve: false),
        attendanceError('minimal 5 karakter'),
      );
      await attendance.reviewOutOfArea(
        manager,
        id: request.id,
        approve: false,
        note: 'Tidak ada penugasan luar tercatat.',
      );
      expect((await attendance.fetchToday(staff)).clockIn, isNull);
      final mine = await notifications.fetch(staff);
      expect(
        mine.any((n) => n.kind == NotificationKind.outOfAreaRejected),
        isTrue,
      );
    });

    test('clock out luar area disetujui menulis jam pulang', () async {
      await attendance.clockIn(staff, position: inside);
      final request = await attendance.submitOutOfArea(
        staff,
        kind: OutOfAreaKind.clockOut,
        position: outside,
        reason: 'Pulang dari venue klien sore ini.',
      );
      await attendance.reviewOutOfArea(manager, id: request.id, approve: true);
      final record = await attendance.fetchToday(staff);
      expect(record.clockIn, isNotNull);
      expect(record.clockOut, now);
      expect(record.clockOutLocation, contains('luar area'));
    });

    test('tidak bisa memproses sendiri & staff tidak bisa mereview', () async {
      final request = await submitIn();
      await expectLater(
        attendance.reviewOutOfArea(
          staff,
          id: request.id,
          approve: true,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        attendance.fetchOutOfAreaQueue(staff),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('manager bisa menyetujui pengajuan luar-areanya sendiri', () async {
      final request = await attendance.submitOutOfArea(
        manager,
        kind: OutOfAreaKind.clockIn,
        position: outside,
        reason: 'Dinas luar ke venue klien pagi ini.',
      );
      expect(request.status, RequestStatus.pending);
      // Muncul di antreannya sendiri.
      final queue = await attendance.fetchOutOfAreaQueue(manager);
      expect(queue.any((i) => i.request.id == request.id), isTrue);
      final reviewed = await attendance.reviewOutOfArea(
        manager,
        id: request.id,
        approve: true,
      );
      expect(reviewed.request.status, RequestStatus.approved);
    });

    test('disetujui keesokan hari tetap masuk riwayat', () async {
      final request = await submitIn();
      now = now.add(const Duration(days: 1));
      await attendance.reviewOutOfArea(manager, id: request.id, approve: true);
      final days = await attendance.fetchMonth(
        staff,
        year: 2026,
        month: 10,
      );
      final day = days.firstWhere((d) => d.date.day == 9);
      expect(day.outOfArea?.status, RequestStatus.approved);
      expect(day.clockIn, DateTime(2026, 10, 9, 8));
    });
  });

  group('antrean', () {
    test('menunggu dulu, yang sudah diproses belakangan', () async {
      final first = await submitIn();
      await attendance.reviewOutOfArea(manager, id: first.id, approve: true);
      // Pengajuan kedua untuk sisi satunya (clock out): clock in sudah ada.
      await attendance.submitOutOfArea(
        staff,
        kind: OutOfAreaKind.clockOut,
        position: outside,
        reason: 'Pulang dari venue klien sore ini.',
      );
      final queue = await attendance.fetchOutOfAreaQueue(manager);
      expect(queue.first.request.status, RequestStatus.pending);
      expect(queue.first.request.kind, OutOfAreaKind.clockOut);
      expect(queue.last.request.status, RequestStatus.approved);
    });
  });
}
