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

  /// Kuota cuti tahunan satu karyawan beserta riwayat penyesuaiannya.
  /// Hanya Super Admin. [year] null = tahun berjalan.
  Future<LeaveQuota> fetchQuota(
    AuthUser actor, {
    required String username,
    int? year,
  });

  /// Mengurangi kuota cuti tahunan satu karyawan (mis. sisa tahun lalu yang
  /// hangus). [days] WAJIB negatif — tidak ada penambahan. [note] wajib.
  /// Server menolak bila kuota menjadi di bawah cuti yang sudah terpakai.
  Future<LeaveQuota> adjustQuota(
    AuthUser actor, {
    required String username,
    required int days,
    required String note,
    int? year,
  });

  /// Membatalkan satu penyesuaian (koreksi salah input).
  Future<void> deleteQuotaAdjustment(AuthUser actor, {required String id});
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

  /// Key objek di S3. null = hanya metadata.
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

/// Kuota cuti tahunan seorang karyawan pada satu tahun, termasuk riwayat
/// penyesuaian yang dibuat Super Admin.
class LeaveQuota {
  const LeaveQuota({
    required this.username,
    required this.fullName,
    required this.year,
    required this.baseQuota,
    required this.adjustment,
    required this.quota,
    required this.used,
    required this.pending,
    required this.adjustments,
  });

  final String username;
  final String fullName;
  final int year;

  /// Kuota dasar dari aturan perusahaan (12 hari).
  final int baseQuota;

  /// Total penyesuaian (selalu negatif atau 0).
  final int adjustment;

  /// Kuota efektif = [baseQuota] + [adjustment].
  final int quota;
  final int used;
  final int pending;
  final List<LeaveQuotaAdjustment> adjustments;

  int get remaining => (quota - used).clamp(0, quota);

  int get available => (remaining - pending).clamp(0, quota);

  /// Pengurangan maksimal yang masih boleh dilakukan tanpa membuat kuota
  /// berada di bawah cuti yang sudah terpakai.
  int get reducible => remaining;
}

/// Satu baris penyesuaian kuota (nilai [days] negatif = pengurangan).
class LeaveQuotaAdjustment {
  const LeaveQuotaAdjustment({
    required this.id,
    required this.days,
    required this.note,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final int days;
  final String note;
  final String createdBy;
  final DateTime createdAt;
}

/// Aturan validasi cuti yang sama dipakai di formulir; server menegakkan ulang.
abstract final class LeaveRules {
  static const int maxDaysAhead = 180;
  static const int sickAttachmentFromDays = 2;

  /// Durasi baku cuti melahirkan (bulan kalender) sejak hari pengajuan.
  static const int maternityMonths = 3;

  static bool attachmentRequired(LeaveType type, int workingDays) =>
      type == LeaveType.sick && workingDays >= sickAttachmentFromDays;
}
