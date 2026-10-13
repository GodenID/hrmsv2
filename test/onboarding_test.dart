import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/mock/mock_employee_repository.dart';
import 'package:hrms_app/data/mock/mock_profile_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';
import 'package:hrms_app/data/profile_repository.dart';

/// Onboarding bulk: superadmin buat akun acak, karyawan wajib ganti
/// password + lengkapi profil saat login pertama.
void main() {
  late MockStore store;
  late MockEmployeeRepository employees;
  late MockProfileRepository profile;

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

  setUp(() {
    store = MockStore(clock: () => DateTime(2026, 10, 9, 10));
    employees = MockEmployeeRepository(store, latency: Duration.zero);
    profile = MockProfileRepository(store, latency: Duration.zero);
  });

  ProfileCompletionDraft draft(String tag, [String? nik]) =>
      ProfileCompletionDraft(
        fullName: 'Karyawan $tag',
        nik: nik ?? '3201990000000011',
        birthPlace: 'Jakarta',
        birthDate: DateTime(2000, 1, 1),
        gender: Gender.male,
        address: 'Jl. Merdeka No. 1, Jakarta Selatan',
        email: 'karyawan$tag@prasasti.example',
        phone: '081290009011',
        emergencyContact: const EmergencyContact(
          name: 'Orang Tua',
          relation: EmergencyRelation.parent,
          phone: '081290009099',
        ),
      );

  group('bulk', () {
    test('superadmin buat banyak akun acak', () async {
      final creds = await employees.createBulk(
        superadmin,
        count: 3,
        role: UserRole.staff,
        division: Division.produksiPrasasti,
        employmentStatus: EmploymentStatus.contract,
        contractMonths: 12,
      );
      expect(creds.length, 3);
      final names = creds.map((c) => c.username).toSet();
      expect(names.length, 3);
      for (final c in creds) {
        expect(c.temporaryPassword, isNotEmpty);
      }
    });

    test('manager & staff ditolak', () async {
      for (final actor in [
        const AuthUser(
          username: 'budi.santoso',
          fullName: 'Budi Santoso',
          role: UserRole.staff,
        ),
        manager,
      ]) {
        await expectLater(
          employees.createBulk(
            actor,
            count: 1,
            role: UserRole.staff,
            division: Division.produksiPrasasti,
            employmentStatus: EmploymentStatus.permanent,
          ),
          throwsA(isA<PermissionDeniedException>()),
        );
      }
    });

    test('validasi jumlah & durasi', () async {
      await expectLater(
        employees.createBulk(
          superadmin,
          count: 0,
          role: UserRole.staff,
          division: Division.produksiPrasasti,
          employmentStatus: EmploymentStatus.permanent,
        ),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        employees.createBulk(
          superadmin,
          count: 1,
          role: UserRole.staff,
          division: Division.produksiPrasasti,
          employmentStatus: EmploymentStatus.contract,
        ),
        throwsA(isA<AppException>()),
      );
    });
  });

  group('login pertama', () {
    test('akun bulk wajib ganti password + lengkapi profil', () async {
      final creds = await employees.createBulk(
        superadmin,
        count: 1,
        role: UserRole.staff,
        division: Division.produksiPrasasti,
        employmentStatus: EmploymentStatus.permanent,
      );
      final user = store.account(creds.single.username)!.toUser();
      expect(user.mustChangePassword, isTrue);
      expect(user.profileIncomplete, isTrue);

      await profile.changePassword(
        user,
        currentPassword: creds.single.temporaryPassword,
        newPassword: 'Baru@1234',
      );
      expect(store.account(creds.single.username)!.mustChangePassword, isFalse);

      await profile.completeProfile(user, draft: draft('baru'));
      final done = store.account(creds.single.username)!;
      expect(done.profileComplete, isTrue);
      expect(done.fullName, 'Karyawan baru');
      expect(done.toUser().needsOnboarding, isFalse);
    });

    test('NIK ganda antar akun ditolak', () async {
      final creds = await employees.createBulk(
        superadmin,
        count: 1,
        role: UserRole.staff,
        division: Division.produksiPrasasti,
        employmentStatus: EmploymentStatus.permanent,
      );
      final user = store.account(creds.single.username)!.toUser();
      await expectLater(
        profile.completeProfile(
          user,
          draft: draft('duplikat', '3201123456780001'),
        ),
        throwsA(isA<AppException>()),
      );
    });
  });
}
