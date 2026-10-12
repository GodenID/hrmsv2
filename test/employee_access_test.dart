import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/employee_repository.dart';
import 'package:hrms_app/data/mock/mock_employee_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';

/// Karyawan: semua role bisa melihat, mutasi hanya Super Admin, dan akun
/// Super Admin disembunyikan dari non-Super Admin.
void main() {
  late MockStore store;
  late MockEmployeeRepository employees;

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
    store = MockStore(clock: () => DateTime(2026, 10, 9, 10));
    employees = MockEmployeeRepository(store, latency: Duration.zero);
  });

  EmployeeDraft draft(String tag) => EmployeeDraft(
        fullName: 'Tes $tag',
        role: UserRole.staff,
        nik: '3201990000000011',
        employeeId: 'PG-9001',
        position: 'Staf',
        division: Division.produksiPrasasti,
        employmentStatus: EmploymentStatus.permanent,
        joinDate: DateTime(2026, 1, 5),
        email: 'tesdstaff@prasasti.example',
        phone: '081290009001',
      );

  group('lihat', () {
    test('staff & manager bisa ambil daftar', () async {
      for (final actor in [staff, manager]) {
        final list = await employees.fetchEmployees(actor);
        expect(list, isNotEmpty);
        // Tanpa tulisan superadmin untuk non-superadmin.
        expect(
          list.any((e) => e.role == UserRole.superadmin),
          isFalse,
        );
      }
    });

    test('superadmin tetap melihat semua termasuk superadmin', () async {
      final list = await employees.fetchEmployees(superadmin);
      expect(
        list.any((e) => e.role == UserRole.superadmin),
        isTrue,
      );
    });

    test('detail superadmin 404 untuk staff/manager', () async {
      for (final actor in [staff, manager]) {
        await expectLater(
          employees.fetchEmployee(actor, username: 'andi.pratama'),
          throwsA(isA<AppException>()),
        );
      }
      final me = await employees.fetchEmployee(
        superadmin,
        username: 'andi.pratama',
      );
      expect(me.role, UserRole.superadmin);
    });
  });

  group('mutasi', () {
    test('manager & staff tidak bisa tambah karyawan', () async {
      for (final actor in [staff, manager]) {
        await expectLater(
          employees.createEmployee(actor, username: 'baru.satu', draft: draft('satu')),
          throwsA(isA<PermissionDeniedException>()),
        );
      }
    });

    test('manager tidak bisa ubah / nonaktifkan / reset password', () async {
      await expectLater(
        employees.updateEmployee(
          manager,
          username: 'budi.santoso',
          draft: draft('dua'),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        employees.setActive(manager, username: 'budi.santoso', active: false),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        employees.resetPassword(manager, username: 'budi.santoso'),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('flag aksi mati untuk non-superadmin', () async {
      final mine = await employees.fetchEmployee(staff, username: 'budi.santoso');
      expect(mine.canEdit, isFalse);
      expect(mine.canResetPassword, isFalse);
      expect(mine.canChangeStatus, isFalse);
    });
  });
}
