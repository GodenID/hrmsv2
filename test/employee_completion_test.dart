import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/employee_repository.dart';
import 'package:hrms_app/data/mock/mock_auth_repository.dart';
import 'package:hrms_app/data/mock/mock_employee_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';

/// Konsistensi akun daftar mandiri vs lengkapi Super Admin:
/// pendaftar lahir tanpa atasan langsung, Super Admin yang mengisinya
/// lewat Ubah data karyawan.
void main() {
  late DateTime now;
  late MockStore store;
  late MockAuthRepository auth;
  late MockEmployeeRepository employees;

  const superadmin = AuthUser(
    username: 'andi.pratama',
    fullName: 'Andi Pratama',
    role: UserRole.superadmin,
  );

  RegistrationDraft draft() => RegistrationDraft(
    username: 'pendaftar.baru',
    password: 'Baru@1234',
    fullName: 'Pendaftar Baru',
    nik: '3174050501000001', // cocok: 05-01-2000, laki-laki.
    birthPlace: 'Jakarta',
    birthDate: DateTime(2000, 1, 5),
    gender: Gender.male,
    address: 'Jl. Merdeka No. 10, Jakarta',
    email: 'pendaftar.baru@prasasti.example',
    phone: '0819-9999-8888',
    emergencyContact: const EmergencyContact(
      name: 'Kontak Darurat',
      relation: EmergencyRelation.sibling,
      phone: '0819-9999-8889',
    ),
    division: Division.produksiPrasasti,
    employmentStatus: EmploymentStatus.contract,
    contractMonths: 12,
    privacyConsent: true,
  );

  setUp(() {
    now = DateTime(2026, 10, 9, 10);
    store = MockStore(clock: () => now);
    auth = MockAuthRepository(store, latency: Duration.zero);
    employees = MockEmployeeRepository(store, latency: Duration.zero);
  });

  test('akun daftar mandiri lahir tanpa atasan langsung', () async {
    final created = await auth.register(draft());
    expect(created.role, UserRole.staff);
    final account = await employees.fetchEmployee(
      superadmin,
      username: created.username,
    );
    expect(account.managerUsername, isNull);
  });

  test('superadmin melengkapi atasan lewat ubah data', () async {
    final created = await auth.register(draft());
    final current = await employees.fetchEmployee(
      superadmin,
      username: created.username,
    );
    final updated = await employees.updateEmployee(
      superadmin,
      username: current.username,
      draft: EmployeeDraft(
        fullName: current.fullName,
        role: current.role,
        nik: current.nik!,
        employeeId: current.employeeId,
        position: 'Crew Event',
        division: current.division,
        employmentStatus: current.employmentStatus,
        contractMonths: current.contractMonths,
        joinDate: current.joinDate,
        email: current.email,
        phone: current.phone,
        managerUsername: 'siti.rahma',
      ),
    );
    expect(updated.managerUsername, 'siti.rahma');
    expect(updated.managerName, 'Siti Rahma');
  });

  test('atasan harus aktif & bukan diri sendiri', () async {
    final created = await auth.register(draft());
    final current = await employees.fetchEmployee(
      superadmin,
      username: created.username,
    );
    EmployeeDraft withManager(String? manager) => EmployeeDraft(
      fullName: current.fullName,
      role: current.role,
      nik: current.nik!,
      employeeId: current.employeeId,
      position: current.position,
      division: current.division,
      employmentStatus: current.employmentStatus,
      contractMonths: current.contractMonths,
      joinDate: current.joinDate,
      email: current.email,
      phone: current.phone,
      managerUsername: manager,
    );
    await expectLater(
      employees.updateEmployee(
        superadmin,
        username: current.username,
        draft: withManager('tidak.ada'),
      ),
      throwsA(
        isA<AppException>().having(
          (e) => e.message,
          'message',
          contains('masih aktif'),
        ),
      ),
    );
    await expectLater(
      employees.updateEmployee(
        superadmin,
        username: current.username,
        draft: withManager(current.username),
      ),
      throwsA(
        isA<AppException>().having(
          (e) => e.message,
          'message',
          contains('dirinya sendiri'),
        ),
      ),
    );
  });
}
