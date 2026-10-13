import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/registration.dart';

void main() {
  group('RegistrationRules.validateBirthPlace', () {
    test('wajib diisi', () {
      expect(RegistrationRules.validateBirthPlace(null), isNotNull);
      expect(RegistrationRules.validateBirthPlace('  '), isNotNull);
    });

    test('minimal 2 karakter', () {
      expect(RegistrationRules.validateBirthPlace('A'), isNotNull);
      expect(RegistrationRules.validateBirthPlace('Bandung'), isNull);
    });
  });

  group('RegistrationRules.validateContractMonths', () {
    test('wajib angka 1 ke atas', () {
      const status = EmploymentStatus.contract;
      expect(
        RegistrationRules.validateContractMonths('', status),
        isNotNull,
      );
      expect(
        RegistrationRules.validateContractMonths('abc', status),
        isNotNull,
      );
      expect(
        RegistrationRules.validateContractMonths('0', status),
        isNotNull,
      );
      expect(
        RegistrationRules.validateContractMonths('12', status),
        isNull,
      );
    });

    test('batas maksimal per status', () {
      // PKWT maks 60 bulan, magang maks 12 bulan.
      expect(
        RegistrationRules.validateContractMonths(
          '60',
          EmploymentStatus.contract,
        ),
        isNull,
      );
      expect(
        RegistrationRules.validateContractMonths(
          '61',
          EmploymentStatus.contract,
        ),
        isNotNull,
      );
      expect(
        RegistrationRules.validateContractMonths(
          '12',
          EmploymentStatus.internship,
        ),
        isNull,
      );
      expect(
        RegistrationRules.validateContractMonths(
          '13',
          EmploymentStatus.internship,
        ),
        isNotNull,
      );
    });

    test('permanen & external tidak memakai durasi', () {
      for (final status in [
        EmploymentStatus.permanent,
        EmploymentStatus.external,
      ]) {
        expect(
          RegistrationRules.validateContractMonths(null, status),
          isNull,
        );
        // Diisi pun diabaikan (form tidak menampilkannya).
        expect(
          RegistrationRules.validateContractMonths('12', status),
          isNull,
        );
        expect(status.displayLabel(12), status.label);
      }
      expect(
        RegistrationRules.validateContractMonths(null, null),
        isNull,
      );
    });

    test('displayLabel menggabungkan status dan durasi', () {
      expect(
        EmploymentStatus.contract.displayLabel(12),
        'Perjanjian Kerja Waktu Tertentu · 12 bulan',
      );
      expect(
        EmploymentStatus.external.displayLabel(null),
        'External Relations',
      );
    });
  });

  group('PhoneNumbers.canonical', () {
    test('+62, 62, dan 0 dianggap nomor yang sama', () {
      const variants = [
        '0812-3456-7890',
        '+62812-3456-7890',
        '6281234567890',
        '0812 3456 7890',
      ];
      final canon = variants.map(PhoneNumbers.canonical).toSet();
      expect(canon, hasLength(1));
    });
  });
}
