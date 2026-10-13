import 'package:flutter/foundation.dart';

import 'attendance_repository.dart';
import 'auth_repository.dart';
import 'employee.dart';

export 'attendance_repository.dart' show RequestStatus, ReviewRules;
export 'employee.dart';

/// Kontrak cuti / izin / sakit.
///
/// - Karyawan: melihat saldo & riwayat, mengajukan, membatalkan.
/// - Manager & Super Admin: menyetujui / menolak pengajuan karyawan yang
///   boleh mereka kelola (Manager -> Staff, Super Admin -> semua), tidak
///   termasuk pengajuan sendiri.
///
/// Implementasi WAJIB menegakkan aturan ini di server.
abstract class LeaveRepository {
  Listenable get changes;

  Future<LeaveBalance> fetchBalance(AuthUser user);

  /// Terbaru lebih dulu.
  Future<List<LeaveRequest>> fetchRequests(AuthUser user);

  Future<LeaveRequest> submit(
    AuthUser user, {
    required LeaveType type,
    required DateTime start,
    required DateTime end,
    required String reason,
    LeaveAttachment? attachment,
  });

  /// Hanya untuk pengajuan berstatus menunggu.
  Future<LeaveRequest> cancel(AuthUser user, {required String id});

  /// Pengajuan karyawan lain yang boleh diproses [actor]:
  /// yang menunggu (terlama dulu), lalu yang sudah diproses (terbaru dulu).
  /// Pengajuan yang dibatalkan karyawan tidak disertakan.
  Future<List<LeaveReviewItem>> fetchReviewQueue(AuthUser actor);

  /// Menyetujui / menolak. [note] wajib saat menolak.
  Future<LeaveReviewItem> review(
    AuthUser actor, {
    required String id,
    required bool approve,
    String? note,
  });

  /// Hapus riwayat pengajuan (khusus Super Admin).
  Future<void> delete(AuthUser actor, {required String id});

  /// Memotong cuti tahunan banyak karyawan sekaligus untuk cuti bersama.
  /// Hanya Super Admin. Untuk tiap karyawan dibuatkan pengajuan cuti
  /// tahunan berstatus disetujui. Jumlah hari = hari kerja Senin–Jumat
  /// dalam rentang, dikurangi tanggal yang sudah tercakup cuti tahunan
  /// yang disetujui (agar tidak memotong dua kali). Tiap karyawan yang
  /// terpotong menerima notifikasi berisi jumlah hari & sisa cutinya.
  Future<List<CollectiveLeaveResult>> applyCollectiveLeave(
    AuthUser actor, {
    required List<String> usernames,
    required DateTime start,
    required DateTime end,
    required String reason,
  });
}

/// Hasil potong cuti bersama untuk satu karyawan.
class CollectiveLeaveResult {
  const CollectiveLeaveResult({
    required this.employee,
    required this.days,
    this.skipped,
  });

  final EmployeeRef employee;

  /// Hari kerja yang dipotong (0 bila dilewati).
  final int days;

  /// Alasan dilewati, null = berhasil dipotong.
  final String? skipped;

  bool get applied => skipped == null;
}

/// Satu pengajuan di halaman Persetujuan.
class LeaveReviewItem {
  const LeaveReviewItem({
    required this.employee,
    required this.request,
    required this.balance,
  });

  final EmployeeRef employee;
  final LeaveRequest request;

  /// Saldo cuti tahunan karyawan saat ini (bantu Manager memutuskan).
  final LeaveBalance balance;
}

enum LeaveType {
  annual('Cuti tahunan'),
  permission('Izin'),
  sick('Sakit'),
  maternity('Cuti melahirkan');

  const LeaveType(this.label);

  final String label;

  /// Hanya cuti tahunan yang memotong kuota.
  bool get usesQuota => this == LeaveType.annual;

  /// Sakit boleh diajukan mundur (setelah kejadian).
  int get maxDaysBack => this == LeaveType.sick ? 7 : 0;
}

class LeaveAttachment {
  const LeaveAttachment({required this.name, required this.sizeBytes, this.key});

  final String name;
  final int sizeBytes;

  /// Key objek di S3 (mode API). null = hanya metadata (mode mock).
  final String? key;

  static const int maxBytes = 2 * 1024 * 1024;
  static const List<String> allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).ceil()} KB';
  }
}

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.type,
    required this.start,
    required this.end,
    required this.workingDays,
    required this.reason,
    required this.status,
    required this.submittedAt,
    this.attachment,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewerNote,
  });

  final String id;
  final LeaveType type;
  final DateTime start;
  final DateTime end;
  final int workingDays;
  final String reason;
  final RequestStatus status;
  final DateTime submittedAt;
  final LeaveAttachment? attachment;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewerNote;

  LeaveRequest copyWith({
    RequestStatus? status,
    DateTime? reviewedAt,
    String? reviewedBy,
    String? reviewerNote,
  }) {
    return LeaveRequest(
      id: id,
      type: type,
      start: start,
      end: end,
      workingDays: workingDays,
      reason: reason,
      status: status ?? this.status,
      submittedAt: submittedAt,
      attachment: attachment,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewerNote: reviewerNote ?? this.reviewerNote,
    );
  }
}

class LeaveBalance {
  const LeaveBalance({
    required this.year,
    required this.quota,
    required this.used,
    required this.pending,
  });

  final int year;
  final int quota;

  /// Hari cuti tahunan yang sudah disetujui.
  final int used;

  /// Hari cuti tahunan yang masih menunggu persetujuan.
  final int pending;

  int get remaining => (quota - used).clamp(0, quota);

  /// Yang masih bisa diajukan sekarang.
  int get available => (remaining - pending).clamp(0, quota);
}

/// Aturan validasi cuti yang sama dipakai di formulir & mock server.
abstract final class LeaveRules {
  static const int maxDaysAhead = 180;
  static const int sickAttachmentFromDays = 2;

  /// Durasi baku cuti melahirkan (bulan kalender) sejak hari pengajuan.
  static const int maternityMonths = 3;

  static bool attachmentRequired(LeaveType type, int workingDays) =>
      type == LeaveType.sick && workingDays >= sickAttachmentFromDays;
}
