import 'package:flutter/foundation.dart';

import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../auth_repository.dart';
import '../notification_repository.dart';
import 'mock_store.dart';

/// Notifikasi palsu. Dibuat oleh repository mock lain lewat
/// [MockStore.notify]; di sini hanya dibaca & ditandai dibaca.
class MockNotificationRepository implements NotificationRepository {
  MockNotificationRepository(
    this.store, {
    this.latency = const Duration(milliseconds: 300),
  });

  /// Batas jumlah notifikasi yang dikirim ke aplikasi.
  static const int maxItems = 50;

  final MockStore store;
  final Duration latency;

  @override
  Listenable get changes => store.notificationChanges;

  List<MockNotification> _list(AuthUser user) =>
      store.notifications[user.username] ?? const [];

  /// Batas pengingat kontrak: tersisa 30 hari atau kurang (termasuk yang
  /// habis hari ini). Di atas itu belum waktunya mengingatkan.
  static const int contractReminderDays = 30;

  /// Pengingat kedaluwarsa hanya untuk kontrak yang lewatnya masih segar.
  static const int contractExpiredWindowDays = 90;

  /// Membuat pengingat kedaluwarsa kontrak untuk [user] bila ia berhak
  /// mengelola karyawan yang kontraknya tersisa ≤ 30 hari. Id stabil per
  /// karyawan + tanggal berakhir sehingga tidak duplikat, ikut terbaca
  /// (markRead), dan muncul lagi bila kontrak diperpanjang (id berubah).
  void _ensureContractReminders(AuthUser user) {
    final today = WorkCalendar.dateOnly(store.now());
    for (final employee in store.accounts.values) {
      if (!employee.active) continue;
      final status = employee.employmentStatus;
      final months = employee.contractMonths;
      if (!status.requiresDuration || months == null) continue;
      final end = WorkCalendar.addMonths(
        WorkCalendar.dateOnly(employee.joinDate),
        months,
      );
      final daysLeft = end.difference(today).inDays;
      if (!store
          .reviewersFor(employee)
          .any((r) => r.username == user.username)) {
        continue;
      }
      final stamp =
          '${end.year}'
          '${end.month.toString().padLeft(2, '0')}'
          '${end.day.toString().padLeft(2, '0')}';
      final existing = store.notifications[user.username];
      bool seen(String id) =>
          existing != null && existing.any((n) => n.id == id);
      if (daysLeft >= 0 && daysLeft <= contractReminderDays) {
        final id = 'CX-${employee.username}-$stamp';
        if (seen(id)) continue;
        final leftLabel = daysLeft == 0
            ? 'berakhir hari ini'
            : 'tersisa $daysLeft hari';
        store.notify(
          user.username,
          kind: NotificationKind.contractExpiring,
          title: 'Kontrak hampir berakhir',
          body:
              '${employee.fullName} — ${status.label} $leftLabel '
              '(${DateFormatId.dayMonthYear(end)}). Perpanjang atau tindak '
              'lanjuti sebelum lewat.',
          id: id,
        );
      } else if (daysLeft < 0 &&
          -daysLeft <= contractExpiredWindowDays) {
        // Sudah lewat tetapi akun masih aktif: jaring pengaman bila
        // peringatan H-30 terlewat.
        final id = 'CXX-${employee.username}-$stamp';
        if (seen(id)) continue;
        store.notify(
          user.username,
          kind: NotificationKind.contractExpired,
          title: 'Kontrak telah berakhir',
          body:
              '${employee.fullName} — ${status.label} berakhir '
              '${DateFormatId.dayMonthYear(end)} (lewat ${-daysLeft} hari) '
              'tetapi akun masih aktif. Perpanjang, alihkan status, atau '
              'nonaktifkan akunnya.',
          id: id,
        );
      }
    }
  }

  @override
  Future<List<AppNotification>> fetch(AuthUser user) async {
    await Future<void>.delayed(latency);
    _ensureContractReminders(user);
    final sorted = [..._list(user)]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable([
      for (final n in sorted.take(maxItems)) n.toNotification(),
    ]);
  }

  @override
  Future<int> unreadCount(AuthUser user) async {
    await Future<void>.delayed(latency);
    _ensureContractReminders(user);
    return _list(user).where((n) => !n.read).length;
  }

  @override
  Future<void> markRead(AuthUser user, {required String id}) async {
    await Future<void>.delayed(latency);
    for (final n in _list(user)) {
      if (n.id == id && !n.read) {
        n.read = true;
        store.notificationChanges.ping();
        return;
      }
    }
  }

  @override
  Future<void> markAllRead(AuthUser user) async {
    await Future<void>.delayed(latency);
    var changed = false;
    for (final n in _list(user)) {
      if (!n.read) {
        n.read = true;
        changed = true;
      }
    }
    if (changed) store.notificationChanges.ping();
  }

  @override
  Future<void> clearAll(AuthUser user) async {
    await Future<void>.delayed(latency);
    final list = store.notifications[user.username];
    if (list == null || list.isEmpty) return;
    list.clear();
    store.notificationChanges.ping();
  }
}
