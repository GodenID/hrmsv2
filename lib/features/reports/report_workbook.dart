import 'package:excel/excel.dart';

import '../../core/utils/date_format_id.dart';
import '../../core/utils/currency_format.dart';
import '../../core/utils/work_calendar.dart';
import '../../data/attendance_repository.dart';
import '../../data/employee_repository.dart';
import '../../data/event_repository.dart';
import '../../data/leave_repository.dart';
import '../events/event_presentation.dart' show crewAttendanceDays;

/// Jenis laporan yang bisa dipilih & diekspor.
enum ReportKind {
  all('Semua (all-in-one)'),
  attendance('Absensi'),
  events('Event'),
  requests('Pengajuan'),
  employees('Karyawan');

  const ReportKind(this.label);

  final String label;
}

/// Satu sheet: judul + header + baris data polos (diuji tanpa excel).
class ReportSheetData {
  const ReportSheetData({
    required this.title,
    required this.header,
    required this.rows,
    this.highlightRows = const {},
    this.navyRows = const {},
    this.statusCellColors = const {},
  });

  final String title;
  final List<String> header;
  final List<List<Object?>> rows;

  /// Indeks baris (0-based, tanpa header) yang diberi fill biru muda,
  /// mis. baris berlembur di sheet Absensi.
  final Set<int> highlightRows;

  /// Baris lembur Minggu: biru laut, teks putih.
  final Set<int> navyRows;

  /// Warna khusus kolom Kehadiran (indeks 5): baris -> hex warna.
  final Map<int, String> statusCellColors;
}

/// Merakit [sheets] menjadi berkas .xlsx (header tebal + warna).
/// Mengembalikan null bila gagal disimpan.
List<int>? buildWorkbookBytes(List<ReportSheetData> sheets) {
  final excel = Excel.createExcel();
  for (final sheet in sheets) {
    final grid = excel[sheet.title];
    grid.appendRow([
      for (final h in sheet.header) TextCellValue(h),
    ]);
    for (final row in sheet.rows) {
      grid.appendRow([for (final v in row) _cell(v)]);
    }
    final headerStyle = CellStyle(
      bold: true,
      fontSize: 11,
      backgroundColorHex: ExcelColor.fromHexString('#D9E8E3'),
      fontColorHex: ExcelColor.fromHexString('#0F2A24'),
    );
    for (var c = 0; c < sheet.header.length; c++) {
      grid.updateCell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        TextCellValue(sheet.header[c]),
        cellStyle: headerStyle,
      );
      grid.setColumnAutoFit(c);
    }
    final highlightStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#DCE9FD'),
    );
    for (final r in sheet.highlightRows) {
      if (r < 0 || r >= sheet.rows.length) continue;
      final row = sheet.rows[r];
      for (var c = 0; c < sheet.header.length && c < row.length; c++) {
        grid.updateCell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
          _cell(row[c]),
          cellStyle: highlightStyle,
        );
      }
    }
    final navyStyle = CellStyle(
      backgroundColorHex: ExcelColor.fromHexString('#123C69'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    );
    for (final r in sheet.navyRows) {
      if (r < 0 || r >= sheet.rows.length) continue;
      final row = sheet.rows[r];
      for (var c = 0; c < sheet.header.length && c < row.length; c++) {
        grid.updateCell(
          CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
          _cell(row[c]),
          cellStyle: navyStyle,
        );
      }
    }
    for (final entry in sheet.statusCellColors.entries) {
      final r = entry.key;
      if (r < 0 || r >= sheet.rows.length || sheet.rows[r].length <= 5) {
        continue;
      }
      grid.updateCell(
        CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: r + 1),
        _cell(sheet.rows[r][5]),
        cellStyle: CellStyle(
          backgroundColorHex: ExcelColor.fromHexString(entry.value),
          fontColorHex: ExcelColor.fromHexString('#0F2A24'),
        ),
      );
    }
  }
  if (sheets.isNotEmpty) excel.delete('Sheet1');
  return excel.save();
}

CellValue? _cell(Object? value) => switch (value) {
  null => null,
  int v => IntCellValue(v),
  double v => DoubleCellValue(v),
  bool v => BoolCellValue(v),
  _ => TextCellValue('$value'),
};

String _date(DateTime d) => DateFormatId.shortDate(d);
String _dateTime(DateTime d) => DateFormatId.shortDateTime(d);
String _time(DateTime? d) => d == null ? '—' : DateFormatId.time(d);

/// Rentang [start]–[end] bersinggungan dengan periode buku atau tidak.
/// Periode null = tanpa filter (semua data).
bool overlapsPeriod(
  DateTime start,
  DateTime end,
  DateTime? periodStart,
  DateTime? periodEnd,
) {
  if (periodStart == null || periodEnd == null) return true;
  final s = WorkCalendar.dateOnly(start);
  final e = WorkCalendar.dateOnly(end);
  return !e.isBefore(periodStart) && !s.isAfter(periodEnd);
}

/// Satu tanggal berada dalam periode buku atau tidak.
bool inPeriod(DateTime date, DateTime? periodStart, DateTime? periodEnd) =>
    overlapsPeriod(date, date, periodStart, periodEnd);

/// Baris ringkasan: label + nilai.
ReportSheetData summarySheet({
  required String periodLabel,
  required DateTime generatedAt,
  required String generatedBy,
  required int activeEmployees,
  required int totalEmployees,
  required int events,
  required int pendingRequests,
  required int approvedRequests,
  required int rejectedRequests,
}) {
  return ReportSheetData(
    title: 'Ringkasan',
    header: const ['Keterangan', 'Nilai'],
    rows: [
      ['Perusahaan', 'Prasasti Group'],
      ['Periode buku', periodLabel],
      ['Dibuat', _dateTime(generatedAt)],
      ['Dibuat oleh', generatedBy],
      ['Karyawan aktif', activeEmployees],
      ['Total akun', totalEmployees],
      ['Event', events],
      ['Pengajuan menunggu', pendingRequests],
      ['Pengajuan disetujui', approvedRequests],
      ['Pengajuan ditolak', rejectedRequests],
    ],
  );
}

ReportSheetData attendanceSheet({
  required List<EmployeeAccount> employees,
  required Map<String, List<AttendanceDay>> daysByUsername,
  required Map<String, List<OvertimeRequest>> overtimeByUser,
  required DateTime start,
  required DateTime end,
}) {
  String statusOf(AttendanceDay? day, DateTime date) {
    if (day == null) {
      final weekend =
          date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
      return weekend ? 'Libur' : 'Tidak ada data';
    }
    return day.status.label;
  }

  String? statusColorOf(AttendanceDay? day) {
    if (day == null) return null;
    if (day.status == AttendanceDayStatus.late) return '#F8CBAD';
    final leave = day.leave;
    if (leave == null) return null;
    return leave.type == LeaveType.sick ? '#FCDCEA' : '#D6E4FD';
  }

  List<OvertimeRequest> overtimeFor(String username, DateTime day) => [
        for (final o in overtimeByUser[username] ?? const <OvertimeRequest>[])
          if (o.status == RequestStatus.approved &&
              o.date.year == day.year &&
              o.date.month == day.month &&
              o.date.day == day.day)
            o,
      ];

  final rows = <List<Object?>>[];
  final highlight = <int>{};
  final navyRows = <int>{};
  final statusColors = <int, String>{};
  final sorted = [...employees]
    ..sort((a, b) => a.fullName.compareTo(b.fullName));
  for (final e in sorted) {
    final byDate = <String, AttendanceDay>{
      for (final d in daysByUsername[e.username] ?? const <AttendanceDay>[])
        '${d.date.year}-${d.date.month}-${d.date.day}': d,
    };
    var day = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
    while (!day.isAfter(last)) {
      final info =
          byDate['${day.year}-${day.month}-${day.day}'];
      final overtimes = overtimeFor(e.username, day);
      if (overtimes.isNotEmpty) highlight.add(rows.length);
      if (overtimes.any((o) => o.slot == OvertimeSlot.sunday)) {
        navyRows.add(rows.length);
      }
      final color = statusColorOf(info);
      if (color != null) statusColors[rows.length] = color;
      final overtimeMinutes = overtimes.fold<Duration>(
        Duration.zero,
        (total, o) => total + o.duration,
      );
      rows.add([
        _date(day),
        e.fullName,
        e.username,
        e.employeeId,
        e.division.label,
        statusOf(info, day),
        _time(info?.clockIn),
        _time(info?.clockOut),
        info?.worked == null
            ? '—'
            : DateFormatId.duration(info!.worked!),
        info?.clockInLocation ?? '—',
        info?.clockOutLocation ?? '—',
        overtimes.isEmpty ? '—' : 'Ya',
        overtimes.isEmpty
            ? '—'
            : overtimes.map((o) => o.timeRangeLabel).join('; '),
        overtimeMinutes == Duration.zero
            ? '—'
            : DateFormatId.duration(overtimeMinutes),
      ]);
      day = DateTime(day.year, day.month, day.day + 1);
    }
  }
  return ReportSheetData(
    title: 'Absensi',
    header: const [
      'Tanggal',
      'Nama',
      'Username',
      'ID',
      'Divisi',
      'Kehadiran',
      'Clock in',
      'Clock out',
      'Durasi',
      'Lokasi in',
      'Lokasi out',
      'Lembur',
      'Jam lembur',
      'Durasi lembur',
    ],
    rows: rows,
    highlightRows: highlight,
    navyRows: navyRows,
    statusCellColors: statusColors,
  );
}

ReportSheetData employeeSheet(List<EmployeeAccount> employees) {
  final sorted = [...employees]
    ..sort((a, b) => a.fullName.compareTo(b.fullName));
  return ReportSheetData(
    title: 'Karyawan',
    header: const [
      'Nama',
      'Username',
      'ID',
      'Jabatan',
      'Divisi',
      'Status kepegawaian',
      'Role',
      'Bergabung',
      'Email',
      'Telepon',
      'Aktif',
    ],
    rows: [
      for (final e in sorted)
        [
          e.fullName,
          e.username,
          e.employeeId,
          e.position,
          e.division.label,
          e.employmentStatus.displayLabel(e.contractMonths),
          e.role.label,
          _date(e.joinDate),
          e.email,
          e.phone,
          e.active ? 'Ya' : 'Tidak',
        ],
    ],
  );
}

ReportSheetData eventSheet(
  List<EventItem> events, {
  DateTime? start,
  DateTime? end,
}) {
  final filtered = [
    for (final e in events)
      if (overlapsPeriod(e.startDate, e.endDate, start, end)) e,
  ];
  final sorted = [...filtered]
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
  return ReportSheetData(
    title: 'Event',
    header: const [
      'Nama',
      'Perusahaan',
      'Entity',
      'Kategori',
      'Tanggal',
      'Lokasi',
      'Ukuran',
      'Nilai PO',
      'Jumlah crew',
    ],
    rows: [
      for (final e in sorted)
        [
          e.name,
          e.company,
          e.entity?.name ?? '—',
          e.category.name,
          DateFormatId.dateRange(e.startDate, e.endDate),
          e.location,
          e.size.label,
          e.poValue == null ? '—' : Rupiah.format(e.poValue!),
          e.crew.length,
        ],
    ],
  );
}

ReportSheetData eventCrewSheet(
  List<EventItem> events, {
  DateTime? start,
  DateTime? end,
}) {
  final filtered = [
    for (final e in events)
      if (overlapsPeriod(e.startDate, e.endDate, start, end)) e,
  ];
  final sorted = [...filtered]
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
  final rows = <List<Object?>>[];
  for (final e in sorted) {
    for (final m in e.crew) {
      final days = crewAttendanceDays(e, m);
      rows.add([
        e.name,
        DateFormatId.dateRange(e.startDate, e.endDate),
        m.fullName,
        m.role.label,
        m.note.isEmpty ? '—' : m.note,
        days.length,
        days.map((d) => DateFormatId.shortDate(d)).join(', '),
      ]);
    }
  }
  return ReportSheetData(
    title: 'Crew Event',
    header: const [
      'Event',
      'Tanggal',
      'Nama',
      'Bagian',
      'Keterangan',
      'Hari ikut',
      'Tanggal ikut',
    ],
    rows: rows,
  );
}

ReportSheetData leaveSheet(
  Map<String, EmployeeAccount> directory,
  Map<String, List<LeaveRequest>> byUser, {
  DateTime? start,
  DateTime? end,
}) {
  String nameOf(String username) =>
      directory[username]?.fullName ?? username;
  final flat = <({String username, LeaveRequest request})>[
    for (final entry in byUser.entries)
      for (final r in entry.value)
        if (overlapsPeriod(r.start, r.end, start, end))
          (username: entry.key, request: r),
  ]..sort((a, b) => b.request.submittedAt.compareTo(a.request.submittedAt));
  final leaveRows = <List<Object?>>[
    for (final e in flat)
      [
        nameOf(e.username),
        e.username,
        e.request.type.label,
        DateFormatId.dateRange(e.request.start, e.request.end),
        e.request.workingDays,
        e.request.reason,
        e.request.status.label,
        _dateTime(e.request.submittedAt),
        e.request.reviewedBy ?? '—',
        e.request.reviewerNote ?? '—',
      ],
  ];
  return ReportSheetData(
    title: 'Cuti',
    header: const [
      'Nama',
      'Username',
      'Jenis',
      'Tanggal',
      'Hari kerja',
      'Alasan',
      'Status',
      'Diajukan',
      'Diproses oleh',
      'Catatan',
    ],
    rows: leaveRows,
  );
}

ReportSheetData overtimeSheet(
  Map<String, EmployeeAccount> directory,
  Map<String, List<OvertimeRequest>> byUser, {
  DateTime? start,
  DateTime? end,
}) {
  String nameOf(String username) =>
      directory[username]?.fullName ?? username;
  final flat = <({String username, OvertimeRequest request})>[
    for (final entry in byUser.entries)
      for (final r in entry.value)
        if (inPeriod(r.date, start, end)) (username: entry.key, request: r),
  ]..sort((a, b) => b.request.submittedAt.compareTo(a.request.submittedAt));
  final navyRows = <int>{
    for (var i = 0; i < flat.length; i++)
      if (flat[i].request.slot == OvertimeSlot.sunday) i,
  };
  final overtimeRows = <List<Object?>>[
    for (final e in flat)
      [
        nameOf(e.username),
        e.username,
        _date(e.request.date),
        e.request.timeRangeLabel,
        e.request.durationLabel,
        e.request.reason,
        e.request.status.label,
        _dateTime(e.request.submittedAt),
        e.request.reviewedBy ?? '—',
        e.request.reviewerNote ?? '—',
      ],
  ];
  return ReportSheetData(
    title: 'Lembur',
    header: const [
      'Nama',
      'Username',
      'Tanggal',
      'Jam',
      'Durasi',
      'Keterangan',
      'Status',
      'Diajukan',
      'Diproses oleh',
      'Catatan',
    ],
    rows: overtimeRows,
    navyRows: navyRows,
  );
}

/// Rekap per karyawan: jawaban langsung atas "absen bulan ini si ini
/// berapa, cutinya berapa". % Hadir = hadir / hari kerja wajib (hari kerja
/// sejak bergabung dikurangi cuti/izin/sakit yang disetujui).
ReportSheetData employeeRecapSheet({
  required List<EmployeeAccount> employees,
  required Map<String, List<AttendanceDay>> daysByUsername,
  required Map<String, List<LeaveRequest>> leaveByUser,
  required Map<String, List<OvertimeRequest>> overtimeByUser,
  required DateTime start,
  required DateTime end,
}) {
  bool leaveCovers(List<LeaveRequest> list, DateTime day, LeaveType? type) {
    for (final r in list) {
      if (r.status != RequestStatus.approved) continue;
      if (type != null && r.type != type) continue;
      if (!day.isBefore(WorkCalendar.dateOnly(r.start)) &&
          !day.isAfter(WorkCalendar.dateOnly(r.end))) {
        return true;
      }
    }
    return false;
  }

  final rows = <List<Object?>>[];
  final sorted = [...employees]
    ..sort((a, b) => a.fullName.compareTo(b.fullName));
  for (final e in sorted) {
    final byDate = <String, AttendanceDay>{
      for (final d in daysByUsername[e.username] ?? const <AttendanceDay>[])
        '${d.date.year}-${d.date.month}-${d.date.day}': d,
    };
    final leaves = leaveByUser[e.username] ?? const <LeaveRequest>[];
    final overtimes = overtimeByUser[e.username] ?? const <OvertimeRequest>[];
    var present = 0;
    var late = 0;
    var annual = 0;
    var permission = 0;
    var sick = 0;
    var required = 0;
    var overtimeMinutes = 0;
    var day = DateTime(start.year, start.month, start.day);
    final join = WorkCalendar.dateOnly(e.joinDate);
    final last = DateTime(end.year, end.month, end.day);
    while (!day.isAfter(last)) {
      final weekend =
          day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
      if (!day.isBefore(join) && !weekend) {
        // Hari cuti bukan hari wajib hadir; absen tanpa keterangan tetap
        // dihitung wajib (menurunkan % hadir) agar terlihat di rekap.
        if (!leaveCovers(leaves, day, null)) required++;
        final info =
            byDate['${day.year}-${day.month}-${day.day}'];
        if (info?.clockIn != null) {
          present++;
          if (info!.status == AttendanceDayStatus.late) late++;
        } else if (leaveCovers(leaves, day, LeaveType.annual)) {
          annual++;
        } else if (leaveCovers(leaves, day, LeaveType.permission)) {
          permission++;
        } else if (leaveCovers(leaves, day, LeaveType.sick)) {
          sick++;
        }
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }
    for (final o in overtimes) {
      if (o.status != RequestStatus.approved) continue;
      final d = WorkCalendar.dateOnly(o.date);
      if (!d.isBefore(WorkCalendar.dateOnly(start)) &&
          !d.isAfter(WorkCalendar.dateOnly(last))) {
        overtimeMinutes += o.duration.inMinutes;
      }
    }
    final percent = required <= 0
        ? '—'
        : '${((present / required) * 100).round()}%';
    rows.add([
      e.fullName,
      e.username,
      e.division.label,
      present,
      late,
      annual,
      permission,
      sick,
      overtimeMinutes <= 0
          ? '—'
          : DateFormatId.duration(Duration(minutes: overtimeMinutes)),
      percent,
    ]);
  }
  return ReportSheetData(
    title: 'Rekap Karyawan',
    header: const [
      'Nama',
      'Username',
      'Divisi',
      'Hadir',
      'Terlambat',
      'Cuti',
      'Izin',
      'Sakit',
      'Lembur',
      '% Hadir',
    ],
    rows: rows,
  );
}

/// Rekap per event beserta daftar crew-nya: jawaban atas "event ini siapa
/// saja yang ikut".
ReportSheetData eventRecapSheet(
  List<EventItem> events, {
  DateTime? start,
  DateTime? end,
}) {
  final filtered = [
    for (final e in events)
      if (overlapsPeriod(e.startDate, e.endDate, start, end)) e,
  ];
  final sorted = [...filtered]
    ..sort((a, b) => a.startDate.compareTo(b.startDate));
  return ReportSheetData(
    title: 'Rekap Event',
    header: const [
      'Nama',
      'Perusahaan',
      'Entity',
      'Kategori',
      'Tanggal',
      'Lokasi',
      'Ukuran',
      'Nilai PO',
      'Jumlah crew',
      'Daftar crew',
    ],
    rows: [
      for (final e in sorted)
        [
          e.name,
          e.company,
          e.entity?.name ?? '—',
          e.category.name,
          DateFormatId.dateRange(e.startDate, e.endDate),
          e.location,
          e.size.label,
          e.poValue == null ? '—' : Rupiah.format(e.poValue!),
          e.crew.length,
          e.crew.isEmpty
              ? '—'
              : e.crew.map((m) => '${m.fullName} (${m.role.label})').join('; '),
        ],
    ],
  );
}
