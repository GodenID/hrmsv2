import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/leave_repository.dart';
import 'package:hrms_app/data/mock/mock_leave_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';

/// Cuti melahirkan 3 bulan otomatis + blokir cuti tahunan saat kuota habis.
///
/// Catatan: uji memakai rizky.ramadhan (tanpa seed cuti) agar rentang
/// 3 bulan tidak bertabrakan dengan seed milik budi.santoso.
void main() {
  late DateTime now;
  late MockStore store;
  late MockLeaveRepository leave;

  const superadmin = AuthUser(
    username: 'andi.pratama',
    fullName: 'Andi Pratama',
    role: UserRole.superadmin,
  );
  const staff = AuthUser(
    username: 'budi.santoso',
    fullName: 'Budi Santoso',
    role: UserRole.staff,
  );
  const rizky = AuthUser(
    username: 'rizky.ramadhan',
    fullName: 'Rizky Ramadhan',
    role: UserRole.staff,
  );

  setUp(() {
    now = DateTime(2026, 10, 9, 10);
    store = MockStore(clock: () => now);
    leave = MockLeaveRepository(store, latency: Duration.zero);
  });

  Matcher leaveError(String part) => throwsA(
    isA<AppException>().having((e) => e.message, 'message', contains(part)),
  );

  Future<LeaveRequest> submitMaternity(AuthUser user) => leave.submit(
    user,
    type: LeaveType.maternity,
    // Tanggal usulan diabaikan server: selalu 3 bulan sejak hari ini.
    start: DateTime(2026, 11, 1),
    end: DateTime(2026, 11, 2),
    reason: 'Perkiraan tanggal lahir 10 Januari.',
  );

  group('cuti melahirkan', () {
    test('tanggal otomatis 3 bulan sejak hari pengajuan', () async {
      final req = await submitMaternity(rizky);
      expect(req.start, DateTime(2026, 10, 9));
      expect(req.end, DateTime(2027, 1, 9));
      expect(req.workingDays, greaterThan(50));
      expect(req.status, RequestStatus.pending);
    });

    test('tidak memotong kuota cuti tahunan', () async {
      final before = await leave.fetchBalance(rizky);
      final req = await submitMaternity(rizky);
      await leave.review(superadmin, id: req.id, approve: true);
      final after = await leave.fetchBalance(rizky);
      expect(after.used, before.used);
    });

    test('bisa disetujui walau kuota tahunan habis', () async {
      // Seed 12 hari cuti lampau yang disetujui (di luar rentang
      // melahirkan sehingga tidak bertabrakan).
      LeaveRequest past(String id, DateTime s, DateTime e, int days) =>
          LeaveRequest(
            id: id,
            type: LeaveType.annual,
            start: s,
            end: e,
            workingDays: days,
            reason: 'Cuti lampau.',
            status: RequestStatus.approved,
            submittedAt: DateTime(2026, 9, 1),
            reviewedBy: 'Siti Rahma',
            reviewedAt: DateTime(2026, 9, 1),
          );
      store.leaveRequests['rizky.ramadhan'] = [
        past('LV-P1', DateTime(2026, 2, 2), DateTime(2026, 2, 6), 5),
        past('LV-P2', DateTime(2026, 3, 2), DateTime(2026, 3, 6), 5),
        past('LV-P3', DateTime(2026, 4, 6), DateTime(2026, 4, 7), 2),
      ];
      expect((await leave.fetchBalance(rizky)).available, 0);
      final req = await submitMaternity(rizky);
      final reviewed = await leave.review(
        superadmin,
        id: req.id,
        approve: true,
      );
      expect(reviewed.request.status, RequestStatus.approved);
    });

    test('bentrok dengan cuti lain tetap ditolak', () async {
      await submitMaternity(rizky);
      await expectLater(
        leave.submit(
          rizky,
          type: LeaveType.annual,
          start: DateTime(2026, 10, 26),
          end: DateTime(2026, 10, 27),
          reason: 'Acara keluarga di luar kota.',
        ),
        leaveError('Bertabrakan'),
      );
    });
  });

  group('kuota habis', () {
    test('cuti tahunan tidak bisa diajukan lagi', () async {
      // Seed budi: 3 terpakai + 2 menunggu = 7 bisa diajukan.
      final extra = await leave.submit(
        staff,
        type: LeaveType.annual,
        start: DateTime(2026, 11, 2),
        end: DateTime(2026, 11, 10),
        reason: 'Acara keluarga di luar kota.',
      );
      await leave.review(superadmin, id: extra.id, approve: true);
      expect((await leave.fetchBalance(staff)).available, 0);
      await expectLater(
        leave.submit(
          staff,
          type: LeaveType.annual,
          start: DateTime(2026, 12, 1),
          end: DateTime(2026, 12, 2),
          reason: 'Acara keluarga di luar kota.',
        ),
        leaveError('Sisa cuti tahunan'),
      );
    });
  });
}
