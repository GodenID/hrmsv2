import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/attendance_repository.dart';
import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/employee_repository.dart';
import 'package:hrms_app/data/event_repository.dart';
import 'package:hrms_app/data/leave_repository.dart';
import 'package:hrms_app/features/reports/report_workbook.dart';

/// Builder laporan: baris per sheet + berkas .xlsx valid.
void main() {
  EmployeeAccount employee({
    required String username,
    required String fullName,
  }) {
    return EmployeeAccount(
      username: username,
      fullName: fullName,
      role: UserRole.staff,
      employeeId: 'PG-0001',
      position: 'Staf',
      division: const Division(
        code: 'produksiPrasasti',
        label: 'Produksi Prasasti',
      ),
      employmentStatus: EmploymentStatus.permanent,
      joinDate: DateTime(2024, 1, 2),
      email: '$username@prasasti.example',
      phone: '081200000001',
      nikMasked: '3201 •••• •••• 0001',
      active: true,
      canEdit: true,
      canChangeRole: true,
      canChangeStatus: true,
      canResetPassword: true,
    );
  }

  group('summarySheet', () {
    test('baris ringkasan berurutan', () {
      final sheet = summarySheet(
        periodLabel: '26 Sep – 25 Okt 2026',
        generatedAt: DateTime(2026, 10, 9, 8),
        generatedBy: 'Andi Pratama',
        activeEmployees: 7,
        totalEmployees: 8,
        events: 5,
        pendingRequests: 3,
        approvedRequests: 10,
        rejectedRequests: 1,
      );
      expect(sheet.title, 'Ringkasan');
      expect(sheet.header, ['Keterangan', 'Nilai']);
      expect(sheet.rows[0], ['Perusahaan', 'Prasasti Group']);
      expect(sheet.rows[4], ['Karyawan aktif', 7]);
    });
  });

  group('attendanceSheet', () {
    test('satu baris per karyawan per tanggal + akhir pekan libur', () {
      final start = DateTime(2026, 9, 26); // Sabtu
      final end = DateTime(2026, 9, 28); // Senin
      final sheet = attendanceSheet(
        employees: [employee(username: 'budi', fullName: 'Budi')],
        daysByUsername: {
          'budi': [
            AttendanceDay(
              date: DateTime(2026, 9, 28),
              status: AttendanceDayStatus.onTime,
              clockIn: DateTime(2026, 9, 28, 8, 5),
              clockOut: DateTime(2026, 9, 28, 17, 5),
            ),
          ],
        },
        overtimeByUser: const {},
        start: start,
        end: end,
      );
      expect(sheet.rows, hasLength(3));
      // 26–27 Sep 2026 = Sabtu–Minggu → Libur.
      expect(sheet.rows[0][0], '26 Sep 2026');
      expect(sheet.rows[0][5], 'Libur');
      expect(sheet.rows[2][5], 'Tepat waktu');
      expect(sheet.rows[2][6], '08:05');
      expect(sheet.rows[2][11], '—');
      expect(sheet.highlightRows, isEmpty);
    });

    test('lembur tampil biru dengan jamnya', () {
      final sheet = attendanceSheet(
        employees: [employee(username: 'budi', fullName: 'Budi')],
        daysByUsername: {
          'budi': [
            AttendanceDay(
              date: DateTime(2026, 9, 28),
              status: AttendanceDayStatus.onTime,
              clockIn: DateTime(2026, 9, 28, 8, 5),
              clockOut: DateTime(2026, 9, 28, 17, 5),
            ),
          ],
        },
        overtimeByUser: {
          'budi': [
            OvertimeRequest(
              id: 'OT-1',
              date: DateTime(2026, 9, 28),
              start: DateTime(2026, 9, 28, 18),
              end: DateTime(2026, 9, 28, 21),
              reason: 'Laporan.',
              status: RequestStatus.approved,
              submittedAt: DateTime(2026, 9, 28, 21, 30),
            ),
          ],
        },
        start: DateTime(2026, 9, 28),
        end: DateTime(2026, 9, 28),
      );
      expect(sheet.rows.single[11], 'Ya');
      expect(sheet.rows.single[12], '18:00 – 21:00');
      expect(sheet.rows.single[13], '3 jam');
      expect(sheet.highlightRows, {0});
    });
  });

  group('recap sheets', () {
    test('rekap karyawan menjawab hadir, cuti, lembur, % hadir', () {
      final staff = employee(username: 'budi', fullName: 'Budi');
      final sheet = employeeRecapSheet(
        employees: [staff],
        daysByUsername: {
          'budi': [
            AttendanceDay(
              date: DateTime(2026, 10, 5), // Senin
              status: AttendanceDayStatus.onTime,
              clockIn: DateTime(2026, 10, 5, 8),
              clockOut: DateTime(2026, 10, 5, 17),
            ),
          ],
        },
        leaveByUser: const {},
        overtimeByUser: {
          'budi': [
            OvertimeRequest(
              id: 'OT-1',
              date: DateTime(2026, 10, 5),
              start: DateTime(2026, 10, 5, 18),
              end: DateTime(2026, 10, 5, 20, 30),
              reason: 'Laporan.',
              status: RequestStatus.approved,
              submittedAt: DateTime(2026, 10, 5, 21),
            ),
          ],
        },
        start: DateTime(2026, 10, 5),
        end: DateTime(2026, 10, 6),
      );
      final row = sheet.rows.single;
      expect(row[0], 'Budi');
      expect(row[3], 1); // Hadir
      expect(row[5], 0); // Cuti
      expect(row[8], '2 jam 30 menit'); // Lembur
      expect(row[9], '50%'); // 1 dari 2 hari kerja
    });

    test('rekap event memuat daftar crew', () {
      final sheet = eventRecapSheet([
        EventItem(
          id: 'EV-1',
          name: 'Acara Tes',
          company: 'PT Tes',
          category: const EventCategory(id: 'EC-1', name: 'Workshop'),
          startDate: DateTime(2026, 10, 15),
          endDate: DateTime(2026, 10, 15),
          location: 'Hall Tes',
          size: EventSize.small,
          createdBy: 'Siti',
          crew: [
            CrewMember(
              username: 'budi',
              fullName: 'Budi Santoso',
              role: CrewRole.crew,
              note: '',
              joinedAt: DateTime(2026, 9, 1),
            ),
          ],
        ),
      ]);
      expect(sheet.rows.single[8], 1);
      expect(sheet.rows.single[9], contains('Budi Santoso'));
    });
  });

  group('employeeSheet & eventSheet', () {
    test('kolom dan baris sesuai model', () {
      final sheet = employeeSheet([
        employee(username: 'budi', fullName: 'Budi Santoso'),
      ]);
      expect(sheet.header.first, 'Nama');
      expect(sheet.rows.single[0], 'Budi Santoso');
      expect(sheet.rows.single[5], contains('Tidak Tertentu'));

      final events = eventSheet([
        EventItem(
          id: 'EV-1',
          name: 'Acara Tes',
          company: 'PT Tes',
          category: const EventCategory(id: 'EC-1', name: 'Workshop'),
          entity: const EventEntity(id: 'EN-1', name: 'PT Prasasti Group'),
          startDate: DateTime(2026, 10, 15),
          endDate: DateTime(2026, 10, 16),
          location: 'Hall Tes',
          size: EventSize.medium,
          createdBy: 'Siti',
          crew: const [],
          poValue: 180000000,
        ),
      ]);
      expect(events.header, contains('Entity'));
      expect(events.rows.single[1], 'PT Tes');
      expect(events.rows.single[2], 'PT Prasasti Group');
      expect(events.rows.single[4], '15–16 Okt 2026');
    });
  });

  group('request sheets', () {
    test('cuti dan lembur memuat nama pemohon', () {
      const directory = <String, EmployeeAccount>{};
      final leaves = leaveSheet(directory, {
        'budi.santoso': [
          LeaveRequest(
            id: 'LV-1',
            type: LeaveType.annual,
            start: DateTime(2026, 10, 26),
            end: DateTime(2026, 10, 27),
            workingDays: 2,
            reason: 'Liburan keluarga.',
            status: RequestStatus.pending,
            submittedAt: DateTime(2026, 10, 6, 14),
          ),
        ],
      });
      // Tanpa direktori: tampil username apa adanya.
      expect(leaves.rows.single[0], 'budi.santoso');
      expect(leaves.rows.single[2], 'Cuti tahunan');

      final overtimes = overtimeSheet(directory, {
        'budi.santoso': [
          OvertimeRequest(
            id: 'OT-1',
            date: DateTime(2026, 10, 8),
            start: DateTime(2026, 10, 8, 18),
            end: DateTime(2026, 10, 8, 21),
            reason: 'Laporan akhir bulan.',
            status: RequestStatus.approved,
            submittedAt: DateTime(2026, 10, 8, 21, 30),
          ),
        ],
      });
      expect(overtimes.rows.single[4], '3 jam');

      // Sheet Koreksi & Luar Area dihapus: yang disetujui sudah masuk
      // sheet Absensi (jamnya), sisanya ada di sheet Cuti/Lembur.
    });
  });

  group('filter periode buku', () {
    final start = DateTime(2026, 9, 26);
    final end = DateTime(2026, 10, 25);

    EventItem event(String name, DateTime s, DateTime e) => EventItem(
      id: name,
      name: name,
      company: 'PT Tes',
      category: const EventCategory(id: 'EC-1', name: 'Workshop'),
      startDate: s,
      endDate: e,
      location: 'Hall',
      size: EventSize.small,
      createdBy: 'Siti',
      crew: const [],
    );

    test('event di dalam & bersinggungan ikut, di luar tidak', () {
      final sheet = eventSheet(
        [
          event('Dalam', DateTime(2026, 10, 1), DateTime(2026, 10, 2)),
          event('Nyebrang', DateTime(2026, 10, 24), DateTime(2026, 11, 5)),
          event('Luar', DateTime(2026, 8, 1), DateTime(2026, 8, 2)),
        ],
        start: start,
        end: end,
      );
      expect(
        sheet.rows.map((r) => r[0]).toList(),
        ['Dalam', 'Nyebrang'],
      );
    });

    test('cuti di luar periode tersaring', () {
      final sheet = leaveSheet(const {}, {
        'budi': [
          LeaveRequest(
            id: 'LV-1',
            type: LeaveType.annual,
            start: DateTime(2026, 10, 26),
            end: DateTime(2026, 10, 27),
            workingDays: 2,
            reason: 'Liburan.',
            status: RequestStatus.pending,
            submittedAt: DateTime(2026, 10, 6),
          ),
          LeaveRequest(
            id: 'LV-2',
            type: LeaveType.annual,
            start: DateTime(2026, 10, 20),
            end: DateTime(2026, 10, 21),
            workingDays: 2,
            reason: 'Keluarga.',
            status: RequestStatus.approved,
            submittedAt: DateTime(2026, 10, 1),
          ),
        ],
      }, start: start, end: end);
      expect(sheet.rows, hasLength(1));
      expect(sheet.rows.single[3], '20–21 Okt 2026');
    });

    test('lembur di luar periode tersaring', () {
      OvertimeRequest ot(DateTime d) => OvertimeRequest(
        id: 'OT-${d.day}',
        date: d,
        start: DateTime(d.year, d.month, d.day, 18),
        end: DateTime(d.year, d.month, d.day, 21),
        reason: 'Laporan.',
        status: RequestStatus.approved,
        submittedAt: d,
      );
      final sheet = overtimeSheet(const {}, {
        'budi': [ot(DateTime(2026, 10, 10)), ot(DateTime(2026, 11, 1))],
      }, start: start, end: end);
      expect(sheet.rows, hasLength(1));
      expect(sheet.rows.single[2], '10 Okt 2026');
    });

    test('tanpa periode = semua data', () {
      final sheet = eventSheet(
        [event('Luar', DateTime(2026, 8, 1), DateTime(2026, 8, 2))],
      );
      expect(sheet.rows, hasLength(1));
    });
  });

  group('buildWorkbookBytes', () {
    test('menghasilkan berkas zip xlsx yang diawali PK', () {
      final bytes = buildWorkbookBytes([
        summarySheet(
          periodLabel: '26 Sep – 25 Okt 2026',
          generatedAt: DateTime(2026, 10, 9, 8),
          generatedBy: 'Tes',
          activeEmployees: 1,
          totalEmployees: 1,
          events: 0,
          pendingRequests: 0,
          approvedRequests: 0,
          rejectedRequests: 0,
        ),
      ]);
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(1000));
      // Tanda tangan berkas ZIP.
      expect(bytes[0], 0x50);
      expect(bytes[1], 0x4B);
    });
  });
}
