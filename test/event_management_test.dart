import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/event_repository.dart';
import 'package:hrms_app/data/mock/mock_event_repository.dart';
import 'package:hrms_app/data/mock/mock_notification_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';
import 'package:hrms_app/data/notification_repository.dart';

/// Event: perusahaan, rentang tanggal, kategori + CRUD-nya, ambang PO
/// untuk manager, dan pengingat H-day untuk crew.
void main() {
  late DateTime now;
  late MockStore store;
  late MockEventRepository events;
  late MockNotificationRepository notifications;

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
    now = DateTime(2026, 10, 9, 8);
    store = MockStore(clock: () => now);
    events = MockEventRepository(store, latency: Duration.zero);
    notifications = MockNotificationRepository(store, latency: Duration.zero);
  });

  Future<EventItem> create({
    String name = 'Acara Tes',
    String company = 'PT Tes Maju',
    String categoryId = 'EC-3',
    DateTime? start,
    DateTime? end,
    String location = 'Hall Tes',
    int poValue = 180000000,
  }) {
    final s = start ?? now;
    return events.createEvent(
      manager,
      name: name,
      company: company,
      categoryId: categoryId,
      startDate: s,
      endDate: end ?? s,
      location: location,
      poValue: poValue,
    );
  }

  group('buat & ubah event', () {
    test('menyimpan perusahaan, rentang tanggal, dan kategori', () async {
      final item = await create(
        start: DateTime(2026, 11, 1),
        end: DateTime(2026, 11, 3),
      );
      expect(item.company, 'PT Tes Maju');
      expect(item.category.name, 'Product Launch');
      expect(item.startDate, DateTime(2026, 11, 1));
      expect(item.endDate, DateTime(2026, 11, 3));
      expect(item.isMultiDay, isTrue);
      expect(item.size, EventSize.medium);
    });

    test('event 1 hari bukan multi-hari', () async {
      final item = await create();
      expect(item.isMultiDay, isFalse);
    });

    test('validasi: perusahaan, tanggal, kategori', () async {
      await expectLater(
        create(company: 'AB'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('Nama perusahaan'),
          ),
        ),
      );
      await expectLater(
        create(start: DateTime(2026, 11, 3), end: DateTime(2026, 11, 1)),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('Tanggal selesai'),
          ),
        ),
      );
      await expectLater(
        create(categoryId: 'EC-X'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('Kategori event tidak dikenal'),
          ),
        ),
      );
    });

    test('event yang sudah selesai tetap bisa didaftari (susulan)', () async {
      final item = await create(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 2),
      );
      final updated = await events.joinEvent(
        staff,
        id: item.id,
        role: CrewRole.crew,
        note: '',
      );
      expect(
        updated.crew.any((m) => m.username == staff.username),
        isTrue,
      );
    });

    test('staff tidak bisa membuat event', () async {
      await expectLater(
        events.createEvent(
          staff,
          name: 'Acara Tes',
          company: 'PT Tes',
          categoryId: 'EC-3',
          startDate: now,
          endDate: now,
          location: 'Hall',
          poValue: 1000000,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });

  group('kategori event', () {
    test('seed berisi kategori awal', () async {
      final cats = await events.fetchCategories(staff);
      expect(
        cats.map((c) => c.name),
        containsAll(['Employee Gathering', 'Family Gathering']),
      );
    });

    test('tambah, ubah, dan tolak duplikat', () async {
      final created = await events.saveCategory(
        manager,
        name: '  Gathering Baru  ',
      );
      expect(created.name, 'Gathering Baru');
      final renamed = await events.saveCategory(
        manager,
        id: created.id,
        name: 'Gathering Baru Plus',
      );
      expect(renamed.name, 'Gathering Baru Plus');
      await expectLater(
        events.saveCategory(manager, name: 'employee gathering'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('sudah ada'),
          ),
        ),
      );
    });

    test('hapus ditolak bila dipakai event', () async {
      await expectLater(
        events.deleteCategory(manager, id: 'EC-3'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('dipakai'),
          ),
        ),
      );
    });

    test('kategori terakhir tidak bisa dihapus', () async {
      // Kosongkan dulu semua event seed agar kategorinya bebas dihapus.
      for (final e in await events.fetchEvents(manager)) {
        await events.deleteEvent(manager, id: e.id);
      }
      for (final id in ['EC-1', 'EC-2', 'EC-3', 'EC-4', 'EC-5']) {
        await events.deleteCategory(manager, id: id);
      }
      expect(
        (await events.fetchCategories(manager)).map((c) => c.id),
        ['EC-6'],
      );
      await expectLater(
        events.deleteCategory(manager, id: 'EC-6'),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('Minimal satu kategori'),
          ),
        ),
      );
    });

    test('staff tidak bisa mengelola kategori', () async {
      await expectLater(
        events.saveCategory(staff, name: 'Coba'),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        events.deleteCategory(staff, id: 'EC-2'),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });

  group('ambang PO', () {
    test('manager boleh mengubah ambang', () async {
      final updated = await events.updateThresholds(
        manager,
        const EventThresholds(smallMax: 1, mediumMax: 2, largeMax: 3),
      );
      expect(updated.smallMax, 1);
    });

    test('staff tetap ditolak', () async {
      await expectLater(
        events.updateThresholds(
          staff,
          const EventThresholds(smallMax: 1, mediumMax: 2, largeMax: 3),
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });

  group('pengingat H-day', () {
    Future<List<AppNotification>> todayReminders(AuthUser user) async {
      await events.fetchEvents(user);
      final all = await notifications.fetch(user);
      return all.where((n) => n.kind == NotificationKind.eventToday).toList();
    }

    test('crew diingatkan saat event berlangsung', () async {
      final item = await create(
        name: 'Acara Hari Ini',
        start: now,
        end: now.add(const Duration(days: 1)),
      );
      await events.joinEvent(
        staff,
        id: item.id,
        role: CrewRole.crew,
        note: '',
      );
      final got = await todayReminders(staff);
      expect(got, hasLength(1));
      expect(got.single.title, contains('Acara Hari Ini'));
      expect(got.single.body, contains('PT Tes Maju'));
    });

    test('bukan crew tidak diingatkan', () async {
      final item = await create(name: 'Acara Hari Ini', start: now, end: now);
      await events.joinEvent(
        staff,
        id: item.id,
        role: CrewRole.crew,
        note: '',
      );
      const other = AuthUser(
        username: 'dewi.lestari',
        fullName: 'Dewi Lestari',
        role: UserRole.staff,
      );
      expect(await todayReminders(other), isEmpty);
    });

    test('sekali sehari, tanpa duplikat', () async {
      final item = await create(
        start: now,
        end: now.add(const Duration(days: 2)),
      );
      await events.joinEvent(
        staff,
        id: item.id,
        role: CrewRole.crew,
        note: '',
      );
      expect(await todayReminders(staff), hasLength(1));
      expect(await todayReminders(staff), hasLength(1));
      // Besok (masih berlangsung): pengingat hari kedua muncul.
      now = now.add(const Duration(days: 1));
      expect(await todayReminders(staff), hasLength(2));
      // Lewat event: tidak ada yang baru.
      now = now.add(const Duration(days: 5));
      expect(await todayReminders(staff), hasLength(2));
    });
  });
}
