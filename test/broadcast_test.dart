import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/mock/mock_notification_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';
import 'package:hrms_app/data/notification_repository.dart';

/// Siaran Super Admin: judul + isi bebas ke sasaran, realtime via changes.
void main() {
  late MockStore store;
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
    store = MockStore(clock: () => DateTime(2026, 10, 9, 10));
    notifications = MockNotificationRepository(store, latency: Duration.zero);
  });

  Future<void> clearAll() async {
    for (final u in [superadmin, manager, staff]) {
      await notifications.clearAll(u);
    }
  }

  group('siaran', () {
    test('ke semua karyawan termasuk pengirim', () async {
      await clearAll();
      final result = await notifications.broadcast(
        superadmin,
        title: 'Apel pagi pindah aula',
        body: 'Mulai besok apel di aula utama.',
        audience: BroadcastAudience.all,
      );
      expect(result.sent, greaterThan(0));
      expect(
        (await notifications.fetch(staff)).any(
          (n) => n.title == 'Apel pagi pindah aula',
        ),
        isTrue,
      );
      expect(
        (await notifications.fetch(manager)).any(
          (n) => n.title == 'Apel pagi pindah aula',
        ),
        isTrue,
      );
      // Pengirim ikut menerima siarannya sendiri.
      expect(
        (await notifications.fetch(superadmin)).any(
          (n) => n.title == 'Apel pagi pindah aula',
        ),
        isTrue,
      );
    });

    test('sasaran staff saja', () async {
      await clearAll();
      final result = await notifications.broadcast(
        superadmin,
        title: 'Khusus staff',
        body: 'Isi untuk staff.',
        audience: BroadcastAudience.staff,
      );
      expect(result.sent, greaterThan(0));
      expect(
        (await notifications.fetch(staff)).any(
          (n) => n.title == 'Khusus staff',
        ),
        isTrue,
      );
      expect(
        (await notifications.fetch(manager)).any(
          (n) => n.title == 'Khusus staff',
        ),
        isFalse,
      );
    });

    test('non-superadmin ditolak & validasi judul/isi', () async {
      await expectLater(
        notifications.broadcast(
          manager,
          title: 'Judul sah',
          body: 'Isi sah.',
          audience: BroadcastAudience.all,
        ),
        throwsA(isA<PermissionDeniedException>()),
      );
      await expectLater(
        notifications.broadcast(
          superadmin,
          title: 'Hi',
          body: 'Isi sah.',
          audience: BroadcastAudience.all,
        ),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        notifications.broadcast(
          superadmin,
          title: 'Judul sah',
          body: '  ',
          audience: BroadcastAudience.all,
        ),
        throwsA(isA<AppException>()),
      );
    });
  });
}
