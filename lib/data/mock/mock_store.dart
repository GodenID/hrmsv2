import 'package:flutter/foundation.dart';

import '../attendance_repository.dart';
import '../auth_repository.dart';
import '../leave_repository.dart';
import '../notification_repository.dart';
import '../overtime_repository.dart';
import '../warning_repository.dart';

/// "Database" di memori yang dipakai bersama oleh semua repository mock,
/// sehingga perubahan di satu fitur terlihat di fitur lain
/// (mis. ganti password -> login, cuti disetujui -> riwayat absensi,
/// cuti disetujui -> notifikasi karyawan).
///
/// Semua akun memakai password awal [demoPassword].
class MockStore {
  MockStore({DateTime Function()? clock}) : now = clock ?? DateTime.now {
    for (final seed in _seedAccounts) {
      accounts[seed.username] = MockAccount._fromSeed(seed);
    }
    _seedLeave();
    _seedCorrections();
    _seedNotifications();
  }

  static const String demoPassword = 'Prasasti@2026';

  /// Sumber waktu (bisa diganti di pengujian).
  final DateTime Function() now;

  /// Pendaftaran akun mandiri dibuka? Diatur Super Admin di menu Karyawan.
  bool registrationOpen = true;

  /// Lokasi absen. CONTOH saja (koordinat Jakarta) — Super Admin wajib
  /// menggantinya dengan titik kantor sebenarnya di menu Lokasi absen.
  final List<AttendanceLocation> attendanceLocations = [
    const AttendanceLocation(
      id: 'LOC-1',
      name: 'Kantor Pusat (contoh)',
      latitude: -6.175392,
      longitude: 106.827153,
      radiusMeters: 100,
    ),
    const AttendanceLocation(
      id: 'LOC-2',
      name: 'Produksi Prasasti (contoh)',
      latitude: -6.208763,
      longitude: 106.845599,
      radiusMeters: 150,
    ),
    const AttendanceLocation(
      id: 'LOC-3',
      name: 'Produksi Mutiari (contoh)',
      latitude: -6.121435,
      longitude: 106.774124,
      radiusMeters: 150,
    ),
    const AttendanceLocation(
      id: 'LOC-4',
      name: 'Gudang (contoh)',
      latitude: -6.302446,
      longitude: 106.895156,
      radiusMeters: 200,
    ),
  ];

  final Map<String, MockAccount> accounts = {};

  /// Absensi hari ini per username.
  final Map<String, AttendanceRecord> todayRecords = {};

  /// Koreksi absensi per username.
  final Map<String, List<AttendanceCorrection>> corrections = {};

  /// Pengajuan clock in / clock out dari luar area per username.
  final Map<String, List<OutOfAreaRequest>> outOfArea = {};

  /// Pengajuan cuti per username.
  final Map<String, List<LeaveRequest>> leaveRequests = {};

  /// Pengajuan lembur per username.
  final Map<String, List<OvertimeRequest>> overtimeRequests = {};

  /// Surat peringatan per username.
  final Map<String, List<WarningLetter>> warningLetters = {};

  /// Notifikasi per username, terbaru di akhir.
  final Map<String, List<MockNotification>> notifications = {};

  final ChangeSignal attendanceChanges = ChangeSignal();
  final ChangeSignal leaveChanges = ChangeSignal();
  final ChangeSignal notificationChanges = ChangeSignal();
  final ChangeSignal employeeChanges = ChangeSignal();
  final ChangeSignal overtimeChanges = ChangeSignal();
  final ChangeSignal warningChanges = ChangeSignal();

  int _nextId = 100;
  String nextId(String prefix) => '$prefix-${_nextId++}';

  /// Karyawan aktif (untuk laporan pembaca pengumuman, dsb.).
  List<EmployeeRef> get directory => [
    for (final a in accounts.values)
      if (a.active) a.toRef(),
  ];

  MockAccount? account(String username) =>
      accounts[username.trim().toLowerCase()];

  /// ID karyawan berikutnya, mis. "PG-0162" (dipakai pendaftaran mandiri).
  String nextEmployeeId() {
    final pattern = RegExp(r'^PG-(\d+)$');
    var max = 0;
    for (final a in accounts.values) {
      final n = int.tryParse(pattern.firstMatch(a.employeeId)?.group(1) ?? '');
      if (n != null && n > max) max = n;
    }
    return 'PG-${(max + 1).toString().padLeft(4, '0')}';
  }

  /// Apakah [actor] boleh memproses data milik [target]
  /// (persetujuan cuti/koreksi, reset password, nonaktifkan).
  /// Tidak pernah untuk diri sendiri.
  bool canActOn(AuthUser actor, MockAccount target) =>
      actor.username != target.username &&
      actor.role.canManageRole(target.role);

  /// Akun aktif yang berhak memproses pengajuan milik [requester].
  List<MockAccount> reviewersFor(MockAccount requester) => [
    for (final a in accounts.values)
      if (a.active &&
          a.username != requester.username &&
          a.role.canReviewRequests &&
          a.role.canManageRole(requester.role))
        a,
  ];

  /// Menambahkan notifikasi untuk [username] (dipanggil "server").
  /// [id] opsional yang stabil (mis. pengingat kontrak per karyawan +
  /// tanggal berakhir) agar tidak duplikat saat dibuat ulang.
  void notify(
    String username, {
    required NotificationKind kind,
    required String title,
    required String body,
    DateTime? at,
    bool read = false,
    String? id,
    String? refType,
    String? refId,
  }) {
    notifications
        .putIfAbsent(username, () => [])
        .add(
          MockNotification(
            id: id ?? nextId('NT'),
            kind: kind,
            title: title,
            body: body,
            createdAt: at ?? now(),
            read: read,
            refType: refType,
            refId: refId,
          ),
        );
    notificationChanges.ping();
  }

  void _seedLeave() {
    LeaveRequest req(
      String id,
      LeaveType type,
      DateTime start,
      DateTime end,
      int days,
      String reason,
      RequestStatus status, {
      required DateTime submittedAt,
      String? reviewedBy,
      DateTime? reviewedAt,
      String? note,
      LeaveAttachment? attachment,
    }) {
      return LeaveRequest(
        id: id,
        type: type,
        start: start,
        end: end,
        workingDays: days,
        reason: reason,
        status: status,
        submittedAt: submittedAt,
        reviewedBy: reviewedBy,
        reviewedAt: reviewedAt,
        reviewerNote: note,
        attachment: attachment,
      );
    }

    leaveRequests['budi.santoso'] = [
      req(
        'LV-5',
        LeaveType.annual,
        DateTime(2026, 10, 26),
        DateTime(2026, 10, 27),
        2,
        'Menghadiri pernikahan saudara di Yogyakarta.',
        RequestStatus.pending,
        submittedAt: DateTime(2026, 10, 6, 14, 12),
      ),
      req(
        'LV-4',
        LeaveType.permission,
        DateTime(2026, 10, 2),
        DateTime(2026, 10, 2),
        1,
        'Mengurus perpanjangan SIM.',
        RequestStatus.rejected,
        submittedAt: DateTime(2026, 9, 29, 9, 3),
        reviewedBy: 'Siti Rahma',
        reviewedAt: DateTime(2026, 9, 29, 13, 40),
        note:
            'Bertepatan dengan stock opname akhir kuartal. '
            'Silakan ajukan di tanggal lain.',
      ),
      req(
        'LV-3',
        LeaveType.annual,
        DateTime(2026, 9, 17),
        DateTime(2026, 9, 18),
        2,
        'Liburan keluarga.',
        RequestStatus.approved,
        submittedAt: DateTime(2026, 9, 7, 10, 22),
        reviewedBy: 'Siti Rahma',
        reviewedAt: DateTime(2026, 9, 7, 15, 5),
      ),
      req(
        'LV-2',
        LeaveType.sick,
        DateTime(2026, 8, 24),
        DateTime(2026, 8, 24),
        1,
        'Demam dan flu.',
        RequestStatus.approved,
        submittedAt: DateTime(2026, 8, 24, 7, 15),
        reviewedBy: 'Siti Rahma',
        reviewedAt: DateTime(2026, 8, 24, 9, 30),
      ),
      req(
        'LV-1',
        LeaveType.annual,
        DateTime(2026, 7, 6),
        DateTime(2026, 7, 6),
        1,
        'Keperluan keluarga.',
        RequestStatus.approved,
        submittedAt: DateTime(2026, 6, 29, 11, 0),
        reviewedBy: 'Siti Rahma',
        reviewedAt: DateTime(2026, 6, 30, 8, 45),
      ),
    ];
    leaveRequests['siti.rahma'] = [
      req(
        'LV-6',
        LeaveType.annual,
        DateTime(2026, 9, 14),
        DateTime(2026, 9, 15),
        2,
        'Acara keluarga.',
        RequestStatus.approved,
        submittedAt: DateTime(2026, 9, 1, 9, 0),
        reviewedBy: 'Andi Pratama',
        reviewedAt: DateTime(2026, 9, 1, 11, 20),
      ),
    ];
    leaveRequests['dewi.lestari'] = [
      req(
        'LV-7',
        LeaveType.sick,
        DateTime(2026, 10, 5),
        DateTime(2026, 10, 6),
        2,
        'Demam tinggi, istirahat sesuai anjuran dokter.',
        RequestStatus.pending,
        submittedAt: DateTime(2026, 10, 6, 7, 40),
        attachment: const LeaveAttachment(
          name: 'surat-dokter-dewi.pdf',
          sizeBytes: 284 * 1024,
        ),
      ),
    ];
  }

  void _seedCorrections() {
    corrections['rizky.ramadhan'] = [
      AttendanceCorrection(
        id: 'KR-1',
        date: DateTime(2026, 10, 2),
        clockIn: DateTime(2026, 10, 2, 8, 10),
        clockOut: DateTime(2026, 10, 2, 17, 25),
        reason:
            'Lupa clock out karena langsung berangkat ke lokasi gladi '
            'Peluncuran Produk Aurora.',
        status: RequestStatus.pending,
        submittedAt: DateTime(2026, 10, 5, 9, 20),
      ),
    ];
  }

  void _seedNotifications() {
    notify(
      'budi.santoso',
      kind: NotificationKind.leaveApproved,
      title: 'Cuti tahunan disetujui',
      body: 'Cuti tahunan 17–18 Sep 2026 disetujui oleh Siti Rahma.',
      at: DateTime(2026, 9, 7, 15, 5),
      read: true,
    );
    notify(
      'budi.santoso',
      kind: NotificationKind.leaveRejected,
      title: 'Izin ditolak',
      body:
          'Izin 2 Okt 2026 ditolak oleh Siti Rahma: “Bertepatan dengan stock '
          'opname akhir kuartal. Silakan ajukan di tanggal lain.”',
      at: DateTime(2026, 9, 29, 13, 40),
    );
    for (final reviewer in ['siti.rahma', 'andi.pratama']) {
      notify(
        reviewer,
        kind: NotificationKind.reviewRequested,
        title: 'Koreksi absensi baru',
        body: 'Rizky Ramadhan mengajukan koreksi absensi 2 Okt 2026.',
        at: DateTime(2026, 10, 5, 9, 20),
      );
      notify(
        reviewer,
        kind: NotificationKind.reviewRequested,
        title: 'Pengajuan sakit baru',
        body: 'Dewi Lestari mengajukan sakit 5–6 Okt 2026 (2 hari).',
        at: DateTime(2026, 10, 6, 7, 40),
      );
      notify(
        reviewer,
        kind: NotificationKind.reviewRequested,
        title: 'Pengajuan cuti tahunan baru',
        body: 'Budi Santoso mengajukan cuti tahunan 26–27 Okt 2026 (2 hari).',
        at: DateTime(2026, 10, 6, 14, 12),
      );
    }
  }

  static const List<_SeedAccount> _seedAccounts = [
    _SeedAccount(
      username: 'andi.pratama',
      fullName: 'Andi Pratama',
      role: UserRole.superadmin,
      nik: '3273012304880003',
      employeeId: 'PG-0007',
      position: 'Kepala Human Capital',
      division: Division.hrIt,
      employmentStatus: EmploymentStatus.permanent,
      joinYear: 2019,
      joinMonth: 3,
      joinDay: 4,
      phone: '0812-0000-0007',
    ),
    _SeedAccount(
      username: 'siti.rahma',
      fullName: 'Siti Rahma',
      role: UserRole.manager,
      nik: '3174015507920002',
      employeeId: 'PG-0031',
      position: 'HR Generalist',
      division: Division.hrIt,
      employmentStatus: EmploymentStatus.permanent,
      joinYear: 2021,
      joinMonth: 8,
      joinDay: 2,
      phone: '0812-0000-0031',
      managerUsername: 'andi.pratama',
    ),
    _SeedAccount(
      username: 'budi.santoso',
      fullName: 'Budi Santoso',
      role: UserRole.staff,
      nik: '3201123456780001',
      employeeId: 'PG-0142',
      position: 'Staf Operasional',
      division: Division.produksiPrasasti,
      employmentStatus: EmploymentStatus.permanent,
      joinYear: 2024,
      joinMonth: 2,
      joinDay: 1,
      phone: '0812-0000-0142',
      managerUsername: 'siti.rahma',
    ),
    _SeedAccount(
      username: 'dewi.lestari',
      fullName: 'Dewi Lestari',
      role: UserRole.staff,
      nik: '3201000000000004',
      employeeId: 'PG-0098',
      position: 'Staf Keuangan',
      division: Division.financeAccounting,
      employmentStatus: EmploymentStatus.permanent,
      joinYear: 2022,
      joinMonth: 11,
      joinDay: 7,
      phone: '0812-0000-0098',
      managerUsername: 'siti.rahma',
    ),
    _SeedAccount(
      username: 'rizky.ramadhan',
      fullName: 'Rizky Ramadhan',
      role: UserRole.staff,
      nik: '3201000000000005',
      employeeId: 'PG-0156',
      position: 'Staf IT',
      division: Division.hrIt,
      employmentStatus: EmploymentStatus.contract,
      contractMonths: 12,
      joinYear: 2025,
      joinMonth: 1,
      joinDay: 6,
      phone: '0812-0000-0156',
      managerUsername: 'siti.rahma',
    ),
    _SeedAccount(
      username: 'agus.setiawan',
      fullName: 'Agus Setiawan',
      role: UserRole.staff,
      nik: '3201000000000006',
      employeeId: 'PG-0077',
      position: 'Supervisor Gudang',
      division: Division.produksiPrasasti,
      employmentStatus: EmploymentStatus.permanent,
      joinYear: 2020,
      joinMonth: 5,
      joinDay: 11,
      phone: '0812-0000-0077',
      managerUsername: 'siti.rahma',
    ),
    _SeedAccount(
      username: 'maya.putri',
      fullName: 'Maya Putri',
      role: UserRole.staff,
      nik: '3201000000000007',
      employeeId: 'PG-0161',
      position: 'Staf Pemasaran',
      division: Division.businessDevelopment,
      employmentStatus: EmploymentStatus.contract,
      contractMonths: 6,
      joinYear: 2025,
      joinMonth: 6,
      joinDay: 2,
      phone: '0812-0000-0161',
      managerUsername: 'siti.rahma',
    ),
    _SeedAccount(
      username: 'fajar.nugroho',
      fullName: 'Fajar Nugroho',
      role: UserRole.staff,
      nik: '3201000000000008',
      employeeId: 'PG-0120',
      position: 'Staf Pengadaan',
      division: Division.financeAccounting,
      employmentStatus: EmploymentStatus.permanent,
      joinYear: 2023,
      joinMonth: 9,
      joinDay: 4,
      phone: '0812-0000-0120',
      managerUsername: 'siti.rahma',
    ),
  ];
}

/// ChangeNotifier yang bisa dipicu dari luar.
class ChangeSignal extends ChangeNotifier {
  void ping() => notifyListeners();
}

class MockAccount {
  MockAccount({
    required this.username,
    required this.fullName,
    required this.role,
    required this.nik,
    required this.employeeId,
    required this.position,
    required this.division,
    required this.employmentStatus,
    this.contractMonths,
    required this.joinDate,
    required this.email,
    required this.phone,
    required this.password,
    this.managerUsername,
    this.active = true,
    this.gender,
    this.birthPlace,
    this.birthDate,
    this.address,
    this.emergencyContact,
    this.privacyConsentedAt,
  });

  MockAccount._fromSeed(_SeedAccount s)
    : username = s.username,
      fullName = s.fullName,
      role = s.role,
      nik = s.nik,
      employeeId = s.employeeId,
      position = s.position,
      division = s.division,
      employmentStatus = s.employmentStatus,
      contractMonths = s.contractMonths,
      joinDate = DateTime(s.joinYear, s.joinMonth, s.joinDay),
      // Domain .example: placeholder, ganti dengan domain perusahaan.
      email = '${s.username}@prasasti.example',
      phone = s.phone,
      managerUsername = s.managerUsername,
      password = MockStore.demoPassword,
      active = true;

  final String username;
  String fullName;
  UserRole role;
  String nik;
  String employeeId;
  String position;
  Division division;
  EmploymentStatus employmentStatus;
  int? contractMonths;
  DateTime joinDate;
  String email;
  String phone;
  String? managerUsername;
  String password;
  bool active;

  // Data pribadi dari pendaftaran mandiri (null untuk akun buatan Manager).
  Gender? gender;
  String? birthPlace;
  DateTime? birthDate;
  String? address;
  EmergencyContact? emergencyContact;

  /// Kapan persetujuan privasi diberikan saat pendaftaran (null = akun lama
  /// atau dibuat sebelum fitur consent ada).
  DateTime? privacyConsentedAt;

  /// Foto profil (PNG / JPEG), null = avatar inisial.
  Uint8List? photo;

  AuthUser toUser() =>
      AuthUser(username: username, fullName: fullName, role: role);

  EmployeeRef toRef() => EmployeeRef(username: username, fullName: fullName);
}

class MockNotification {
  MockNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    this.refType,
    this.refId,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  bool read;
  final String? refType;
  final String? refId;

  AppNotification toNotification() => AppNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    createdAt: createdAt,
    read: read,
    refType: refType,
    refId: refId,
  );
}

class _SeedAccount {
  const _SeedAccount({
    required this.username,
    required this.fullName,
    required this.role,
    required this.nik,
    required this.employeeId,
    required this.position,
    required this.division,
    required this.employmentStatus,
    this.contractMonths,
    required this.joinYear,
    required this.joinMonth,
    required this.joinDay,
    required this.phone,
    this.managerUsername,
  });

  final String username;
  final String fullName;
  final UserRole role;
  final String nik;
  final String employeeId;
  final String position;
  final Division division;
  final EmploymentStatus employmentStatus;
  final int? contractMonths;
  final int joinYear;
  final int joinMonth;
  final int joinDay;
  final String phone;
  final String? managerUsername;
}
