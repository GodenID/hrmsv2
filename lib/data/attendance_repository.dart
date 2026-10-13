import 'package:flutter/foundation.dart';

import '../core/utils/date_format_id.dart';
import '../core/utils/work_calendar.dart';
import 'attendance_location.dart';
import 'auth_repository.dart';
import 'employee.dart';
import 'leave_repository.dart' show LeaveRequest;

export 'attendance_location.dart';

/// Kontrak absensi.
///
/// Catatan backend: waktu clock in/out WAJIB ditentukan oleh server,
/// bukan dikirim dari perangkat, agar tidak bisa dimanipulasi.
///
/// Persetujuan koreksi: Manager (untuk Staff) & Super Admin (semua), tidak
/// termasuk koreksi sendiri — WAJIB ditegakkan di server.
abstract class AttendanceRepository {
  /// Berbunyi setiap ada perubahan (clock in/out, pengajuan koreksi),
  /// agar halaman lain bisa menyegarkan datanya.
  Listenable get changes;

  Future<AttendanceRecord> fetchToday(AuthUser user);

  /// Clock in / out hanya bila [position] berada dalam radius salah satu
  /// lokasi absen. Server WAJIB menghitung jarak sendiri, menolak lokasi
  /// palsu (mock location), dan memakai jam server.
  Future<AttendanceRecord> clockIn(AuthUser user, {required GeoPoint position});

  Future<AttendanceRecord> clockOut(
    AuthUser user, {
    required GeoPoint position,
  });

  /// Lokasi absen yang berlaku (semua role boleh melihat).
  Future<List<AttendanceLocation>> fetchLocations(AuthUser user);

  /// Tambah ([id] null) / ubah lokasi absen — hanya Super Admin.
  Future<AttendanceLocation> saveLocation(
    AuthUser actor, {
    String? id,
    required AttendanceLocationDraft draft,
  });

  /// Hapus lokasi absen — hanya Super Admin. Minimal satu lokasi tersisa.
  Future<void> deleteLocation(AuthUser actor, {required String id});

  /// Hari-hari dalam satu bulan untuk kalender absensi, terbaru dulu:
  /// - hari kerja sampai hari ini (beserta catatan absensinya),
  /// - semua hari kerja yang tercakup pengajuan cuti / izin / sakit yang
  ///   menunggu atau disetujui — termasuk tanggal yang akan datang, agar
  ///   kalender langsung berubah begitu pengajuan dikirim.
  /// Akhir pekan tidak disertakan kecuali ada catatan absensi.
  Future<List<AttendanceDay>> fetchMonth(
    AuthUser user, {
    required int year,
    required int month,
  });

  /// Bulan paling awal yang punya data (bulan mulai bekerja).
  Future<DateTime> fetchFirstMonth(AuthUser user);

  Future<AttendanceCorrection> submitCorrection(
    AuthUser user, {
    required DateTime date,
    required DateTime clockIn,
    required DateTime clockOut,
    required String reason,
  });

  /// Koreksi karyawan lain yang boleh diproses [actor]:
  /// yang menunggu (terlama dulu), lalu yang sudah diproses (terbaru dulu).
  Future<List<CorrectionReviewItem>> fetchCorrectionQueue(AuthUser actor);

  /// Menyetujui / menolak koreksi. [note] wajib saat menolak.
  Future<CorrectionReviewItem> reviewCorrection(
    AuthUser actor, {
    required String id,
    required bool approve,
    String? note,
  });

  /// Membatalkan pengajuan koreksi milik sendiri. Hanya yang menunggu.
  Future<AttendanceCorrection> cancelCorrection(
    AuthUser user, {
    required String id,
  });

  /// Mengajukan clock in / clock out dari luar area absen.
  /// [position] tidak boleh lokasi palsu; bila ternyata di dalam radius
  /// salah satu lokasi, server menolak dan meminta pakai clock biasa.
  /// Hanya satu pengajuan menunggu per sisi per hari; sisi yang sudah
  /// tercatat (biasa maupun disetujui) tidak bisa diajukan lagi.
  Future<OutOfAreaRequest> submitOutOfArea(
    AuthUser user, {
    required OutOfAreaKind kind,
    required GeoPoint position,
    required String reason,
  });

  /// Pengajuan luar-area milik [user] sendiri, terbaru dulu (untuk status
  /// di panel & riwayat).
  Future<List<OutOfAreaRequest>> fetchMyOutOfArea(AuthUser user);

  /// Pengajuan luar-area karyawan lain yang boleh diproses [actor]:
  /// yang menunggu (terlama dulu), lalu yang sudah diproses (terbaru dulu).
  Future<List<OutOfAreaReviewItem>> fetchOutOfAreaQueue(AuthUser actor);

  /// Menyetujui / menolak. [note] wajib saat menolak.
  /// Disetujui = jam pengajuan ditulis sebagai jam clock in/out hari itu
  /// (ditandai "luar area").
  Future<OutOfAreaReviewItem> reviewOutOfArea(
    AuthUser actor, {
    required String id,
    required bool approve,
    String? note,
  });
  Future<void> deleteCorrection(AuthUser actor, {required String id});
  Future<void> deleteOutOfArea(AuthUser actor, {required String id});

  /// Membatalkan pengajuan luar-area milik sendiri. Hanya yang menunggu.
  Future<OutOfAreaRequest> cancelOutOfArea(
    AuthUser user, {
    required String id,
  });
}

/// Aturan pengajuan luar area (dipakai formulir & mock server).
abstract final class OutOfAreaRules {
  static const int minReasonLength = 10;
}

/// Sisi absensi yang diajukan dari luar area.
enum OutOfAreaKind {
  clockIn('Clock in'),
  clockOut('Clock out');

  const OutOfAreaKind(this.label);

  final String label;
}

/// Satu pengajuan clock in / clock out dari luar area, beserta bukti
/// posisi saat diajukan.
class OutOfAreaRequest {
  const OutOfAreaRequest({
    required this.id,
    required this.date,
    required this.kind,
    required this.requestedAt,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    required this.nearestLocationName,
    required this.distanceMeters,
    required this.reason,
    required this.status,
    required this.submittedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewerNote,
  });

  final String id;
  final DateTime date;
  final OutOfAreaKind kind;

  /// Jam yang diminta dicatat (jam server saat pengajuan dikirim).
  final DateTime requestedAt;

  /// Posisi perangkat saat mengajukan + lokasi absen terdekat saat itu.
  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final String nearestLocationName;
  final double distanceMeters;

  final String reason;
  final RequestStatus status;
  final DateTime submittedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewerNote;

  OutOfAreaRequest copyWith({
    required RequestStatus status,
    required String reviewedBy,
    required DateTime reviewedAt,
    String? reviewerNote,
  }) {
    return OutOfAreaRequest(
      id: id,
      date: date,
      kind: kind,
      requestedAt: requestedAt,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      nearestLocationName: nearestLocationName,
      distanceMeters: distanceMeters,
      reason: reason,
      status: status,
      submittedAt: submittedAt,
      reviewedBy: reviewedBy,
      reviewedAt: reviewedAt,
      reviewerNote: reviewerNote,
    );
  }
}

/// Satu pengajuan luar-area di halaman Persetujuan, beserta catatan asli
/// sistem hari itu.
class OutOfAreaReviewItem {
  const OutOfAreaReviewItem({
    required this.employee,
    required this.request,
    this.recordedClockIn,
    this.recordedClockOut,
  });

  final EmployeeRef employee;
  final OutOfAreaRequest request;

  /// Jam yang sudah tercatat sistem hari itu (null = belum ada).
  final DateTime? recordedClockIn;
  final DateTime? recordedClockOut;
}

/// Satu pengajuan di halaman Persetujuan lembur.
class OvertimeReviewItem {
  const OvertimeReviewItem({required this.employee, required this.request});

  final EmployeeRef employee;
  final OvertimeRequest request;
}

class OvertimeRequest {
  const OvertimeRequest({
    required this.id,
    required this.date,
    required this.start,
    required this.end,
    required this.reason,
    required this.status,
    required this.submittedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewerNote,
  });

  final String id;
  final DateTime date;
  final DateTime start;
  final DateTime end;
  final String reason;
  final RequestStatus status;
  final DateTime submittedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewerNote;

  Duration get duration => end.difference(start);

  /// Mis. "3 jam 30 menit".
  String get durationLabel => DateFormatId.duration(duration);

  /// Mis. "18.00 – 21.30".
  String get timeRangeLabel =>
      '${DateFormatId.time(start)} – ${DateFormatId.time(end)}';

  OvertimeRequest copyWith({
    RequestStatus? status,
    DateTime? reviewedAt,
    String? reviewedBy,
    String? reviewerNote,
  }) {
    return OvertimeRequest(
      id: id,
      date: date,
      start: start,
      end: end,
      reason: reason,
      status: status ?? this.status,
      submittedAt: submittedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewerNote: reviewerNote ?? this.reviewerNote,
    );
  }
}

/// Aturan validasi lembur yang sama dipakai di formulir & mock server.
abstract final class OvertimeRules {
  /// Diajukan maksimal N hari ke belakang (hari ini boleh).
  static const int maxDaysBack = 30;

  /// Durasi minimum yang bisa diajukan.
  static const int minMinutes = 60;

  static const int minReasonLength = 10;

  static String? validateReason(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Keterangan wajib diisi';
    if (v.length < minReasonLength) {
      return 'Keterangan minimal $minReasonLength karakter';
    }
    return null;
  }
}

/// Aturan catatan persetujuan (cuti & koreksi).
abstract final class ReviewRules {
  static const int minRejectNote = 5;
  static const int maxNote = 300;
}

/// Satu koreksi di halaman Persetujuan, beserta catatan asli sistem.
class CorrectionReviewItem {
  const CorrectionReviewItem({
    required this.employee,
    required this.correction,
    this.recordedClockIn,
    this.recordedClockOut,
  });

  final EmployeeRef employee;
  final AttendanceCorrection correction;

  /// Jam yang tercatat sistem sebelum koreksi (null = tidak ada catatan).
  final DateTime? recordedClockIn;
  final DateTime? recordedClockOut;
}

enum AttendanceStatus { notClockedIn, working, finished }

/// Absensi hari ini (dipakai panel di dashboard).
class AttendanceRecord {
  const AttendanceRecord({
    required this.date,
    this.clockIn,
    this.clockOut,
    this.clockInLocation,
    this.clockOutLocation,
  });

  final DateTime date;
  final DateTime? clockIn;
  final DateTime? clockOut;

  /// Nama lokasi absen tempat clock in / clock out tercatat.
  final String? clockInLocation;
  final String? clockOutLocation;

  AttendanceStatus get status {
    if (clockIn == null) return AttendanceStatus.notClockedIn;
    if (clockOut == null) return AttendanceStatus.working;
    return AttendanceStatus.finished;
  }

  Duration? workedDuration(DateTime now) {
    final start = clockIn;
    if (start == null) return null;
    final end = clockOut ?? now;
    final d = end.difference(start);
    return d.isNegative ? Duration.zero : d;
  }
}

enum AttendanceDayStatus {
  onTime('Tepat waktu'),
  late('Terlambat'),
  incomplete('Tidak clock out'),
  absent('Tidak hadir'),
  leave('Cuti/izin'),
  inProgress('Sedang bekerja'),
  notYet('Belum clock in'),

  /// Tanggal yang belum tiba.
  upcoming('Akan datang'),

  /// Akhir pekan tanpa catatan absensi.
  dayOff('Libur');

  const AttendanceDayStatus(this.label);

  final String label;
}

/// Satu hari di kalender absensi.
class AttendanceDay {
  const AttendanceDay({
    required this.date,
    required this.status,
    this.clockIn,
    this.clockOut,
    this.clockInLocation,
    this.clockOutLocation,
    this.leave,
    this.correction,
    this.outOfArea,
    this.overtime,
  });

  final DateTime date;
  final AttendanceDayStatus status;
  final DateTime? clockIn;
  final DateTime? clockOut;

  /// Nama lokasi absen (bila tercatat).
  final String? clockInLocation;
  final String? clockOutLocation;

  /// Pengajuan cuti / izin / sakit yang mencakup tanggal ini — menunggu
  /// atau disetujui. Bila disetujui, [status] == leave.
  final LeaveRequest? leave;

  /// Pengajuan koreksi terakhir untuk tanggal ini, bila ada.
  final AttendanceCorrection? correction;

  /// Pengajuan luar-area terakhir untuk tanggal ini, bila ada.
  final OutOfAreaRequest? outOfArea;

  /// Pengajuan lembur terakhir (menunggu/disetujui) untuk tanggal ini,
  /// bila ada.
  final OvertimeRequest? overtime;

  /// Mis. "Cuti tahunan".
  String? get leaveLabel => leave?.type.label;

  bool get hasPendingLeave => leave?.status == RequestStatus.pending;

  Duration? get worked {
    final start = clockIn;
    final end = clockOut;
    if (start == null || end == null) return null;
    return end.difference(start);
  }

  /// Hari ini atau sebelumnya, tidak tercakup cuti/izin/sakit, dalam batas
  /// waktu koreksi, dan belum ada koreksi yang menunggu.
  bool canRequestCorrection(DateTime now) {
    final today = WorkCalendar.dateOnly(now);
    if (!date.isBefore(today)) return false;
    if (leave != null || status == AttendanceDayStatus.leave) return false;
    if (status == AttendanceDayStatus.dayOff) return false;
    if (today.difference(date).inDays > WorkPolicy.correctionWindowDays) {
      return false;
    }
    return correction?.status != RequestStatus.pending;
  }

  /// Hari yang perlu ditindaklanjuti karyawan.
  bool get needsAttention =>
      (status == AttendanceDayStatus.incomplete ||
          status == AttendanceDayStatus.absent) &&
      leave == null &&
      correction?.status != RequestStatus.pending;
}

/// Status pengajuan (koreksi absensi & cuti).
enum RequestStatus {
  pending('Menunggu'),
  approved('Disetujui'),
  rejected('Ditolak'),
  cancelled('Dibatalkan');

  const RequestStatus(this.label);

  final String label;
}

class AttendanceCorrection {
  const AttendanceCorrection({
    required this.id,
    required this.date,
    required this.clockIn,
    required this.clockOut,
    required this.reason,
    required this.status,
    required this.submittedAt,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewerNote,
  });

  final String id;
  final DateTime date;
  final DateTime clockIn;
  final DateTime clockOut;
  final String reason;
  final RequestStatus status;
  final DateTime submittedAt;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewerNote;

  AttendanceCorrection copyWith({
    required RequestStatus status,
    required String reviewedBy,
    required DateTime reviewedAt,
    String? reviewerNote,
  }) {
    return AttendanceCorrection(
      id: id,
      date: date,
      clockIn: clockIn,
      clockOut: clockOut,
      reason: reason,
      status: status,
      submittedAt: submittedAt,
      reviewedBy: reviewedBy,
      reviewedAt: reviewedAt,
      reviewerNote: reviewerNote,
    );
  }
}
