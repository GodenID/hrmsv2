import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/attendance_repository.dart';
import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/mock/mock_attendance_repository.dart';
import 'package:hrms_app/data/mock/mock_notification_repository.dart';
import 'package:hrms_app/data/mock/mock_overtime_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';
import 'package:hrms_app/data/notification_repository.dart';
import 'package:hrms_app/data/overtime_repository.dart';
import 'package:hrms_app/features/attendance/attendance_presentation.dart';

/// Pengajuan lembur: validasi, antrean, persetujuan, pembatalan.
void main() {
  late DateTime now;
  late MockStore store;
  late MockOvertimeRepository overtime;
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

  setUp(() {
    now = DateTime(2026, 10, 9, 18);
    store = MockStore(clock: () => now);
    overtime = MockOvertimeRepository(store, latency: Duration.zero);
    notifications = MockNotificationRepository(store, latency: Duration.zero);
  });

  DateTime day(int dayOffset) {
    final base = DateTime(2026, 10, 9).add(Duration(days: dayOffset));
    return DateTime(base.year, base.month, base.day);
  }

  Future<OvertimeRequest> submit({
    int dayOffset = 0,
    int startHour = 18,
    int endHour = 21,
    String reason = 'Menyelesaikan laporan akhir bulan.',
  }) {
    final d = day(dayOffset);
    return overtime.submit(
      staff,
      date: d,
      start: DateTime(d.year, d.month, d.day, startHour),
      end: DateTime(d.year, d.month, d.day, endHour),
      reason: reason,
    );
  }

  Matcher overtimeError(String part) => throwsA(
    isA<AppException>().having((e) => e.message, 'message', contains(part)),
  );

  group('submit', () {
    test('tersimpan dengan durasi yang benar', () async {
      final request = await submit();
      expect(request.status, RequestStatus.pending);
      expect(request.duration, const Duration(hours: 3));
      expect(request.durationLabel, '3 jam');
      expect(request.timeRangeLabel, '18:00 – 21:00');
      // Reviewer diberi tahu.
      final forManager = await notifications.fetch(manager);
      expect(
        forManager.any(
          (n) =>
              n.kind == NotificationKind.reviewRequested &&
              n.title.contains('lembur'),
        ),
        isTrue,
      );
    });

    test('masa depan ditolak', () async {
      await expectLater(
        submit(dayOffset: 1),
        overtimeError('setelah dikerjakan'),
      );
    });

    test('lebih dari 30 hari lalu ditolak', () async {
      await expectLater(
        submit(dayOffset: -31),
        overtimeError('30 hari terakhir'),
      );
    });

    test('selesai harus setelah mulai & minimal 1 jam', () async {
      final d = day(0);
      Future<void> bad(int s, int e) => expectLater(
        overtime.submit(
          staff,
          date: d,
          start: DateTime(d.year, d.month, d.day, s),
          end: DateTime(d.year, d.month, d.day, e),
          reason: 'Menyelesaikan laporan akhir bulan.',
        ),
        overtimeError('Jam selesai'),
      );
      await bad(21, 18);
      await bad(18, 18);
      await expectLater(
        overtime.submit(
          staff,
          date: d,
          start: DateTime(d.year, d.month, d.day, 18),
          end: DateTime(d.year, d.month, d.day, 18, 30),
          reason: 'Menyelesaikan laporan akhir bulan.',
        ),
        overtimeError('minimal 60 menit'),
      );
    });

    test('keterangan terlalu pendek ditolak', () async {
      final d = day(0);
      await expectLater(
        overtime.submit(
          staff,
          date: d,
          start: DateTime(d.year, d.month, d.day, 18),
          end: DateTime(d.year, d.month, d.day, 21),
          reason: 'Lembur',
        ),
        overtimeError('minimal 10 karakter'),
      );
    });

    test('bentrok cuti ditolak', () async {
      // Budi punya cuti tahunan disetujui 17–18 Sep 2026 (seed).
      final d = DateTime(2026, 9, 18);
      await expectLater(
        overtime.submit(
          staff,
          date: d,
          start: DateTime(2026, 9, 18, 18),
          end: DateTime(2026, 9, 18, 21),
          reason: 'Menyelesaikan laporan akhir bulan.',
        ),
        overtimeError('cuti tahunan'),
      );
    });

    test('satu tanggal satu pengajuan aktif', () async {
      await submit();
      await expectLater(submit(), overtimeError('Sudah ada pengajuan'));
    });
  });

  group('review', () {
    test('disetujui + karyawan diberi tahu', () async {
      final request = await submit();
      final reviewed = await overtime.review(
        manager,
        id: request.id,
        approve: true,
      );
      expect(reviewed.request.status, RequestStatus.approved);
      expect(reviewed.request.reviewedBy, 'Siti Rahma');
      final mine = await notifications.fetch(staff);
      expect(
        mine.any((n) => n.kind == NotificationKind.overtimeApproved),
        isTrue,
      );
    });

    test('ditolak wajib alasan + antrean terurut', () async {
      final first = await submit();
      await overtime.submit(
        staff,
        date: day(-1),
        start: DateTime(2026, 10, 8, 18),
        end: DateTime(2026, 10, 8, 20),
        reason: 'Menyiapkan materi presentasi pagi.',
      );
      await expectLater(
        overtime.review(manager, id: first.id, approve: false),
        overtimeError('minimal 5 karakter'),
      );
      await overtime.review(
        manager,
        id: first.id,
        approve: false,
        note: 'Tidak ada penugasan lembur tercatat.',
      );
      final queue = await overtime.fetchReviewQueue(manager);
      // Menunggu dulu, yang diproses belakangan.
      expect(queue.first.request.status, RequestStatus.pending);
      expect(queue.last.request.status, RequestStatus.rejected);
    });

    test('tidak bisa memproses sendiri & staff ditolak', () async {
      final request = await submit();
      await expectLater(
        overtime.review(staff, id: request.id, approve: true),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        overtime.fetchReviewQueue(staff),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });

  group('tampil di absensi', () {
    test('riwayat memuat pengajuan + bendera biru di kalender', () async {
      await submit(dayOffset: -1);
      final attendance = MockAttendanceRepository(
        store,
        latency: Duration.zero,
      );
      final days = await attendance.fetchMonth(staff, year: 2026, month: 10);
      final day = days.firstWhere((d) => d.date.day == 8);
      expect(day.overtime?.status, RequestStatus.pending);
      expect(day.overtime?.durationLabel, '3 jam');
      final look = calendarLookFor(
        day,
        date: day.date,
        today: DateTime(2026, 10, 9),
      );
      expect(look.flags, contains(CalendarFlag.overtime));
    });
  });

  group('proses massal (bulk)', () {
    test('superadmin menyetujui banyak pengajuan sekaligus', () async {
      final first = await submit();
      final second = await overtime.submit(
        staff,
        date: day(-2),
        start: DateTime(2026, 10, 7, 18),
        end: DateTime(2026, 10, 7, 21),
        reason: 'Menyiapkan materi presentasi pagi.',
      );
      for (final id in [first.id, second.id]) {
        await overtime.review(manager, id: id, approve: true);
      }
      final queue = await overtime.fetchReviewQueue(manager);
      expect(
        queue.where((i) => i.request.status == RequestStatus.approved),
        hasLength(2),
      );
      final notes = await notifications.fetch(staff);
      expect(
        notes
            .where((n) => n.kind == NotificationKind.overtimeApproved)
            .length,
        2,
      );
    });
  });

  group('batalkan', () {
    test('menunggu bisa dibatalkan', () async {
      final request = await submit();
      final cancelled = await overtime.cancel(staff, id: request.id);
      expect(cancelled.status, RequestStatus.cancelled);
      final queue = await overtime.fetchReviewQueue(manager);
      expect(queue.where((i) => i.request.id == request.id), isEmpty);
    });

    test('yang sudah diproses tidak bisa dibatalkan', () async {
      final request = await submit();
      await overtime.review(manager, id: request.id, approve: true);
      await expectLater(
        overtime.cancel(staff, id: request.id),
        overtimeError('menunggu'),
      );
    });
  });
}
