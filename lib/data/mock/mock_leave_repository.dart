import 'package:flutter/foundation.dart';

import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../auth_repository.dart';
import '../leave_repository.dart';
import '../notification_repository.dart';
import 'mock_store.dart';

/// Cuti palsu. Validasi di sini meniru yang WAJIB dilakukan server.
class MockLeaveRepository implements LeaveRepository {
  MockLeaveRepository(
    this.store, {
    this.latency = const Duration(milliseconds: 600),
  });

  final MockStore store;
  final Duration latency;

  @override
  Listenable get changes => store.leaveChanges;
  @override
  Future<void> delete(AuthUser actor, {required String id}) async {
    await Future<void>.delayed(latency);
    if (actor.role != UserRole.superadmin) {
      throw const PermissionDeniedException(
        'Hanya Super Admin yang dapat menghapus riwayat.',
      );
    }
    for (final entry in store.leaveRequests.entries) {
      final idx = entry.value.indexWhere((r) => r.id == id);
      if (idx >= 0) {
        entry.value.removeAt(idx);
        store.leaveChanges.ping();
        break;
      }
    }
  }

  List<LeaveRequest> _list(AuthUser user) => _listOf(user.username);

  List<LeaveRequest> _listOf(String username) =>
      store.leaveRequests.putIfAbsent(username, () => []);

  LeaveBalance _balance(AuthUser user) => _balanceOf(user.username);

  LeaveBalance _balanceOf(String username) {
    final year = store.now().year;
    var used = 0;
    var pending = 0;
    for (final r in _listOf(username)) {
      if (r.type != LeaveType.annual || r.start.year != year) continue;
      if (r.status == RequestStatus.approved) used += r.workingDays;
      if (r.status == RequestStatus.pending) pending += r.workingDays;
    }
    return LeaveBalance(
      year: year,
      quota: WorkPolicy.annualLeaveQuota,
      used: used,
      pending: pending,
    );
  }

  @override
  Future<LeaveBalance> fetchBalance(AuthUser user) async {
    await Future<void>.delayed(latency);
    return _balance(user);
  }

  @override
  Future<List<LeaveRequest>> fetchRequests(AuthUser user) async {
    await Future<void>.delayed(latency);
    final sorted = [..._list(user)]
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return List.unmodifiable(sorted);
  }

  @override
  Future<LeaveRequest> submit(
    AuthUser user, {
    required LeaveType type,
    required DateTime start,
    required DateTime end,
    required String reason,
    LeaveAttachment? attachment,
  }) async {
    await Future<void>.delayed(latency);
    final today = WorkCalendar.dateOnly(store.now());
    var s = WorkCalendar.dateOnly(start);
    var e = WorkCalendar.dateOnly(end);

    // Cuti melahirkan: 3 bulan kalender otomatis sejak hari pengajuan,
    // tanggal dari pemohon diabaikan.
    if (type == LeaveType.maternity) {
      s = today;
      e = WorkCalendar.dateOnly(
        WorkCalendar.addMonths(today, LeaveRules.maternityMonths),
      );
    }

    if (e.isBefore(s)) {
      throw const AppException(
        'Tanggal selesai tidak boleh sebelum tanggal mulai.',
      );
    }
    final earliest = today.subtract(Duration(days: type.maxDaysBack));
    if (s.isBefore(earliest)) {
      throw AppException(
        type.maxDaysBack == 0
            ? '${type.label} tidak bisa diajukan untuk tanggal yang sudah lewat.'
            : '${type.label} paling lambat diajukan '
                  '${type.maxDaysBack} hari setelah tanggal mulai.',
      );
    }
    if (e.isAfter(today.add(const Duration(days: LeaveRules.maxDaysAhead)))) {
      throw const AppException(
        'Pengajuan paling jauh ${LeaveRules.maxDaysAhead} hari ke depan.',
      );
    }
    final days = WorkCalendar.workingDaysBetween(s, e);
    if (days == 0) {
      throw const AppException(
        'Rentang tanggal hanya berisi hari libur akhir pekan.',
      );
    }
    if (reason.trim().length < 5) {
      throw const AppException('Alasan minimal 5 karakter.');
    }
    if (LeaveRules.attachmentRequired(type, days) && attachment == null) {
      throw const AppException(
        'Sakit ${LeaveRules.sickAttachmentFromDays} hari atau lebih wajib '
        'melampirkan surat dokter.',
      );
    }
    if (attachment != null && attachment.sizeBytes > LeaveAttachment.maxBytes) {
      throw const AppException('Ukuran lampiran maksimal 2 MB.');
    }
    if (type.usesQuota) {
      final balance = _balance(user);
      if (days > balance.available) {
        throw AppException(
          'Sisa cuti tahunan yang bisa diajukan ${balance.available} hari.',
        );
      }
    }
    for (final r in _list(user)) {
      final active =
          r.status == RequestStatus.pending ||
          r.status == RequestStatus.approved;
      if (active && WorkCalendar.rangesOverlap(r.start, r.end, s, e)) {
        throw AppException(
          'Bertabrakan dengan pengajuan ${r.type.label.toLowerCase()} '
          'tanggal ${_range(r)} (${r.status.label.toLowerCase()}).',
        );
      }
    }

    final request = LeaveRequest(
      id: store.nextId('LV'),
      type: type,
      start: s,
      end: e,
      workingDays: days,
      reason: reason.trim(),
      status: RequestStatus.pending,
      submittedAt: store.now(),
      attachment: attachment,
    );
    _list(user).add(request);
    store.leaveChanges.ping();

    final requester = store.account(user.username);
    if (requester != null) {
      final what = type.label.toLowerCase();
      for (final reviewer in store.reviewersFor(requester)) {
        store.notify(
          reviewer.username,
          kind: NotificationKind.reviewRequested,
          title: 'Pengajuan $what baru',
          body:
              '${requester.fullName} mengajukan $what '
              '${DateFormatId.dateRange(s, e)} ($days hari).',
        );
      }
    }
    return request;
  }

  @override
  Future<LeaveRequest> cancel(AuthUser user, {required String id}) async {
    await Future<void>.delayed(latency);
    final list = _list(user);
    final index = list.indexWhere((r) => r.id == id);
    if (index < 0) {
      throw const AppException('Pengajuan tidak ditemukan.');
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
    list[index] = updated;
    store.leaveChanges.ping();
    return updated;
  }

  // ---------------------------------------------------------------------------
  // Persetujuan (Manager / Super Admin)
  // ---------------------------------------------------------------------------

  void _requireReviewer(AuthUser actor) {
    if (!actor.role.canReviewRequests) {
      throw const PermissionDeniedException(
        'Hanya Manager dan Super Admin yang dapat memproses pengajuan.',
      );
    }
  }

  LeaveReviewItem _item(MockAccount account, LeaveRequest request) =>
      LeaveReviewItem(
        employee: account.toRef(),
        request: request,
        balance: _balanceOf(account.username),
      );

  @override
  Future<List<LeaveReviewItem>> fetchReviewQueue(AuthUser actor) async {
    await Future<void>.delayed(latency);
    _requireReviewer(actor);
    final pending = <LeaveReviewItem>[];
    final done = <LeaveReviewItem>[];
    for (final entry in store.leaveRequests.entries) {
      final account = store.account(entry.key);
      if (account == null || !store.canActOn(actor, account)) continue;
      for (final r in entry.value) {
        if (r.status == RequestStatus.cancelled) continue;
        (r.status == RequestStatus.pending ? pending : done).add(
          _item(account, r),
        );
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
  Future<LeaveReviewItem> review(
    AuthUser actor, {
    required String id,
    required bool approve,
    String? note,
  }) async {
    await Future<void>.delayed(latency);
    _requireReviewer(actor);

    MockAccount? account;
    var index = -1;
    for (final entry in store.leaveRequests.entries) {
      final i = entry.value.indexWhere((r) => r.id == id);
      if (i >= 0) {
        account = store.account(entry.key);
        index = i;
        break;
      }
    }
    if (account == null || index < 0) {
      throw const AppException('Pengajuan tidak ditemukan.');
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

    final list = _listOf(account.username);
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
    if (approve && current.type.usesQuota) {
      final b = _balanceOf(account.username);
      if (current.workingDays > b.remaining) {
        throw AppException(
          'Sisa cuti tahunan ${account.fullName} tinggal ${b.remaining} hari, '
          'tidak cukup untuk ${current.workingDays} hari.',
        );
      }
    }

    final updated = current.copyWith(
      status: approve ? RequestStatus.approved : RequestStatus.rejected,
      reviewedAt: store.now(),
      reviewedBy: actor.fullName,
      reviewerNote: trimmed.isEmpty ? null : trimmed,
    );
    list[index] = updated;
    store.leaveChanges.ping();
    // Cuti yang disetujui mengubah riwayat absensi.
    store.attendanceChanges.ping();

    final range = DateFormatId.dateRange(updated.start, updated.end);
    final verb = approve ? 'disetujui' : 'ditolak';
    store.notify(
      account.username,
      kind: approve
          ? NotificationKind.leaveApproved
          : NotificationKind.leaveRejected,
      title: '${updated.type.label} $verb',
      body:
          '${updated.type.label} $range $verb oleh ${actor.fullName}'
          '${trimmed.isEmpty ? '.' : ': “$trimmed”'}',
    );
    return _item(account, updated);
  }

  @override
  Future<List<CollectiveLeaveResult>> applyCollectiveLeave(
    AuthUser actor, {
    required List<String> usernames,
    required DateTime start,
    required DateTime end,
    required String reason,
  }) async {
    await Future<void>.delayed(latency);
    if (actor.role != UserRole.superadmin) {
      throw const PermissionDeniedException(
        'Hanya Super Admin yang dapat memotong cuti bersama.',
      );
    }
    final s = WorkCalendar.dateOnly(start);
    final e = WorkCalendar.dateOnly(end);
    if (e.isBefore(s)) {
      throw const AppException(
        'Tanggal selesai tidak boleh sebelum tanggal mulai.',
      );
    }
    final days = WorkCalendar.workingDaysBetween(s, e);
    if (days == 0) {
      throw const AppException(
        'Rentang tanggal hanya berisi hari libur akhir pekan.',
      );
    }
    final trimmed = reason.trim();
    if (trimmed.length < 5) {
      throw const AppException('Alasan minimal 5 karakter.');
    }
    final targets = {
      for (final u in usernames) u.trim().toLowerCase(),
    }.where((u) => u.isNotEmpty).toList();
    if (targets.isEmpty) {
      throw const AppException('Pilih minimal satu karyawan.');
    }

    final results = <CollectiveLeaveResult>[];
    for (final username in targets) {
      final account = store.account(username);
      if (account == null || !account.active) {
        results.add(
          CollectiveLeaveResult(
            employee: EmployeeRef(username: username, fullName: username),
            days: 0,
            skipped: 'Akun tidak ditemukan atau nonaktif.',
          ),
        );
        continue;
      }
      // Tanggal yang sudah tercakup cuti tahunan yang disetujui tidak
      // dipotong dua kali.
      var effective = 0;
      var day = s;
      while (!day.isAfter(e)) {
        if (!WorkCalendar.isWeekend(day) && !_hasApprovedAnnualOn(username, day)) {
          effective++;
        }
        day = DateTime(day.year, day.month, day.day + 1);
      }
      if (effective == 0) {
        results.add(
          CollectiveLeaveResult(
            employee: account.toRef(),
            days: 0,
            skipped: 'Sudah tercakup cuti yang disetujui.',
          ),
        );
        continue;
      }
      final request = LeaveRequest(
        id: store.nextId('LV'),
        type: LeaveType.annual,
        start: s,
        end: e,
        workingDays: effective,
        reason: trimmed,
        status: RequestStatus.approved,
        submittedAt: store.now(),
        reviewedBy: actor.fullName,
        reviewedAt: store.now(),
      );
      _listOf(username).add(request);
      final remaining = _balanceOf(username).remaining;
      store.notify(
        username,
        kind: NotificationKind.collectiveLeaveApplied,
        title: 'Cuti bersama: $effective hari terpotong',
        body:
            '$trimmed (${DateFormatId.dateRange(s, e)}) memotong '
            '$effective hari cuti tahunan Anda. Sisa $remaining hari.',
      );
      results.add(
        CollectiveLeaveResult(employee: account.toRef(), days: effective),
      );
    }
    store.leaveChanges.ping();
    store.attendanceChanges.ping();
    return List.unmodifiable(results);
  }

  /// Apakah [username] sudah punya cuti tahunan yang disetujui pada [day].
  bool _hasApprovedAnnualOn(String username, DateTime day) {
    for (final r in _listOf(username)) {
      if (r.type != LeaveType.annual) continue;
      if (r.status != RequestStatus.approved) continue;
      if (!day.isBefore(r.start) && !day.isAfter(r.end)) return true;
    }
    return false;
  }

  static String _range(LeaveRequest r) {
    String d(DateTime x) => '${x.day}/${x.month}/${x.year}';
    return WorkCalendar.isSameDay(r.start, r.end)
        ? d(r.start)
        : '${d(r.start)}–${d(r.end)}';
  }
}
