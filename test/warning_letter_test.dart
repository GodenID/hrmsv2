import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/mock/mock_notification_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';
import 'package:hrms_app/data/mock/mock_warning_repository.dart';
import 'package:hrms_app/data/notification_repository.dart';
import 'package:hrms_app/data/warning_repository.dart';

/// Surat peringatan: hak akses Super Admin, eskalasi bertahap,
/// kedaluwarsa 6 bulan, tanda tangan / penolakan, sanggahan.
void main() {
  late DateTime now;
  late MockStore store;
  late MockWarningRepository warnings;
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
    warnings = MockWarningRepository(store, latency: Duration.zero);
    notifications = MockNotificationRepository(store, latency: Duration.zero);
  });

  Matcher warningError(String part) => throwsA(
    isA<AppException>().having((e) => e.message, 'message', contains(part)),
  );

  Future<WarningLetterDetail> issue({
    String username = 'budi.santoso',
    int level = 1,
    int daysAgo = 1,
    String violation = 'Terlambat masuk kerja',
    WarningSeverity severity = WarningSeverity.ringan,
  }) {
    final incident = DateTime(2026, 10, 9).subtract(Duration(days: daysAgo));
    return warnings.issue(
      superadmin,
      username: username,
      violationName: violation,
      severity: severity,
      level: level,
      incidentDate: incident,
      description: 'Karyawan terlambat masuk kerja tanpa keterangan yang jelas.',
      articleRef: 'Tata Tertib Pasal 4',
    );
  }

  group('hak akses', () {
    test('manager & staff tidak bisa menerbitkan', () async {
      for (final actor in [manager, staff]) {
        await expectLater(
          warnings.issue(
            actor,
            username: 'budi.santoso',
            violationName: 'Terlambat masuk kerja',
            severity: WarningSeverity.ringan,
            level: 1,
            incidentDate: DateTime(2026, 10, 8),
            description:
                'Karyawan terlambat masuk kerja tanpa keterangan yang jelas.',
            articleRef: 'Tata Tertib Pasal 4',
          ),
          warningError('Hanya Super Admin'),
        );
      }
    });

    test('staff tidak bisa membuka daftar semua (pakai menu sendiri)', () async {
      await expectLater(
        warnings.fetchLetters(staff),
        warningError('menu Peringatan'),
      );
    });

    test('tidak bisa menerbitkan untuk diri sendiri', () async {
      await expectLater(
        warnings.issue(
          superadmin,
          username: 'andi.pratama',
          violationName: 'Terlambat masuk kerja',
          severity: WarningSeverity.ringan,
          level: 1,
          incidentDate: DateTime(2026, 10, 8),
          description:
              'Karyawan terlambat masuk kerja tanpa keterangan yang jelas.',
          articleRef: 'Tata Tertib Pasal 4',
        ),
        warningError('diri sendiri'),
      );
    });
  });

  group('eskalasi bertahap', () {
    test('tanpa riwayat -> saran SP 1', () async {
      final s = await warnings.suggestLevel(
        superadmin,
        username: 'budi.santoso',
      );
      expect(s.suggestedLevel, 1);
      expect(s.activeCount, 0);
      expect(s.phkEligible, isFalse);
    });

    test('SP aktif -> saran naik satu tingkat', () async {
      await issue();
      var s = await warnings.suggestLevel(
        superadmin,
        username: 'budi.santoso',
      );
      expect(s.suggestedLevel, 2);
      await issue(level: 2);
      s = await warnings.suggestLevel(superadmin, username: 'budi.santoso');
      expect(s.suggestedLevel, 3);
    });

    test('SP 3 aktif + pelanggaran baru -> memenuhi syarat PHK', () async {
      await issue();
      await issue(level: 2);
      await issue(level: 3);
      final s = await warnings.suggestLevel(
        superadmin,
        username: 'budi.santoso',
      );
      expect(s.phkEligible, isTrue);
      expect(s.suggestedLevel, 3);
    });
  });

  group('masa berlaku', () {
    test('SP hidup 6 bulan sejak diterbitkan', () async {
      final detail = await issue();
      expect(detail.letter.levelLabel, 'SP 1');
      expect(detail.letter.expiresAt, DateTime(2027, 4, 9, 10, 0));
      expect(detail.letter.isActive(now), isTrue);
    });

    test('setelah kedaluwarsa -> kembali ke SP 1', () async {
      await issue();
      now = DateTime(2027, 4, 10, 10); // lewat 6 bulan + 1 hari
      final s = await warnings.suggestLevel(
        superadmin,
        username: 'budi.santoso',
      );
      expect(s.suggestedLevel, 1);
      expect(s.activeCount, 0);
    });

    test('pengingat H-30 muncul sekali untuk Super Admin', () async {
      await issue();
      now = DateTime(2027, 3, 15, 10); // 25 hari sebelum kedaluwarsa
      await warnings.fetchLetters(superadmin);
      await warnings.fetchLetters(superadmin); // panggil 2x: tetap 1
      final items = await notifications.fetch(superadmin);
      final reminders = items
          .where((n) => n.kind == NotificationKind.warningExpiring)
          .toList();
      expect(reminders, hasLength(1));
    });
  });

  group('validasi terbit', () {
    test('kejadian masa depan & terlalu lama ditolak', () async {
      await expectLater(
        warnings.issue(
          superadmin,
          username: 'budi.santoso',
          violationName: 'Terlambat masuk kerja',
          severity: WarningSeverity.ringan,
          level: 1,
          incidentDate: DateTime(2026, 10, 10),
          description:
              'Karyawan terlambat masuk kerja tanpa keterangan yang jelas.',
          articleRef: 'Tata Tertib Pasal 4',
        ),
        warningError('masa depan'),
      );
      await expectLater(
        warnings.issue(
          superadmin,
          username: 'budi.santoso',
          violationName: 'Terlambat masuk kerja',
          severity: WarningSeverity.ringan,
          level: 1,
          incidentDate: DateTime(2026, 10, 9).subtract(
            const Duration(days: 91),
          ),
          description:
              'Karyawan terlambat masuk kerja tanpa keterangan yang jelas.',
          articleRef: 'Tata Tertib Pasal 4',
        ),
        warningError('kedaluwarsa'),
      );
    });

    test('nama, uraian & tingkat divalidasi', () async {
      await expectLater(
        warnings.issue(
          superadmin,
          username: 'budi.santoso',
          violationName: 'TL',
          severity: WarningSeverity.ringan,
          level: 1,
          incidentDate: DateTime(2026, 10, 8),
          description:
              'Karyawan terlambat masuk kerja tanpa keterangan yang jelas.',
          articleRef: 'Tata Tertib Pasal 4',
        ),
        warningError('minimal 3 karakter'),
      );
      await expectLater(
        warnings.issue(
          superadmin,
          username: 'budi.santoso',
          violationName: 'Terlambat masuk kerja',
          severity: WarningSeverity.ringan,
          level: 1,
          incidentDate: DateTime(2026, 10, 8),
          description: 'Terlambat.',
          articleRef: 'Tata Tertib Pasal 4',
        ),
        warningError('minimal 20 karakter'),
      );
      await expectLater(
        warnings.issue(
          superadmin,
          username: 'budi.santoso',
          violationName: 'Terlambat masuk kerja',
          severity: WarningSeverity.ringan,
          level: 4,
          incidentDate: DateTime(2026, 10, 8),
          description:
              'Karyawan terlambat masuk kerja tanpa keterangan yang jelas.',
          articleRef: 'Tata Tertib Pasal 4',
        ),
        warningError('1, 2, atau 3'),
      );
    });

    test('karyawan & manager diberi tahu saat SP terbit', () async {
      await issue();
      final forStaff = await notifications.fetch(staff);
      expect(
        forStaff.any((n) => n.kind == NotificationKind.warningIssued),
        isTrue,
      );
      final forManager = await notifications.fetch(manager);
      expect(
        forManager.any((n) => n.kind == NotificationKind.warningIssued),
        isTrue,
      );
    });
  });

  group('tanda tangan & sanggahan', () {
    test('karyawan menandatangani sekali saja', () async {
      final detail = await issue();
      final signed = await warnings.acknowledge(
        staff,
        id: detail.letter.id,
        refused: false,
      );
      expect(signed.letter.signed, isTrue);
      expect(signed.letter.refused, isFalse);
      await expectLater(
        warnings.acknowledge(staff, id: detail.letter.id, refused: false),
        warningError('sudah ditandatangani'),
      );
    });

    test('penolakan wajib 2 saksi berbeda', () async {
      final detail = await issue();
      await expectLater(
        warnings.acknowledge(
          staff,
          id: detail.letter.id,
          refused: true,
          witness1: 'Saksi Satu',
          witness2: '',
        ),
        warningError('2 nama saksi'),
      );
      final refused = await warnings.acknowledge(
        staff,
        id: detail.letter.id,
        refused: true,
        witness1: 'Saksi Satu',
        witness2: 'Saksi Dua',
      );
      expect(refused.letter.refused, isTrue);
      expect(refused.letter.witness1, 'Saksi Satu');
    });

    test('sanggahan sekali saja, minimal jelas', () async {
      final detail = await issue();
      await expectLater(
        warnings.appeal(staff, id: detail.letter.id, text: 'Tidak setuju.'),
        warningError('minimal 20 karakter'),
      );
      final updated = await warnings.appeal(
        staff,
        id: detail.letter.id,
        text: 'Saat itu saya sedang mengantar tamu direksi ke lantai dua.',
      );
      expect(updated.letter.appeal, isNotNull);
      await expectLater(
        warnings.appeal(
          staff,
          id: detail.letter.id,
          text: 'Sanggahan kedua yang seharusnya tidak bisa masuk sama sekali.',
        ),
        warningError('sudah diajukan'),
      );
    });

    test('orang lain tidak bisa menandatangani / menyanggah', () async {
      final detail = await issue();
      await expectLater(
        warnings.acknowledge(
          manager,
          id: detail.letter.id,
          refused: false,
        ),
        warningError('tidak ditemukan'),
      );
    });
  });

  group('cakupan baca', () {
    test('manager hanya melihat timnya, karyawan melihat miliknya', () async {
      await issue(username: 'budi.santoso');
      await issue(username: 'siti.rahma');
      final forManager = await warnings.fetchLetters(manager);
      expect(
        forManager.map((d) => d.employee.username),
        contains('budi.santoso'),
      );
      expect(
        forManager.map((d) => d.employee.username),
        isNot(contains('siti.rahma')),
      );
      final mine = await warnings.fetchMyLetters(staff);
      expect(mine, hasLength(1));
      expect(mine.first.letter.levelLabel, 'SP 1');
    });
  });

  group('respons sanggahan', () {
    Future<String> appealId() async {
      final detail = await issue();
      final updated = await warnings.appeal(
        staff,
        id: detail.letter.id,
        text: 'Saat itu saya sedang mengantar tamu direksi ke lantai dua.',
      );
      return updated.letter.id;
    }

    test('hanya Super Admin, wajib ada sanggahan & catatan', () async {
      final id = await appealId();
      await expectLater(
        warnings.respondAppeal(
          manager,
          id: id,
          accept: false,
          note: 'Sanggahan tidak berdasar sama sekali.',
        ),
        warningError('Hanya Super Admin'),
      );
      await expectLater(
        warnings.respondAppeal(
          superadmin,
          id: id,
          accept: false,
          note: 'Tidak.',
        ),
        warningError('minimal 10 karakter'),
      );
      final fresh = await issue(
        violation: 'Mangkir tanpa keterangan',
        severity: WarningSeverity.sedang,
      );
      await expectLater(
        warnings.respondAppeal(
          superadmin,
          id: fresh.letter.id,
          accept: false,
          note: 'Tidak ada sanggahan yang perlu direspons.',
        ),
        warningError('Belum ada sanggahan'),
      );
    });

    test('diterima -> SP dicabut & tak dihitung eskalasi', () async {
      final id = await appealId();
      final updated = await warnings.respondAppeal(
        superadmin,
        id: id,
        accept: true,
        note: 'Terbukti sedang tugas direksi. SP dicabut.',
      );
      expect(updated.letter.voided, isTrue);
      expect(updated.letter.isActive(now), isFalse);
      final s = await warnings.suggestLevel(
        superadmin,
        username: 'budi.santoso',
      );
      expect(s.suggestedLevel, 1);
      expect(s.activeCount, 0);
      final forStaff = await notifications.fetch(staff);
      expect(
        forStaff.any(
          (n) =>
              n.kind == NotificationKind.warningIssued &&
              n.title.contains('dicabut'),
        ),
        isTrue,
      );
    });

    test('ditolak -> SP tetap berlaku; respons sekali saja', () async {
      final id = await appealId();
      final updated = await warnings.respondAppeal(
        superadmin,
        id: id,
        accept: false,
        note: 'Bukti tidak mendukung. SP tetap berlaku.',
      );
      expect(updated.letter.voided, isFalse);
      expect(updated.letter.isActive(now), isTrue);
      await expectLater(
        warnings.respondAppeal(
          superadmin,
          id: id,
          accept: true,
          note: 'Mencoba merespons kedua kalinya.',
        ),
        warningError('sudah direspons'),
      );
    });
  });
}
