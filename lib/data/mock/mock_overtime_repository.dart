import 'package:flutter/foundation.dart';

import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../auth_repository.dart';
import '../leave_repository.dart';
import '../notification_repository.dart';
import '../overtime_repository.dart';
import 'mock_store.dart';

/// Lembur palsu. Aturan hak akses & validasi di sini meniru yang WAJIB
/// ditegakkan server (lihat [OvertimeRepository]).
class MockOvertimeRepository implements OvertimeRepository {
  MockOvertimeRepository(
    this.store, {
    this.latency = const Duration(milliseconds: 500),
  });

  final MockStore store;
  final Duration latency;

  @override
  Listenable get changes => store.overtimeChanges;

  @override
  Future<void> delete(AuthUser actor, {required String id}) async {
    await Future<void>.delayed(latency);
    if (actor.role != UserRole.superadmin) {
      throw const PermissionDeniedException(
        'Hanya Super Admin yang dapat menghapus riwayat.',
      );
    }
    for (final key in store.overtimeRequests.keys.toList()) {
      final list = store.overtimeRequests[key]!;
      final idx = list.indexWhere((r) => r.id == id);
      if (idx >= 0) {
        list.removeAt(idx);
        store.overtimeChanges.ping();
        break;
      }
    }
  }

  DateTime get _today => WorkCalendar.dateOnly(store.now());

  List<OvertimeRequest> _list(String username) =>
      store.overtimeRequests[username] ?? const [];

  /// Cuti/izin/sakit (menunggu atau disetujui) yang mencakup [date].
  LeaveRequest? _leaveOn(String username, DateTime date) {
    for (final r in store.leaveRequests[username] ?? const <LeaveRequest>[]) {
      if (r.status != RequestStatus.approved &&
          r.status != RequestStatus.pending) {
        continue;
      }
      if (WorkCalendar.rangesOverlap(r.start, r.end, date, date)) return r;
    }
    return null;
  }

  @override
  Future<List<OvertimeRequest>> fetchRequests(AuthUser user) async {
    await Future<void>.delayed(latency);
    final sorted = [..._list(user.username)]
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return List.unmodifiable(sorted);
  }

  @override
  Future<OvertimeRequest> submit(
    AuthUser user, {
    required DateTime date,
    required DateTime start,
    required DateTime end,
    required String reason,
  }) async {
    await Future<void>.delayed(latency);
    final day = WorkCalendar.dateOnly(date);
    final today = _today;
    if (day.isAfter(today)) {
      throw const AppException(
        'Lembur diajukan setelah dikerjakan, bukan sebelumnya.',
      );
    }
    if (today.difference(day).inDays > OvertimeRules.maxDaysBack) {
      throw AppException(
        'Lembur hanya bisa diajukan untuk '
        '${OvertimeRules.maxDaysBack} hari terakhir.',
      );
    }
    final s = DateTime(day.year, day.month, day.day, start.hour, start.minute);
    final e = DateTime(day.year, day.month, day.day, end.hour, end.minute);
    if (!e.isAfter(s)) {
      throw const AppException(
        'Jam selesai harus setelah jam mulai pada tanggal yang sama.',
      );
    }
    if (e.difference(s).inMinutes < OvertimeRules.minMinutes) {
      throw const AppException(
        'Durasi lembur minimal ${OvertimeRules.minMinutes} menit (1 jam).',
      );
    }
    final trimmed = reason.trim();
    final reasonError = OvertimeRules.validateReason(trimmed);
    if (reasonError != null) throw AppException(reasonError);
    final clash = _leaveOn(user.username, day);
    if (clash != null) {
      throw AppException(
        'Tanggal ini tercakup pengajuan ${clash.type.label.toLowerCase()} '
        '(${clash.status.label.toLowerCase()}). Lembur tidak bisa diajukan.',
      );
    }
    if (_list(user.username).any(
      (r) =>
          WorkCalendar.isSameDay(r.date, day) &&
          (r.status == RequestStatus.pending ||
              r.status == RequestStatus.approved),
    )) {
      throw const AppException(
        'Sudah ada pengajuan lembur untuk tanggal ini.',
      );
    }
    final request = OvertimeRequest(
      id: store.nextId('OT'),
      date: day,
      start: s,
      end: e,
      reason: trimmed,
      status: RequestStatus.pending,
      submittedAt: store.now(),
    );
    store.overtimeRequests
        .putIfAbsent(user.username, () => [])
        .add(request);
    store.overtimeChanges.ping();

    final requester = store.account(user.username);
    if (requester != null) {
      for (final reviewer in store.reviewersFor(requester)) {
        store.notify(
          reviewer.username,
          kind: NotificationKind.reviewRequested,
          title: 'Pengajuan lembur baru',
          body:
              '${requester.fullName} mengajukan lembur '
              '${DateFormatId.shortDate(day)} '
              '(${request.durationLabel}).',
        );
      }
    }
    return request;
  }

  @override
  Future<OvertimeRequest> cancel(AuthUser user, {required String id}) async {
    await Future<void>.delayed(latency);
    final list = store.overtimeRequests[user.username] ?? const [];
    final index = list.indexWhere((r) => r.id == id);
    if (index < 0) {
      throw const AppException('Pengajuan lembur tidak ditemukan.');
    }
    if (list[index].status != RequestStatus.pending) {
      throw const AppException(
        'Hanya pengajuan yang masih menunggu yang bisa dibatalkan.',
      );
    }
    final updated = list[index].copyWith(
      status: RequestStatus.cancelled,
      reviewedAt: store.now(),
    );
    store.overtimeRequests[user.username]![index] = updated;
    store.overtimeChanges.ping();
    return updated;
  }

  void _requireReviewer(AuthUser actor) {
    if (!actor.role.canReviewRequests) {
      throw const PermissionDeniedException(
        'Hanya Manager dan Super Admin yang dapat memproses pengajuan.',
      );
    }
  }

  @override
  Future<List<OvertimeReviewItem>> fetchReviewQueue(AuthUser actor) async {
    await Future<void>.delayed(latency);
    _requireReviewer(actor);
    final pending = <OvertimeReviewItem>[];
    final done = <OvertimeReviewItem>[];
    for (final entry in store.overtimeRequests.entries) {
      final account = store.account(entry.key);
      if (account == null || !store.canActOn(actor, account)) continue;
      for (final r in entry.value) {
        if (r.status == RequestStatus.cancelled) continue;
        final item = OvertimeReviewItem(
          employee: account.toRef(),
          request: r,
        );
        (r.status == RequestStatus.pending ? pending : done).add(item);
      }
    }
    pending.sort(
      (a, b) => a.request.submittedAt.compareTo(b.request.submittedAt),
    );
    done.sort((a, b) {
      final x = a.request.reviewedAt ?? a.request.submittedAt;
      final y = b.request.reviewedAt ?? b.request.submittedAt;
      return y.compareTo(x);
    });
    return List.unmodifiable([...pending, ...done]);
  }

  @override
  Future<OvertimeReviewItem> review(
    AuthUser actor, {
    required String id,
    required bool approve,
    String? note,
  }) async {
    await Future<void>.delayed(latency);
    _requireReviewer(actor);

    MockAccount? account;
    var index = -1;
    for (final entry in store.overtimeRequests.entries) {
      final i = entry.value.indexWhere((r) => r.id == id);
      if (i >= 0) {
        account = store.account(entry.key);
        index = i;
        break;
      }
    }
    if (account == null || index < 0) {
      throw const AppException('Pengajuan lembur tidak ditemukan.');
    }
    if (account.username == actor.username) {
      throw const PermissionDeniedException(
        'Anda tidak dapat memproses pengajuan Anda sendiri.',
      );
    }
    if (!store.canActOn(actor, account)) {
      throw const PermissionDeniedException(
        'Anda tidak berhak memproses pengajuan karyawan ini.',
      );
    }

    final list = store.overtimeRequests[account.username]!;
    final current = list[index];
    if (current.status != RequestStatus.pending) {
      throw AppException(
        'Pengajuan ini sudah ${current.status.label.toLowerCase()}. '
        'Muat ulang untuk melihat status terbaru.',
      );
    }
    final trimmed = note?.trim() ?? '';
    if (!approve && trimmed.length < ReviewRules.minRejectNote) {
      throw const AppException(
        'Tulis alasan penolakan minimal ${ReviewRules.minRejectNote} karakter.',
      );
    }
    if (trimmed.length > ReviewRules.maxNote) {
      throw const AppException(
        'Catatan maksimal ${ReviewRules.maxNote} karakter.',
      );
    }

    final updated = current.copyWith(
      status: approve ? RequestStatus.approved : RequestStatus.rejected,
      reviewedBy: actor.fullName,
      reviewedAt: store.now(),
      reviewerNote: trimmed.isEmpty ? null : trimmed,
    );
    list[index] = updated;
    store.overtimeChanges.ping();

    final verb = approve ? 'disetujui' : 'ditolak';
    store.notify(
      account.username,
      kind: approve
          ? NotificationKind.overtimeApproved
          : NotificationKind.overtimeRejected,
      title: 'Pengajuan lembur $verb',
      body:
          'Lembur ${DateFormatId.shortDate(updated.date)} '
          '(${updated.durationLabel}) $verb oleh '
          '${actor.fullName}${trimmed.isEmpty ? '.' : ': “$trimmed”'}',
    );
    return OvertimeReviewItem(employee: account.toRef(), request: updated);
  }
}
