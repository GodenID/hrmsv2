import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../attendance_repository.dart';
import '../auth_repository.dart';
import '../leave_repository.dart';
import '../notification_repository.dart';
import 'mock_store.dart';

/// Absensi palsu.
/// - Hari ini: dari clock in/out sungguhan (jam perangkat; di backend: jam
///   server).
/// - Hari sebelumnya: dibangkitkan secara deterministik per karyawan &
///   tanggal, sehingga konsisten selama aplikasi berjalan.
/// - Cuti yang disetujui & koreksi yang disetujui ikut diperhitungkan.
class MockAttendanceRepository implements AttendanceRepository {
  MockAttendanceRepository(
    this.store, {
    this.latency = const Duration(milliseconds: 600),
  });

  final MockStore store;
  final Duration latency;

  @override
  Listenable get changes => store.attendanceChanges;

  DateTime get _today => WorkCalendar.dateOnly(store.now());

  AttendanceRecord _currentToday(String username) {
    final today = _today;
    final record = store.todayRecords[username];
    if (record == null || record.date != today) {
      return AttendanceRecord(date: today);
    }
    return record;
  }

  @override
  Future<AttendanceRecord> fetchToday(AuthUser user) async {
    await Future<void>.delayed(latency);
    return _currentToday(user.username);
  }

  @override
  Future<AttendanceRecord> clockIn(
    AuthUser user, {
    required GeoPoint position,
  }) async {
    await Future<void>.delayed(latency);
    final record = _currentToday(user.username);
    if (record.clockIn != null) {
      throw const AppException('Anda sudah clock in hari ini.');
    }
    final place = _requireInsideArea(position);
    final updated = AttendanceRecord(
      date: record.date,
      clockIn: store.now(),
      clockInLocation: place.name,
    );
    store.todayRecords[user.username] = updated;
    store.attendanceChanges.ping();
    return updated;
  }

  @override
  Future<AttendanceRecord> clockOut(
    AuthUser user, {
    required GeoPoint position,
  }) async {
    await Future<void>.delayed(latency);
    final record = _currentToday(user.username);
    if (record.clockIn == null) {
      throw const AppException('Silakan clock in terlebih dahulu.');
    }
    if (record.clockOut != null) {
      throw const AppException('Anda sudah clock out hari ini.');
    }
    final place = _requireInsideArea(position);
    final updated = AttendanceRecord(
      date: record.date,
      clockIn: record.clockIn,
      clockOut: store.now(),
      clockInLocation: record.clockInLocation,
      clockOutLocation: place.name,
    );
    store.todayRecords[user.username] = updated;
    store.attendanceChanges.ping();
    return updated;
  }

  /// Lokasi absen yang memuat [p], atau galat yang menjelaskan jaraknya.
  AttendanceLocation _requireInsideArea(GeoPoint p) {
    if (p.isMocked) {
      throw const AppException(
        'Lokasi palsu terdeteksi. Matikan aplikasi pemalsu lokasi (mock '
        'location) lalu coba lagi.',
      );
    }
    final locations = store.attendanceLocations;
    if (locations.isEmpty) {
      throw const AppException(
        'Belum ada lokasi absen yang diatur. Hubungi Super Admin.',
      );
    }
    AttendanceLocation? nearest;
    var best = double.infinity;
    for (final l in locations) {
      final d = l.distanceTo(p.latitude, p.longitude);
      if (d <= l.radiusMeters) return l;
      if (d - l.radiusMeters < best) {
        best = d - l.radiusMeters;
        nearest = l;
      }
    }
    final distance = nearest!.distanceTo(p.latitude, p.longitude);
    final accuracy = p.accuracyMeters;
    throw AppException(
      'Anda berada di luar area absen. Lokasi terdekat: ${nearest.name}, '
      '${GeoMath.formatDistance(distance)} dari posisi Anda (radius '
      '${nearest.radiusMeters} m).'
      '${accuracy != null && accuracy > 100 ? ' Akurasi lokasi perangkat ±${GeoMath.formatDistance(accuracy)}; aktifkan GPS / lokasi akurat lalu coba lagi.' : ''}',
    );
  }

  // ---------------------------------------------------------------------------
  // Lokasi absen (Super Admin)
  // ---------------------------------------------------------------------------

  void _requireLocationManager(AuthUser actor) {
    if (!actor.role.canManageAttendanceLocations) {
      throw const PermissionDeniedException(
        'Hanya Super Admin yang dapat mengatur lokasi absen.',
      );
    }
  }

  @override
  Future<List<AttendanceLocation>> fetchLocations(AuthUser user) async {
    await Future<void>.delayed(latency ~/ 2);
    return List.unmodifiable(store.attendanceLocations);
  }

  @override
  Future<AttendanceLocation> saveLocation(
    AuthUser actor, {
    String? id,
    required AttendanceLocationDraft draft,
  }) async {
    await Future<void>.delayed(latency);
    _requireLocationManager(actor);
    final name = draft.name.trim();
    final error =
        LocationRules.validateName(name) ??
        LocationRules.validateLatitude('${draft.latitude}') ??
        LocationRules.validateLongitude('${draft.longitude}') ??
        LocationRules.validateRadius(draft.radiusMeters);
    if (error != null) throw AppException(error);

    final list = store.attendanceLocations;
    final index = id == null ? -1 : list.indexWhere((l) => l.id == id);
    if (id != null && index < 0) {
      throw const AppException('Lokasi tidak ditemukan. Muat ulang daftar.');
    }
    final duplicate = list.any(
      (l) => l.id != id && l.name.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      throw AppException('Nama lokasi "$name" sudah dipakai.');
    }
    final saved = AttendanceLocation(
      id: id ?? store.nextId('LOC'),
      name: name,
      latitude: draft.latitude,
      longitude: draft.longitude,
      radiusMeters: draft.radiusMeters,
    );
    if (index >= 0) {
      list[index] = saved;
    } else {
      list.add(saved);
    }
    store.attendanceChanges.ping();
    return saved;
  }

  @override
  Future<void> deleteLocation(AuthUser actor, {required String id}) async {
    await Future<void>.delayed(latency);
    _requireLocationManager(actor);
    final list = store.attendanceLocations;
    if (!list.any((l) => l.id == id)) {
      throw const AppException('Lokasi tidak ditemukan. Muat ulang daftar.');
    }
    if (list.length == 1) {
      throw const AppException(
        'Minimal harus ada satu lokasi absen. Ubah lokasi ini bila perlu.',
      );
    }
    list.removeWhere((l) => l.id == id);
    store.attendanceChanges.ping();
  }

  @override
  Future<DateTime> fetchFirstMonth(AuthUser user) async {
    await Future<void>.delayed(latency);
    final join = store.account(user.username)?.joinDate ?? _today;
    return DateTime(join.year, join.month);
  }

  @override
  Future<List<AttendanceDay>> fetchMonth(
    AuthUser user, {
    required int year,
    required int month,
  }) async {
    await Future<void>.delayed(latency);
    final account = store.account(user.username);
    if (account == null) return const [];

    final today = _today;
    final join = WorkCalendar.dateOnly(account.joinDate);
    // Menunggu & disetujui sama-sama tampil di kalender begitu diajukan.
    final activeLeave = [
      for (final r in store.leaveRequests[user.username] ?? <LeaveRequest>[])
        if (r.status == RequestStatus.approved ||
            r.status == RequestStatus.pending)
          r,
    ];
    final corrections =
        store.corrections[user.username] ?? <AttendanceCorrection>[];

    final days = <AttendanceDay>[];
    final lastDay = DateTime(year, month + 1, 0).day;
    for (var d = 1; d <= lastDay; d++) {
      final date = DateTime(year, month, d);
      if (date.isBefore(join)) continue;

      final weekend = WorkCalendar.isWeekend(date);
      // Akhir pekan tidak dihitung sebagai hari cuti.
      final leave = weekend ? null : _leaveOn(activeLeave, date);
      final leaveApproved = leave?.status == RequestStatus.approved;
      final correction = _latestCorrection(corrections, date);

      if (date.isAfter(today)) {
        if (leave != null) {
          days.add(
            AttendanceDay(
              date: date,
              status: leaveApproved
                  ? AttendanceDayStatus.leave
                  : AttendanceDayStatus.upcoming,
              leave: leave,
            ),
          );
        }
        continue;
      }
      if (WorkCalendar.isSameDay(date, today)) {
        days.add(_todayEntry(user.username, date, correction, leave));
        continue;
      }
      if (weekend) continue;
      if (leaveApproved) {
        days.add(
          AttendanceDay(
            date: date,
            status: AttendanceDayStatus.leave,
            leave: leave,
            correction: correction,
          ),
        );
        continue;
      }
      days.add(_generated(user.username, date, correction, leave: leave));
    }
    return days.reversed.toList(growable: false);
  }

  /// Pengajuan lembur terakhir (menunggu/disetujui) untuk tanggal [date].
  OvertimeRequest? _latestOvertime(String username, DateTime date) {
    OvertimeRequest? latest;
    for (final r in store.overtimeRequests[username] ??
        const <OvertimeRequest>[]) {
      if (r.status != RequestStatus.pending &&
          r.status != RequestStatus.approved) {
        continue;
      }
      if (!WorkCalendar.isSameDay(r.date, date)) continue;
      if (latest == null || r.submittedAt.isAfter(latest.submittedAt)) {
        latest = r;
      }
    }
    return latest;
  }

  /// Pengajuan luar-area terakhir untuk tanggal [date], bila ada.
  OutOfAreaRequest? _latestOutOfArea(String username, DateTime date) {
    OutOfAreaRequest? latest;
    for (final r in store.outOfArea[username] ?? const <OutOfAreaRequest>[]) {
      if (!WorkCalendar.isSameDay(r.date, date)) continue;
      if (latest == null || r.submittedAt.isAfter(latest.submittedAt)) {
        latest = r;
      }
    }
    return latest;
  }

  AttendanceDay _todayEntry(
    String username,
    DateTime date,
    AttendanceCorrection? correction,
    LeaveRequest? leave,
  ) {
    final r = _currentToday(username);
    final status = switch (r.status) {
      AttendanceStatus.notClockedIn =>
        leave?.status == RequestStatus.approved
            ? AttendanceDayStatus.leave
            : WorkCalendar.isWeekend(date)
            ? AttendanceDayStatus.dayOff
            : AttendanceDayStatus.notYet,
      AttendanceStatus.working => AttendanceDayStatus.inProgress,
      AttendanceStatus.finished =>
        WorkPolicy.isLate(r.clockIn!)
            ? AttendanceDayStatus.late
            : AttendanceDayStatus.onTime,
    };
    return AttendanceDay(
      date: date,
      status: status,
      clockIn: r.clockIn,
      clockOut: r.clockOut,
      clockInLocation: r.clockInLocation,
      clockOutLocation: r.clockOutLocation,
      leave: leave,
      correction: correction,
      outOfArea: _latestOutOfArea(username, date),
      overtime: _latestOvertime(username, date),
    );
  }

  AttendanceDay _generated(
    String username,
    DateTime date,
    AttendanceCorrection? correction, {
    LeaveRequest? leave,
  }) {
    DateTime? clockIn;
    DateTime? clockOut;

    final override = _demoOverrides['$username|${_key(date)}'];
    final rnd = Random(_hash('$username|${_key(date)}'));
    final roll = rnd.nextInt(100);
    final kind =
        override ??
        (roll < 2 ? 'absent' : (roll < 6 ? 'incomplete' : 'normal'));

    if (kind != 'absent') {
      var minutes = 7 * 60 + 30 + rnd.nextInt(80); // 07:30–08:50
      if (kind == 'late' || (override == null && rnd.nextInt(100) < 10)) {
        minutes = 9 * 60 + 1 + rnd.nextInt(40); // 09:01–09:41
      }
      clockIn = DateTime(
        date.year,
        date.month,
        date.day,
        minutes ~/ 60,
        minutes % 60,
        rnd.nextInt(60),
      );
      if (kind != 'incomplete') {
        clockOut = clockIn.add(
          WorkPolicy.requiredDailyWork +
              Duration(minutes: rnd.nextInt(75), seconds: rnd.nextInt(60)),
        );
      }
    }

    // Pengajuan luar-area yang disetujui menggantikan catatan asli.
    for (final o in store.outOfArea[username] ?? const <OutOfAreaRequest>[]) {
      if (o.status != RequestStatus.approved) continue;
      if (!WorkCalendar.isSameDay(o.date, date)) continue;
      if (o.kind == OutOfAreaKind.clockIn) {
        clockIn = o.requestedAt;
      } else {
        clockOut = o.requestedAt;
      }
    }

    // Koreksi yang disetujui menggantikan catatan asli.
    if (correction?.status == RequestStatus.approved) {
      clockIn = correction!.clockIn;
      clockOut = correction.clockOut;
    }

    final AttendanceDayStatus status;
    if (clockIn == null) {
      status = AttendanceDayStatus.absent;
    } else if (clockOut == null) {
      status = AttendanceDayStatus.incomplete;
    } else {
      status = WorkPolicy.isLate(clockIn)
          ? AttendanceDayStatus.late
          : AttendanceDayStatus.onTime;
    }
    return AttendanceDay(
      date: date,
      status: status,
      clockIn: clockIn,
      clockOut: clockOut,
      leave: leave,
      correction: correction,
      outOfArea: _latestOutOfArea(username, date),
      overtime: _latestOvertime(username, date),
    );
  }

  @override
  Future<AttendanceCorrection> submitCorrection(
    AuthUser user, {
    required DateTime date,
    required DateTime clockIn,
    required DateTime clockOut,
    required String reason,
  }) async {
    await Future<void>.delayed(latency);
    final day = WorkCalendar.dateOnly(date);
    final today = _today;
    if (!day.isBefore(today)) {
      throw const AppException(
        'Koreksi hanya bisa diajukan untuk hari yang sudah lewat.',
      );
    }
    if (today.difference(day).inDays > WorkPolicy.correctionWindowDays) {
      throw const AppException(
        'Koreksi hanya bisa diajukan untuk '
        '${WorkPolicy.correctionWindowDays} hari terakhir.',
      );
    }
    if (!WorkCalendar.isSameDay(clockIn, day) ||
        !WorkCalendar.isSameDay(clockOut, day)) {
      throw const AppException('Jam koreksi harus pada tanggal yang sama.');
    }
    if (!clockOut.isAfter(clockIn)) {
      throw const AppException('Jam pulang harus setelah jam masuk.');
    }
    if (reason.trim().length < 10) {
      throw const AppException('Alasan minimal 10 karakter.');
    }
    final list = store.corrections.putIfAbsent(user.username, () => []);
    if (list.any(
      (c) =>
          WorkCalendar.isSameDay(c.date, day) &&
          c.status == RequestStatus.pending,
    )) {
      throw const AppException(
        'Masih ada pengajuan koreksi yang menunggu untuk tanggal ini.',
      );
    }
    final correction = AttendanceCorrection(
      id: store.nextId('KR'),
      date: day,
      clockIn: clockIn,
      clockOut: clockOut,
      reason: reason.trim(),
      status: RequestStatus.pending,
      submittedAt: store.now(),
    );
    list.add(correction);
    store.attendanceChanges.ping();

    final requester = store.account(user.username);
    if (requester != null) {
      for (final reviewer in store.reviewersFor(requester)) {
        store.notify(
          reviewer.username,
          kind: NotificationKind.reviewRequested,
          title: 'Koreksi absensi baru',
          body:
              '${requester.fullName} mengajukan koreksi absensi '
              '${DateFormatId.shortDate(day)}.',
        );
      }
    }
    return correction;
  }

  @override
  Future<AttendanceCorrection> cancelCorrection(
    AuthUser user, {
    required String id,
  }) async {
    await Future<void>.delayed(latency);
    final list = store.corrections[user.username] ?? const [];
    final index = list.indexWhere((c) => c.id == id);
    if (index < 0) {
      throw const AppException('Pengajuan koreksi tidak ditemukan.');
    }
    final current = list[index];
    if (current.status != RequestStatus.pending) {
      throw const AppException(
        'Hanya pengajuan yang masih menunggu yang bisa dibatalkan.',
      );
    }
    final updated = AttendanceCorrection(
      id: current.id,
      date: current.date,
      clockIn: current.clockIn,
      clockOut: current.clockOut,
      reason: current.reason,
      status: RequestStatus.cancelled,
      submittedAt: current.submittedAt,
    );
    store.corrections[user.username]![index] = updated;
    store.attendanceChanges.ping();
    return updated;
  }

  @override
  Future<OutOfAreaRequest> cancelOutOfArea(
    AuthUser user, {
    required String id,
  }) async {
    await Future<void>.delayed(latency);
    final list = store.outOfArea[user.username] ?? const [];
    final index = list.indexWhere((r) => r.id == id);
    if (index < 0) {
      throw const AppException('Pengajuan luar area tidak ditemukan.');
    }
    final current = list[index];
    if (current.status != RequestStatus.pending) {
      throw const AppException(
        'Hanya pengajuan yang masih menunggu yang bisa dibatalkan.',
      );
    }
    final updated = OutOfAreaRequest(
      id: current.id,
      date: current.date,
      kind: current.kind,
      requestedAt: current.requestedAt,
      latitude: current.latitude,
      longitude: current.longitude,
      accuracyMeters: current.accuracyMeters,
      nearestLocationName: current.nearestLocationName,
      distanceMeters: current.distanceMeters,
      reason: current.reason,
      status: RequestStatus.cancelled,
      submittedAt: current.submittedAt,
    );
    store.outOfArea[user.username]![index] = updated;
    store.attendanceChanges.ping();
    return updated;
  }

  // ---------------------------------------------------------------------------
  // Persetujuan koreksi (Manager / Super Admin)
  // ---------------------------------------------------------------------------

  void _requireReviewer(AuthUser actor) {
    if (!actor.role.canReviewRequests) {
      throw const PermissionDeniedException(
        'Hanya Manager dan Super Admin yang dapat memproses koreksi absensi.',
      );
    }
  }

  /// Catatan asli sistem untuk tanggal koreksi (tanpa koreksi apa pun).
  CorrectionReviewItem _item(MockAccount account, AttendanceCorrection c) {
    final DateTime? clockIn;
    final DateTime? clockOut;
    if (WorkCalendar.isSameDay(c.date, _today)) {
      final r = _currentToday(account.username);
      clockIn = r.clockIn;
      clockOut = r.clockOut;
    } else {
      final original = _generated(account.username, c.date, null);
      clockIn = original.clockIn;
      clockOut = original.clockOut;
    }
    return CorrectionReviewItem(
      employee: account.toRef(),
      correction: c,
      recordedClockIn: clockIn,
      recordedClockOut: clockOut,
    );
  }

  @override
  Future<List<CorrectionReviewItem>> fetchCorrectionQueue(
    AuthUser actor,
  ) async {
    await Future<void>.delayed(latency);
    _requireReviewer(actor);
    final pending = <CorrectionReviewItem>[];
    final done = <CorrectionReviewItem>[];
    for (final entry in store.corrections.entries) {
      final account = store.account(entry.key);
      if (account == null || !store.canActOn(actor, account)) continue;
      for (final c in entry.value) {
        if (c.status == RequestStatus.cancelled) continue;
        (c.status == RequestStatus.pending ? pending : done).add(
          _item(account, c),
        );
      }
    }
    pending.sort(
      (a, b) => a.correction.submittedAt.compareTo(b.correction.submittedAt),
    );
    done.sort((a, b) {
      final x = a.correction.reviewedAt ?? a.correction.submittedAt;
      final y = b.correction.reviewedAt ?? b.correction.submittedAt;
      return y.compareTo(x);
    });
    return List.unmodifiable([...pending, ...done]);
  }

  @override
  Future<CorrectionReviewItem> reviewCorrection(
    AuthUser actor, {
    required String id,
    required bool approve,
    String? note,
  }) async {
    await Future<void>.delayed(latency);
    _requireReviewer(actor);

    MockAccount? account;
    var index = -1;
    for (final entry in store.corrections.entries) {
      final i = entry.value.indexWhere((c) => c.id == id);
      if (i >= 0) {
        account = store.account(entry.key);
        index = i;
        break;
      }
    }
    if (account == null || index < 0) {
      throw const AppException('Pengajuan koreksi tidak ditemukan.');
    }
    if (account.username == actor.username) {
      throw const PermissionDeniedException(
        'Anda tidak dapat memproses koreksi Anda sendiri.',
      );
    }
    if (!store.canActOn(actor, account)) {
      throw const PermissionDeniedException(
        'Anda tidak berhak memproses koreksi karyawan ini.',
      );
    }

    final list = store.corrections[account.username]!;
    final current = list[index];
    if (current.status != RequestStatus.pending) {
      throw AppException(
        'Koreksi ini sudah ${current.status.label.toLowerCase()}. '
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
    store.attendanceChanges.ping();

    final verb = approve ? 'disetujui' : 'ditolak';
    store.notify(
      account.username,
      kind: approve
          ? NotificationKind.correctionApproved
          : NotificationKind.correctionRejected,
      title: 'Koreksi absensi $verb',
      body:
          'Koreksi absensi ${DateFormatId.shortDate(updated.date)} $verb oleh '
          '${actor.fullName}${trimmed.isEmpty ? '.' : ': “$trimmed”'}',
    );
    return _item(account, updated);
  }

  // ---------------------------------------------------------------------------
  // Pengajuan luar area
  // ---------------------------------------------------------------------------

  /// Lokasi absen terdekat dari [p] (null bila belum ada lokasi sama sekali).
  AttendanceLocation? _nearestLocation(GeoPoint p) {
    AttendanceLocation? best;
    var bestDistance = double.infinity;
    for (final l in store.attendanceLocations) {
      final d = l.distanceTo(p.latitude, p.longitude);
      if (d < bestDistance) {
        bestDistance = d;
        best = l;
      }
    }
    return best;
  }

  @override
  Future<OutOfAreaRequest> submitOutOfArea(
    AuthUser user, {
    required OutOfAreaKind kind,
    required GeoPoint position,
    required String reason,
  }) async {
    await Future<void>.delayed(latency);
    if (position.isMocked) {
      throw const AppException(
        'Lokasi palsu terdeteksi. Matikan aplikasi pemalsu lokasi (mock '
        'location) lalu coba lagi.',
      );
    }
    final locations = store.attendanceLocations;
    if (locations.isEmpty) {
      throw const AppException(
        'Belum ada lokasi absen yang diatur. Hubungi Super Admin.',
      );
    }
    // Di dalam radius → pakai tombol clock biasa, bukan pengajuan.
    for (final l in locations) {
      if (l.distanceTo(position.latitude, position.longitude) <=
          l.radiusMeters) {
        throw AppException(
          'Anda berada di dalam area ${l.name}. Pakai tombol '
          '${kind.label} biasa.',
        );
      }
    }
    final trimmed = reason.trim();
    if (trimmed.length < OutOfAreaRules.minReasonLength) {
      throw const AppException(
        'Alasan minimal ${OutOfAreaRules.minReasonLength} karakter.',
      );
    }
    final record = _currentToday(user.username);
    final isIn = kind == OutOfAreaKind.clockIn;
    if (isIn && record.clockIn != null) {
      throw const AppException('Jam clock in hari ini sudah tercatat.');
    }
    if (!isIn && (record.clockIn == null || record.clockOut != null)) {
      throw const AppException(
        'Clock out luar area hanya bisa diajukan bila sudah clock in '
        'dan belum clock out.',
      );
    }
    final list = store.outOfArea.putIfAbsent(user.username, () => []);
    if (list.any(
      (r) =>
          WorkCalendar.isSameDay(r.date, _today) &&
          r.kind == kind &&
          r.status == RequestStatus.pending,
    )) {
      throw AppException(
        'Pengajuan ${kind.label} luar area hari ini masih menunggu '
        'persetujuan.',
      );
    }
    final nearest = _nearestLocation(position)!;
    final request = OutOfAreaRequest(
      id: store.nextId('OA'),
      date: _today,
      kind: kind,
      requestedAt: store.now(),
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracyMeters,
      nearestLocationName: nearest.name,
      distanceMeters: nearest.distanceTo(
        position.latitude,
        position.longitude,
      ),
      reason: trimmed,
      status: RequestStatus.pending,
      submittedAt: store.now(),
    );
    list.add(request);
    store.attendanceChanges.ping();

    final requester = store.account(user.username);
    if (requester != null) {
      for (final reviewer in store.reviewersFor(requester)) {
        store.notify(
          reviewer.username,
          kind: NotificationKind.reviewRequested,
          title: 'Pengajuan absensi luar area',
          body:
              '${requester.fullName} mengajukan ${kind.label.toLowerCase()} '
              'luar area (${GeoMath.formatDistance(request.distanceMeters)} '
              'dari ${nearest.name}).',
        );
      }
    }
    return request;
  }

  @override
  Future<List<OutOfAreaRequest>> fetchMyOutOfArea(AuthUser user) async {
    await Future<void>.delayed(latency);
    final list = [...store.outOfArea[user.username] ?? const <OutOfAreaRequest>[]]
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    return List.unmodifiable(list);
  }

  @override
  Future<List<OutOfAreaReviewItem>> fetchOutOfAreaQueue(
    AuthUser actor,
  ) async {
    await Future<void>.delayed(latency);
    _requireReviewer(actor);
    final pending = <OutOfAreaReviewItem>[];
    final done = <OutOfAreaReviewItem>[];
    for (final entry in store.outOfArea.entries) {
      final account = store.account(entry.key);
      if (account == null || !store.canActOn(actor, account)) continue;
      for (final r in entry.value) {
        if (r.status == RequestStatus.cancelled) continue;
        final item = OutOfAreaReviewItem(
          employee: account.toRef(),
          request: r,
          recordedClockIn: _recordedOn(account.username, r.date).clockIn,
          recordedClockOut: _recordedOn(account.username, r.date).clockOut,
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

  /// Catatan sistem untuk tanggal [date]: hari ini dari catatan harian,
  /// hari lalu dari pembangkit deterministik (tanpa koreksi/pengajuan).
  AttendanceDay _recordedOn(String username, DateTime date) {
    if (WorkCalendar.isSameDay(date, _today)) {
      final r = _currentToday(username);
      return AttendanceDay(
        date: date,
        status: AttendanceDayStatus.inProgress,
        clockIn: r.clockIn,
        clockOut: r.clockOut,
      );
    }
    return _generated(username, date, null);
  }

  @override
  Future<OutOfAreaReviewItem> reviewOutOfArea(
    AuthUser actor, {
    required String id,
    required bool approve,
    String? note,
  }) async {
    await Future<void>.delayed(latency);
    _requireReviewer(actor);

    MockAccount? account;
    var index = -1;
    for (final entry in store.outOfArea.entries) {
      final i = entry.value.indexWhere((r) => r.id == id);
      if (i >= 0) {
        account = store.account(entry.key);
        index = i;
        break;
      }
    }
    if (account == null || index < 0) {
      throw const AppException('Pengajuan luar area tidak ditemukan.');
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

    final list = store.outOfArea[account.username]!;
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

    // Disetujui = jam pengajuan ditulis sebagai jam clock in/out. Bila
    // tanggalnya hari ini, catatan harian ditulis langsung; bila sudah
    // lewat, riwayat membacanya dari pengajuan ini.
    if (approve && WorkCalendar.isSameDay(current.date, _today)) {
      final record = _currentToday(account.username);
      final label = '${current.nearestLocationName} (luar area)';
      if (current.kind == OutOfAreaKind.clockIn) {
        if (record.clockIn != null) {
          throw const AppException(
            'Jam clock in sudah tercatat. Muat ulang untuk melihat '
            'status terbaru.',
          );
        }
        store.todayRecords[account.username] = AttendanceRecord(
          date: record.date,
          clockIn: current.requestedAt,
          clockInLocation: label,
        );
      } else {
        if (record.clockIn == null || record.clockOut != null) {
          throw const AppException(
            'Kondisi catatan berubah. Muat ulang untuk melihat status '
            'terbaru.',
          );
        }
        store.todayRecords[account.username] = AttendanceRecord(
          date: record.date,
          clockIn: record.clockIn,
          clockOut: current.requestedAt,
          clockInLocation: record.clockInLocation,
          clockOutLocation: label,
        );
      }
    }
    store.attendanceChanges.ping();

    final verb = approve ? 'disetujui' : 'ditolak';
    store.notify(
      account.username,
      kind: approve
          ? NotificationKind.outOfAreaApproved
          : NotificationKind.outOfAreaRejected,
      title: 'Pengajuan luar area $verb',
      body:
          '${current.kind.label} luar area '
          '${DateFormatId.shortDate(current.date)} $verb oleh '
          '${actor.fullName}${trimmed.isEmpty ? '.' : ': “$trimmed”'}',
    );
    return OutOfAreaReviewItem(
      employee: account.toRef(),
      request: updated,
      recordedClockIn: _recordedOn(account.username, updated.date).clockIn,
      recordedClockOut: _recordedOn(account.username, updated.date).clockOut,
    );
  }

  static AttendanceCorrection? _latestCorrection(
    List<AttendanceCorrection> list,
    DateTime date,
  ) {
    AttendanceCorrection? latest;
    for (final c in list) {
      if (!WorkCalendar.isSameDay(c.date, date)) continue;
      if (latest == null || c.submittedAt.isAfter(latest.submittedAt)) {
        latest = c;
      }
    }
    return latest;
  }

  static LeaveRequest? _leaveOn(List<LeaveRequest> active, DateTime date) {
    for (final r in active) {
      if (WorkCalendar.rangesOverlap(r.start, r.end, date, date)) return r;
    }
    return null;
  }

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// FNV-1a: stabil antar-jalan (berbeda dengan String.hashCode).
  static int _hash(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  /// Contoh kasus agar riwayat demo selalu memuat hari bermasalah.
  static const Map<String, String> _demoOverrides = {
    'budi.santoso|2026-10-5': 'incomplete',
    'budi.santoso|2026-10-1': 'late',
    'budi.santoso|2026-9-29': 'normal',
    'budi.santoso|2026-9-23': 'absent',
    'rizky.ramadhan|2026-10-2': 'incomplete',
  };
}
