import '../../core/app_scope.dart';
import '../../data/attendance_repository.dart';
import '../../data/auth_repository.dart';
import '../../data/notification_repository.dart';
import 'shell_controller.dart';
import 'shell_routes.dart';

/// Mengubah tautan notifikasi (kind + refType/refId) menjadi halaman detail
/// yang tepat. Dipakai ketukan di daftar notifikasi dan ketukan push (tray
/// maupun banner), jadi keduanya selalu berujung di tempat yang sama.
///
/// Semua pencarian best-effort: bila data tidak ditemukan / gagal dimuat,
/// [open] mengembalikan false dan pemanggil membuka menu tujuan biasa.
class NotificationLinkResolver {
  NotificationLinkResolver({
    required this.deps,
    required this.user,
    required this.pushRoute,
    required this.showDay,
  });

  final AppDependencies deps;
  final AuthUser user;

  /// Pindah ke [tab] lalu buka [route] di atasnya. false = menu tidak ada.
  final Future<bool> Function(ShellTab tab, String route, Object args)
  pushRoute;

  /// Pindah ke menu Absensi lalu tampilkan lembar detail hari [day].
  final Future<bool> Function(AttendanceDay day) showDay;

  Future<bool> open({
    required String kind,
    required String? refType,
    required String? refId,
  }) async {
    if (refType == null || refId == null || refId.isEmpty) return false;
    final review = kind == NotificationKind.reviewRequested.name;
    try {
      switch (refType) {
        case 'leave':
          return review ? await _reviewLeave(refId) : await _myLeave(refId);
        case 'overtime':
          return review
              ? await _reviewOvertime(refId)
              : await _myOvertime(refId);
        case 'correction':
          return review
              ? await _reviewCorrection(refId)
              : await _myCorrection(refId);
        case 'outOfArea':
          return review
              ? await _reviewOutOfArea(refId)
              : await _myOutOfArea(refId);
        case 'warning':
          return await _warning(refId);
        case 'announcement':
          return await _announcement(refId);
      }
    } catch (_) {
      // Jaringan / data hilang: jatuh ke menu tujuan biasa.
    }
    return false;
  }

  // ---- sisi pemroses (antrean Persetujuan) ----

  Future<bool> _reviewLeave(String id) async {
    if (!user.role.canReviewRequests) return false;
    for (final item in await deps.leave.fetchReviewQueue(user)) {
      if (item.request.id == id) {
        return pushRoute(ShellTab.approvals, ShellRoutes.leaveReview, item);
      }
    }
    return false;
  }

  Future<bool> _reviewOvertime(String id) async {
    if (!user.role.canReviewRequests) return false;
    for (final item in await deps.overtime.fetchReviewQueue(user)) {
      if (item.request.id == id) {
        return pushRoute(ShellTab.approvals, ShellRoutes.overtimeReview, item);
      }
    }
    return false;
  }

  Future<bool> _reviewCorrection(String id) async {
    if (!user.role.canReviewRequests) return false;
    for (final item in await deps.attendance.fetchCorrectionQueue(user)) {
      if (item.correction.id == id) {
        return pushRoute(
          ShellTab.approvals,
          ShellRoutes.correctionReview,
          item,
        );
      }
    }
    return false;
  }

  Future<bool> _reviewOutOfArea(String id) async {
    if (!user.role.canReviewRequests) return false;
    for (final item in await deps.attendance.fetchOutOfAreaQueue(user)) {
      if (item.request.id == id) {
        return pushRoute(
          ShellTab.approvals,
          ShellRoutes.outOfAreaReview,
          item,
        );
      }
    }
    return false;
  }

  // ---- sisi pengaju (hasil persetujuan) ----

  Future<bool> _myLeave(String id) async {
    for (final r in await deps.leave.fetchRequests(user)) {
      if (r.id == id) {
        return pushRoute(ShellTab.leave, ShellRoutes.leaveDetail, r);
      }
    }
    return false;
  }

  Future<bool> _myOvertime(String id) async {
    for (final r in await deps.overtime.fetchRequests(user)) {
      if (r.id == id) {
        return pushRoute(ShellTab.leave, ShellRoutes.overtimeDetail, r);
      }
    }
    return false;
  }

  /// Koreksi hanya bisa untuk ≤ 30 hari ke belakang, jadi cukup periksa
  /// bulan ini dan dua bulan sebelumnya.
  Future<bool> _myCorrection(String id) async {
    final now = DateTime.now();
    for (var back = 0; back < 3; back++) {
      final m = DateTime(now.year, now.month - back);
      final days = await deps.attendance.fetchMonth(
        user,
        year: m.year,
        month: m.month,
      );
      for (final d in days) {
        if (d.correction?.id == id) return showDay(d);
      }
    }
    return false;
  }

  Future<bool> _myOutOfArea(String id) async {
    for (final r in await deps.attendance.fetchMyOutOfArea(user)) {
      if (r.id != id) continue;
      // Tanggal pengajuan bisa masuk bulan ini atau berikutnya (periode
      // absensi tidak selalu sama dengan bulan kalender).
      for (var plus = 0; plus < 2; plus++) {
        final m = DateTime(r.date.year, r.date.month + plus);
        final days = await deps.attendance.fetchMonth(
          user,
          year: m.year,
          month: m.month,
        );
        for (final d in days) {
          if (d.outOfArea?.id == id) return showDay(d);
        }
      }
    }
    return false;
  }

  // ---- lainnya ----

  Future<bool> _warning(String id) async {
    var letters = await deps.warnings.fetchMyLetters(user);
    for (final l in letters) {
      if (l.letter.id == id) {
        return pushRoute(ShellTab.warnings, ShellRoutes.warningDetail, l);
      }
    }
    if (user.role == UserRole.staff) return false;
    letters = await deps.warnings.fetchLetters(user);
    for (final l in letters) {
      if (l.letter.id == id) {
        return pushRoute(ShellTab.warnings, ShellRoutes.warningDetail, l);
      }
    }
    return false;
  }

  Future<bool> _announcement(String id) async {
    final a = await deps.announcements.open(viewer: user, id: id);
    return pushRoute(ShellTab.dashboard, ShellRoutes.announcementDetail, a);
  }
}
