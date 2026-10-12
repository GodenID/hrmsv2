import 'package:flutter/foundation.dart';

import 'attendance_repository.dart';
import 'auth_repository.dart';

export 'attendance_repository.dart'
    show
        RequestStatus,
        ReviewRules,
        OvertimeRequest,
        OvertimeReviewItem,
        OvertimeRules;
export 'employee.dart';

/// Kontrak lembur.
///
/// - Karyawan: melihat riwayat, mengajukan, membatalkan (yang menunggu).
/// - Manager & Super Admin: menyetujui / menolak pengajuan karyawan yang
///   boleh mereka kelola (Manager -> Staff, Super Admin -> semua), tidak
///   termasuk pengajuan sendiri.
///
/// Lembur diajukan setelah dikerjakan (maksimal 30 hari ke belakang,
/// seperti koreksi), minimal 1 jam, dan tidak boleh bertabrakan dengan
/// cuti/izin/sakit yang menunggu atau disetujui.
///
/// Implementasi WAJIB menegakkan aturan ini di server.
abstract class OvertimeRepository {
  Listenable get changes;

  /// Terbaru lebih dulu.
  Future<List<OvertimeRequest>> fetchRequests(AuthUser user);

  /// [date] tanggal lembur; [start]/[end] jam mulai–selesai pada tanggal
  /// itu.
  Future<OvertimeRequest> submit(
    AuthUser user, {
    required DateTime date,
    required DateTime start,
    required DateTime end,
    required String reason,
  });

  /// Hanya untuk pengajuan berstatus menunggu.
  Future<OvertimeRequest> cancel(AuthUser user, {required String id});

  /// Pengajuan karyawan lain yang boleh diproses [actor]:
  /// yang menunggu (terlama dulu), lalu yang sudah diproses (terbaru dulu).
  /// Pengajuan yang dibatalkan karyawan tidak disertakan.
  Future<List<OvertimeReviewItem>> fetchReviewQueue(AuthUser actor);

  /// Menyetujui / menolak. [note] wajib saat menolak.
  Future<OvertimeReviewItem> review(
    AuthUser actor, {
    required String id,
    required bool approve,
    String? note,
  });
}

