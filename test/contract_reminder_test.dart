import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/core/utils/work_calendar.dart';
import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/employee_repository.dart';
import 'package:hrms_app/data/mock/mock_employee_repository.dart';
import 'package:hrms_app/data/mock/mock_notification_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';
import 'package:hrms_app/data/notification_repository.dart';

/// Pengingat kontrak hampir berakhir (tersisa ≤ 30 hari) untuk Manager &
/// Super Admin. Jam bisa dimajukan lewat [now].
void main() {
  late DateTime now;
  late MockStore store;
  late MockEmployeeRepository employees;
  late MockNotificationRepository notifications;

  const admin = AuthUser(
    username: 'andi.pratama',
    fullName: 'Andi Pratama',
    role: UserRole.superadmin,
  );
  const manager = AuthUser(
    username: 'siti.rahma',
    fullName: 'Siti Rahma',
    role: UserRole.manager,
  );

  var seq = 0;

  setUp(() {
    now = DateTime(2026, 10, 9, 8);
    store = MockStore(clock: () => now);
    employees = MockEmployeeRepository(store, latency: Duration.zero);
    notifications = MockNotificationRepository(store, latency: Duration.zero);
    seq = 0;
  });

  EmployeeDraft draft({
    required int daysAgoJoined,
    required EmploymentStatus status,
    required int? months,
  }) {
    seq++;
    return EmployeeDraft(
      fullName: 'Tes Kontrak $seq',
      role: UserRole.staff,
      nik: '32019900000000${seq.toString().padLeft(2, '0')}',
      employeeId: 'PG-9${seq.toString().padLeft(3, '0')}',
      position: 'Staf',
      division: Division.produksiPrasasti,
      employmentStatus: status,
      contractMonths: months,
      joinDate: WorkCalendar.dateOnly(now).subtract(Duration(days: daysAgoJoined)),
      email: 'kontrak$seq@prasasti.example',
      phone: '0812900000${seq.toString().padLeft(2, '0')}',
    );
  }

  Future<String> hire({
    required int daysAgoJoined,
    required EmploymentStatus status,
    required int? months,
  }) async {
    final username = 'kontrak.tes.$seq';
    await employees.createEmployee(
      admin,
      username: username,
      draft: draft(
        daysAgoJoined: daysAgoJoined,
        status: status,
        months: months,
      ),
    );
    return username;
  }

  Future<List<AppNotification>> reminders(AuthUser user) async {
    final all = await notifications.fetch(user);
    return all
        .where((n) => n.kind == NotificationKind.contractExpiring)
        .toList();
  }

  group('WorkCalendar.periode buku 26–25', () {
    test('tanggal 26 ke atas = periode bulan berjalan', () {
      expect(
        WorkCalendar.periodStartFor(DateTime(2026, 10, 26)),
        DateTime(2026, 10, 26),
      );
      expect(
        WorkCalendar.periodEndFor(DateTime(2026, 10, 26)),
        DateTime(2026, 11, 25),
      );
    });

    test('tanggal 25 ke bawah = periode bulan sebelumnya', () {
      expect(
        WorkCalendar.periodStartFor(DateTime(2026, 10, 9)),
        DateTime(2026, 9, 26),
      );
      expect(
        WorkCalendar.periodEndFor(DateTime(2026, 10, 25)),
        DateTime(2026, 10, 25),
      );
    });

    test('batas tahun (Januari) mundur ke Desember', () {
      expect(
        WorkCalendar.periodStartFor(DateTime(2027, 1, 5)),
        DateTime(2026, 12, 26),
      );
      expect(
        WorkCalendar.periodEndFor(DateTime(2027, 1, 5)),
        DateTime(2027, 1, 25),
      );
    });

    test('berlaku selamanya (2030 dan seterusnya)', () {
      expect(
        WorkCalendar.periodStartFor(DateTime(2030, 5, 10)),
        DateTime(2030, 4, 26),
      );
      expect(
        WorkCalendar.periodEndFor(DateTime(2030, 5, 10)),
        DateTime(2030, 5, 25),
      );
      expect(
        WorkCalendar.periodStartFor(DateTime(2035, 12, 31)),
        DateTime(2035, 12, 26),
      );
      expect(
        WorkCalendar.periodEndFor(DateTime(2035, 12, 31)),
        DateTime(2036, 1, 25),
      );
    });
  });

  group('WorkCalendar.addMonths', () {
    test('tanggal dijepit ke akhir bulan bila meluap', () {
      expect(
        WorkCalendar.addMonths(DateTime(2026, 1, 31), 1),
        DateTime(2026, 2, 28),
      );
      expect(
        WorkCalendar.addMonths(DateTime(2024, 1, 31), 1),
        DateTime(2024, 2, 29),
      );
    });

    test('pindah tahun dengan benar', () {
      expect(
        WorkCalendar.addMonths(DateTime(2026, 12, 15), 2),
        DateTime(2027, 2, 15),
      );
    });
  });

  group('pengingat kontrak', () {
    test('manager & superadmin menerima saat tersisa ≤ 30 hari', () async {
      // Masuk 40 hari lalu, kontrak 2 bulan → berakhir ± 20 hari lagi.
      await hire(
        daysAgoJoined: 40,
        status: EmploymentStatus.contract,
        months: 2,
      );
      final forManager = await reminders(manager);
      final forAdmin = await reminders(admin);
      expect(forManager, hasLength(1));
      expect(forAdmin, hasLength(1));
      expect(forManager.single.body, contains('Tes Kontrak'));
      expect(forManager.single.body, contains('hari'));
    });

    test('tidak ada pengingat bila masih > 30 hari', () async {
      await hire(
        daysAgoJoined: 10,
        status: EmploymentStatus.contract,
        months: 12,
      );
      expect(await reminders(manager), isEmpty);
    });

    test('tidak ada pengingat untuk external / tanpa durasi', () async {
      await hire(
        daysAgoJoined: 300,
        status: EmploymentStatus.external,
        months: null,
      );
      expect(await reminders(manager), isEmpty);
    });

    test('kontrak yang baru lewat memicu pengingat kedaluwarsa', () async {
      // Masuk 80 hari lalu, kontrak 2 bulan → lewat ± 20 hari.
      await hire(
        daysAgoJoined: 80,
        status: EmploymentStatus.contract,
        months: 2,
      );
      final items = await notifications.fetch(manager);
      final expired = items
          .where((n) => n.kind == NotificationKind.contractExpired)
          .toList();
      expect(expired, hasLength(1));
      expect(expired.single.body, contains('lewat'));
      // Tidak ada lagi pengingat "hampir berakhir" untuknya.
      expect(
        items.where((n) => n.kind == NotificationKind.contractExpiring),
        isEmpty,
      );
    });

    test('tidak ada pengingat untuk kontrak yang sudah lama lewat', () async {
      // Lewat ± 100 hari: di luar jendela 90 hari.
      await hire(
        daysAgoJoined: 160,
        status: EmploymentStatus.contract,
        months: 2,
      );
      final items = await notifications.fetch(manager);
      expect(
        items.where((n) => n.kind == NotificationKind.contractExpired),
        isEmpty,
      );
      expect(
        items.where((n) => n.kind == NotificationKind.contractExpiring),
        isEmpty,
      );
    });

    test('tidak ada pengingat untuk akun nonaktif', () async {
      final username = await hire(
        daysAgoJoined: 40,
        status: EmploymentStatus.contract,
        months: 2,
      );
      expect(await reminders(manager), hasLength(1));
      await employees.setActive(admin, username: username, active: false);
      expect(await reminders(manager), hasLength(1));
      // Pengingat lama tetap ada (sudah dibuat), tapi tidak bertambah;
      // karyawan nonaktif tidak dihitung ulang.
      await notifications.clearAll(manager);
      expect(await reminders(manager), isEmpty);
    });

    test('tidak duplikat & ikut terbaca', () async {
      await hire(
        daysAgoJoined: 40,
        status: EmploymentStatus.contract,
        months: 2,
      );
      expect(await reminders(manager), hasLength(1));
      expect(await reminders(manager), hasLength(1));
      final unreadBefore = await notifications.unreadCount(manager);
      final all = await notifications.fetch(manager);
      await notifications.markRead(
        manager,
        id: all
            .firstWhere((n) => n.kind == NotificationKind.contractExpiring)
            .id,
      );
      expect(
        await notifications.unreadCount(manager),
        unreadBefore - 1,
      );
      // Dibaca lalu fetch lagi: tetap satu dan tetap terbaca.
      final again = await reminders(manager);
      expect(again, hasLength(1));
      expect(again.single.read, isTrue);
    });

    test('perpanjangan kontrak memicu pengingat baru', () async {
      await employees.createEmployee(
        admin,
        username: 'kontrak.panjang',
        draft: draft(
          daysAgoJoined: 40,
          status: EmploymentStatus.contract,
          months: 12,
        ),
      );
      expect(await reminders(manager), isEmpty);
      // Dipersingkat sehingga berakhir ≤ 30 hari → pengingat baru muncul.
      final current = await employees.fetchEmployee(
        admin,
        username: 'kontrak.panjang',
      );
      await employees.updateEmployee(
        admin,
        username: 'kontrak.panjang',
        draft: EmployeeDraft(
          fullName: current.fullName,
          role: current.role,
          nik: '3201990000000099',
          employeeId: current.employeeId,
          position: current.position,
          division: current.division,
          employmentStatus: current.employmentStatus,
          contractMonths: 2,
          joinDate: current.joinDate,
          email: current.email,
          phone: current.phone,
        ),
      );
      expect(await reminders(manager), hasLength(1));
    });
  });
}
