import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/leave_repository.dart';
import 'package:hrms_app/data/mock/mock_leave_repository.dart';
import 'package:hrms_app/data/mock/mock_notification_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';
import 'package:hrms_app/data/notification_repository.dart';

/// Potong cuti bersama massal: hak Super Admin, hitung otomatis hari kerja,
/// lewati yang sudah tercakup cuti, notifikasi + saldo berkurang.
void main() {
  late DateTime now;
  late MockStore store;
  late MockLeaveRepository leave;
  late MockNotificationRepository notifications;

  const superadmin = AuthUser(
    username: 'andi.pratama',
    fullName: 'Andi Pratama',
    role: UserRole.superadmin,
  );
  const manager = AuthUser(
    username: 'siti.rahma',
    fullName: 'Siti Rahma',
    role: UserRole.manager,
  );
  const staff = AuthUser(
    username: 'budi.santoso',
    fullName: 'Budi Santoso',
    role: UserRole.staff,
  );

  setUp(() {
    now = DateTime(2026, 10, 9, 10);
    store = MockStore(clock: () => now);
    leave = MockLeaveRepository(store, latency: Duration.zero);
    notifications = MockNotificationRepository(store, latency: Duration.zero);
  });

  Matcher leaveError(String part) => throwsA(
    isA<AppException>().having((e) => e.message, 'message', contains(part)),
  );

  Future<List<CollectiveLeaveResult>> apply({
    List<String> usernames = const ['budi.santoso'],
    DateTime? start,
    DateTime? end,
    String reason = 'Cuti bersama Natal',
    AuthUser actor = superadmin,
  }) => leave.applyCollectiveLeave(
    actor,
    usernames: usernames,
    start: start ?? DateTime(2026, 12, 24),
    end: end ?? DateTime(2026, 12, 25),
    reason: reason,
  );

  group('hak akses & validasi', () {
    test('manager & staff ditolak', () async {
      for (final actor in [manager, staff]) {
        await expectLater(
          apply(actor: actor),
          leaveError('Hanya Super Admin'),
        );
      }
    });

    test('rentang terbalik & akhir pekan saja ditolak', () async {
      await expectLater(
        apply(start: DateTime(2026, 12, 25), end: DateTime(2026, 12, 24)),
        leaveError('sebelum tanggal mulai'),
      );
      // 12–13 Des 2026 = Sabtu–Minggu.
      await expectLater(
        apply(start: DateTime(2026, 12, 12), end: DateTime(2026, 12, 13)),
        leaveError('akhir pekan'),
      );
    });

    test('tanpa karyawan & alasan pendek ditolak', () async {
      await expectLater(apply(usernames: const []), leaveError('minimal satu'));
      await expectLater(apply(reason: 'Lib'), leaveError('minimal 5'));
    });

    test('akun asing dilewati dengan alasan', () async {
      final results = await apply(usernames: const ['tidak.ada']);
      expect(results.single.applied, isFalse);
      expect(results.single.skipped, contains('nonaktif'));
    });
  });

  group('pemotongan', () {
    test('hari kerja dihitung otomatis, Sabtu–Minggu tidak ikut', () async {
      // 24–28 Des 2026: Kam, Jum, Sab, Min, Sen = 3 hari kerja.
      final results = await apply(
        start: DateTime(2026, 12, 24),
        end: DateTime(2026, 12, 28),
      );
      expect(results.single.days, 3);
      // Seed sudah punya 3 hari cuti tahunan yang disetujui.
      final balance = await leave.fetchBalance(staff);
      expect(balance.used, 3 + 3);
      final requests = await leave.fetchRequests(staff);
      final created = requests.firstWhere(
        (r) => r.reason == 'Cuti bersama Natal',
      );
      expect(created.status, RequestStatus.approved);
      expect(created.type, LeaveType.annual);
      expect(created.workingDays, 3);
    });

    test('tanggal yang sudah tercakup cuti tidak dipotong dua kali', () async {
      // Cuti tahunan pribadi 14–15 Des (Senin–Selasa), disetujui dulu.
      final req = await leave.submit(
        staff,
        type: LeaveType.annual,
        start: DateTime(2026, 12, 14),
        end: DateTime(2026, 12, 15),
        reason: 'Acara keluarga di luar kota.',
      );
      await leave.review(superadmin, id: req.id, approve: true);
      // Cuti bersama 14–18 Des = 5 hari kerja − 2 sudah cuti = 3.
      final results = await apply(
        start: DateTime(2026, 12, 14),
        end: DateTime(2026, 12, 18),
      );
      expect(results.single.days, 3);
      // 3 seed + 2 pribadi + 3 bersama.
      expect((await leave.fetchBalance(staff)).used, 3 + 2 + 3);
    });

    test('karyawan & saldo diberi tahu lewat notifikasi', () async {
      await apply();
      final items = await notifications.fetch(staff);
      final note = items.firstWhere(
        (n) => n.kind == NotificationKind.collectiveLeaveApplied,
      );
      expect(note.title, contains('2 hari terpotong'));
      // Kuota 12 − 3 seed − 2 bersama.
      expect(note.body, contains('Sisa 7 hari'));
    });

    test('banyak karyawan sekaligus, gagal satu tidak menggagalkan lain', () async {
      final results = await apply(
        usernames: const ['budi.santoso', 'tidak.ada', 'dewi.lestari'],
      );
      expect(results.where((r) => r.applied).length, 2);
      expect(results.where((r) => !r.applied).length, 1);
    });
  });
}
