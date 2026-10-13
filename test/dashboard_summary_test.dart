import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/attendance_repository.dart';
import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/event_repository.dart';
import 'package:hrms_app/features/dashboard/widgets/summary_section.dart';

/// Logika ringkasan Beranda: hitung hadir & event terdekat.
void main() {
  AttendanceDay day(int day, AttendanceDayStatus status, [int month = 10]) =>
      AttendanceDay(
        date: DateTime(2026, month, day),
        status: status,
      );

  EventItem event(String id, DateTime start, DateTime end) => EventItem(
    id: id,
    name: 'Event $id',
    company: 'Klien',
    category: const EventCategory(id: 'C1', name: 'Umum'),
    startDate: start,
    endDate: end,
    location: 'Venue',
    size: EventSize.small,
    createdBy: 'andi.pratama',
    crew: const [],
  );

  group('countPresentInRange', () {
    test('ada jam clock in dihitung (sama dengan strip Absensi)', () {
      final days = [
        day(1, AttendanceDayStatus.onTime),
        day(2, AttendanceDayStatus.late),
        day(3, AttendanceDayStatus.incomplete),
        day(4, AttendanceDayStatus.inProgress),
        day(5, AttendanceDayStatus.absent),
        day(6, AttendanceDayStatus.leave),
      ];
      final start = DateTime(2026, 9, 26);
      final end = DateTime(2026, 10, 25);
      expect(countPresentInRange(days, start, end), 4);
    });

    test('di luar periode tutup buku tidak dihitung', () {
      final days = [
        day(20, AttendanceDayStatus.onTime, 9),
        day(26, AttendanceDayStatus.onTime, 9),
      ];
      // Oktober: periode berjalan 26 Sep–25 Okt.
      final start = DateTime(2026, 9, 26);
      final end = DateTime(2026, 10, 25);
      expect(countPresentInRange(days, start, end), 1);
    });

    test('kosong = 0', () {
      expect(
        countPresentInRange(
          const [],
          DateTime(2026, 9, 26),
          DateTime(2026, 10, 25),
        ),
        0,
      );
    });
  });

  group('nearestUpcomingEvent', () {
    final now = DateTime(2026, 10, 9, 10);

    test('melewati yang sudah selesai, mengambil yang paling dekat', () {
      final events = [
        event('C', DateTime(2026, 10, 20), DateTime(2026, 10, 21)),
        event('A', DateTime(2026, 10, 1), DateTime(2026, 10, 2)),
        event('B', DateTime(2026, 10, 12), DateTime(2026, 10, 12)),
      ];
      expect(nearestUpcomingEvent(events, now)?.id, 'B');
    });

    test('event yang sedang berjalan ikut dihitung', () {
      final events = [
        event('A', DateTime(2026, 10, 8), DateTime(2026, 10, 10)),
      ];
      expect(nearestUpcomingEvent(events, now)?.id, 'A');
    });

    test('tidak ada = null', () {
      expect(nearestUpcomingEvent(const [], now), isNull);
      expect(
        nearestUpcomingEvent(
          [event('A', DateTime(2026, 10, 1), DateTime(2026, 10, 2))],
          now,
        ),
        isNull,
      );
    });
  });

  // Referensi agar import auth_repository dipakai (tipe pengguna ringkasan).
  test('tipe pengguna tersedia', () {
    const user = AuthUser(
      username: 'budi.santoso',
      fullName: 'Budi Santoso',
      role: UserRole.staff,
    );
    expect(user.role, UserRole.staff);
  });
}
