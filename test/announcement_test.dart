import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/announcement_repository.dart';
import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/mock/mock_announcement_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';

/// Pengumuman: jadwal terbit, kedaluwarsa, sematan, target divisi,
/// dan lampiran.
void main() {
  late DateTime now;
  late MockStore store;
  late MockAnnouncementRepository announcements;

  const admin = AuthUser(
    username: 'andi.pratama',
    fullName: 'Andi Pratama',
    role: UserRole.superadmin,
  );
  const managerHrIt = AuthUser(
    username: 'siti.rahma',
    fullName: 'Siti Rahma',
    role: UserRole.manager,
  );
  const staffProduksi = AuthUser(
    username: 'budi.santoso',
    fullName: 'Budi Santoso',
    role: UserRole.staff,
  );

  setUp(() {
    now = DateTime(2026, 10, 9, 8);
    store = MockStore(clock: () => now);
    announcements = MockAnnouncementRepository(store, latency: Duration.zero);
  });

  Future<Announcement> create({
    String title = 'Pengumuman tes',
    DateTime? publishAt,
    DateTime? expiresAt,
    bool pinned = false,
    List<Division> targets = const [],
  }) {
    return announcements.create(
      actor: admin,
      draft: AnnouncementDraft(
        title: title,
        body: 'Isi pengumuman yang cukup panjang untuk validasi.',
        publishAt: publishAt,
        expiresAt: expiresAt,
        pinned: pinned,
        targetDivisions: targets,
      ),
    );
  }

  Future<List<String>> feedTitles(AuthUser user) async {
    final feed = await announcements.fetchFeed(user);
    return [for (final f in feed) f.announcement.title];
  }

  group('jadwal & kedaluwarsa', () {
    test('terjadwal tersembunyi sampai waktunya tiba', () async {
      await create(
        title: 'Besok terbit',
        publishAt: DateTime(2026, 10, 10, 9),
      );
      expect(await feedTitles(staffProduksi), isNot(contains('Besok terbit')));
      now = DateTime(2026, 10, 10, 10);
      expect(await feedTitles(staffProduksi), contains('Besok terbit'));
    });

    test('kedaluwarsa hilang dari feed', () async {
      await create(
        title: 'Promo kilat',
        expiresAt: DateTime(2026, 10, 9, 9, 59),
      );
      expect(await feedTitles(staffProduksi), contains('Promo kilat'));
      now = DateTime(2026, 10, 9, 10);
      expect(await feedTitles(staffProduksi), isNot(contains('Promo kilat')));
    });

    test('kedaluwarsa sebelum terbit ditolak', () async {
      await expectLater(
        create(
          publishAt: DateTime(2026, 10, 12, 9),
          expiresAt: DateTime(2026, 10, 11),
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('kedaluwarsa'),
          ),
        ),
      );
    });
  });

  group('sematan & target', () {
    test('disematkan tampil paling atas', () async {
      await create(title: 'Biasa saja');
      await create(title: 'Penting disemat', pinned: true);
      final titles = await feedTitles(staffProduksi);
      expect(titles.indexOf('Penting disemat'), 0);
    });

    test('target divisi menyaring pembaca', () async {
      await create(
        title: 'Khusus HR & IT',
        targets: [Division.hrIt],
      );
      expect(await feedTitles(managerHrIt), contains('Khusus HR & IT'));
      // Budi (Produksi Prasasti) tidak melihatnya.
      expect(
        await feedTitles(staffProduksi),
        isNot(contains('Khusus HR & IT')),
      );
    });
  });

  group('validasi', () {
    test('judul, isi, dan lampiran divalidasi server', () async {
      await expectLater(
        announcements.create(
          actor: admin,
          draft: const AnnouncementDraft(title: 'Abc', body: 'Isi cukup panjang.'),
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('Judul'),
          ),
        ),
      );
      await expectLater(
        announcements.create(
          actor: admin,
          draft: AnnouncementDraft(
            title: 'Judul valid',
            body: 'Isi pengumuman yang cukup panjang.',
            attachments: [
              for (var i = 0; i < 4; i++)
                AnnouncementAttachment(name: 'file$i.pdf', sizeBytes: 1000),
            ],
          ),
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('Maksimal 3 lampiran'),
          ),
        ),
      );
      await expectLater(
        announcements.create(
          actor: admin,
          draft: const AnnouncementDraft(
            title: 'Judul valid',
            body: 'Isi pengumuman yang cukup panjang.',
            attachments: [
              AnnouncementAttachment(name: 'data.exe', sizeBytes: 1000),
            ],
          ),
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('Format file'),
          ),
        ),
      );
    });

    test('staff tidak bisa membuat pengumuman', () async {
      await expectLater(
        announcements.create(
          actor: staffProduksi,
          draft: const AnnouncementDraft(
            title: 'Judul valid',
            body: 'Isi pengumuman yang cukup panjang.',
          ),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });
}
