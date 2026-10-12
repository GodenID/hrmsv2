import 'package:flutter/foundation.dart';

import '../../core/utils/date_format_id.dart';
import '../auth_repository.dart';
import '../employee.dart';
import '../notification_repository.dart';
import '../warning_repository.dart';
import 'mock_store.dart';

/// Surat peringatan palsu. Aturan hak akses & eskalasi di sini meniru yang
/// WAJIB ditegakkan server (lihat [WarningRepository]).
///
/// Hanya Super Admin yang boleh membuat / menerbitkan SP. Manager membaca
/// dalam cakupannya, karyawan membaca miliknya sendiri.
class MockWarningRepository implements WarningRepository {
  MockWarningRepository(
    this.store, {
    this.latency = const Duration(milliseconds: 500),
  });

  final MockStore store;
  final Duration latency;

  @override
  Listenable get changes => store.warningChanges;

  DateTime get _now => store.now();

  /// SP milik [username] yang masih aktif (belum kedaluwarsa), terlama dulu.
  List<WarningLetter> _active(String username) {
    final now = _now;
    final list = [
      for (final l in store.warningLetters[username] ?? const <WarningLetter>[])
        if (l.isActive(now)) l,
    ]..sort((a, b) => a.issuedAt.compareTo(b.issuedAt));
    return list;
  }

  void _requireSuperAdmin(AuthUser actor) {
    if (actor.role != UserRole.superadmin) {
      throw const PermissionDeniedException(
        'Hanya Super Admin yang dapat menerbitkan surat peringatan.',
      );
    }
  }

  WarningLetterDetail _detail(MockAccount account, WarningLetter letter) =>
      WarningLetterDetail(employee: account.toRef(), letter: letter);

  List<WarningLetter> _sortedDesc(String username) {
    final list = [...store.warningLetters[username] ?? const <WarningLetter>[]]
      ..sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return list;
  }

  @override
  Future<List<EmployeeRef>> fetchIssuableEmployees(AuthUser actor) async {
    await Future<void>.delayed(latency);
    _requireSuperAdmin(actor);
    final list = [
      for (final a in store.accounts.values)
        if (a.active && a.username != actor.username) a.toRef(),
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    return List.unmodifiable(list);
  }

  @override
  Future<WarningSuggestion> suggestLevel(
    AuthUser actor, {
    required String username,
  }) async {
    await Future<void>.delayed(latency);
    _requireSuperAdmin(actor);
    final target = store.account(username);
    if (target == null || !target.active) {
      throw const AppException('Karyawan tidak ditemukan atau nonaktif.');
    }
    final active = _active(target.username);
    if (active.any((l) => l.level >= 3)) {
      return WarningSuggestion(
        suggestedLevel: 3,
        activeCount: active.length,
        phkEligible: true,
      );
    }
    return WarningSuggestion(
      suggestedLevel: (active.length + 1).clamp(1, 3),
      activeCount: active.length,
      phkEligible: false,
    );
  }

  @override
  Future<WarningLetterDetail> issue(
    AuthUser actor, {
    required String username,
    required String violationName,
    required WarningSeverity severity,
    required int level,
    required DateTime incidentDate,
    required String description,
    required String articleRef,
  }) async {
    await Future<void>.delayed(latency);
    _requireSuperAdmin(actor);
    final target = store.account(username);
    if (target == null || !target.active) {
      throw const AppException('Karyawan tidak ditemukan atau nonaktif.');
    }
    if (target.username == actor.username) {
      throw const PermissionDeniedException(
        'Anda tidak dapat menerbitkan SP untuk diri sendiri.',
      );
    }
    final nameError = WarningRules.validateViolationName(violationName);
    if (nameError != null) throw AppException(nameError);
    if (level < 1 || level > 3) {
      throw const AppException('Tingkat SP harus 1, 2, atau 3.');
    }
    final incident = DateTime(
      incidentDate.year,
      incidentDate.month,
      incidentDate.day,
    );
    final today = DateTime(_now.year, _now.month, _now.day);
    if (incident.isAfter(today)) {
      throw const AppException(
        'Tanggal kejadian tidak boleh di masa depan.',
      );
    }
    if (today.difference(incident).inDays > WarningRules.maxIncidentDaysBack) {
      throw AppException(
        'Kejadian lebih dari ${WarningRules.maxIncidentDaysBack} hari lalu '
        'sudah kedaluwarsa untuk diterbitkan SP.',
      );
    }
    final descError = WarningRules.validateDescription(description);
    if (descError != null) throw AppException(descError);
    final trimmedArticle = articleRef.trim();
    if (trimmedArticle.isEmpty) {
      throw const AppException('Pasal peraturan wajib diisi.');
    }

    final issuedAt = _now;
    final letter = WarningLetter(
      id: store.nextId('SP'),
      employeeUsername: target.username,
      violationName: violationName.trim(),
      severity: severity,
      level: level,
      incidentDate: incident,
      description: description.trim(),
      articleRef: trimmedArticle.length > WarningRules.maxArticle
          ? trimmedArticle.substring(0, WarningRules.maxArticle)
          : trimmedArticle,
      issuedBy: actor.username,
      issuedByName: actor.fullName,
      issuedAt: issuedAt,
      expiresAt: DateTime(
        issuedAt.year,
        issuedAt.month + WarningRules.validityMonths,
        issuedAt.day,
        issuedAt.hour,
        issuedAt.minute,
      ),
    );
    store.warningLetters.putIfAbsent(target.username, () => []).add(letter);
    store.warningChanges.ping();

    store.notify(
      target.username,
      kind: NotificationKind.warningIssued,
      title: 'Surat peringatan ${letter.levelLabel}',
      body:
          'Anda menerima ${letter.levelLabel} (${letter.violationName}). '
          'Buka untuk membaca dan menandatangani.',
    );
    for (final reviewer in store.reviewersFor(target)) {
      store.notify(
        reviewer.username,
        kind: NotificationKind.warningIssued,
        title: 'SP ${letter.levelLabel} diterbitkan',
        body:
            '${target.fullName} menerima ${letter.levelLabel} '
            '(${letter.violationName}) dari ${actor.fullName}.',
      );
    }
    return _detail(target, letter);
  }

  @override
  Future<List<WarningLetterDetail>> fetchLetters(AuthUser actor) async {
    await Future<void>.delayed(latency);
    if (actor.role == UserRole.staff) {
      throw const PermissionDeniedException(
        'Gunakan menu Peringatan untuk melihat SP Anda sendiri.',
      );
    }
    final out = <WarningLetterDetail>[];
    for (final entry in store.warningLetters.entries) {
      final account = store.account(entry.key);
      if (account == null) continue;
      if (actor.role == UserRole.manager &&
          !actor.role.canManageRole(account.role)) {
        continue;
      }
      for (final l in _sortedDesc(account.username)) {
        out.add(_detail(account, l));
      }
    }
    out.sort((a, b) => b.letter.issuedAt.compareTo(a.letter.issuedAt));
    _remindExpiring();
    return List.unmodifiable(out);
  }

  @override
  Future<List<WarningLetterDetail>> fetchMyLetters(AuthUser user) async {
    await Future<void>.delayed(latency);
    final account = store.account(user.username);
    if (account == null) {
      throw const AppException('Akun tidak ditemukan.');
    }
    return List.unmodifiable([
      for (final l in _sortedDesc(account.username)) _detail(account, l),
    ]);
  }

  /// Pengingat H-30 kedaluwarsa untuk para Super Admin (sekali per SP,
  /// memakai id stabil agar tidak duplikat).
  void _remindExpiring() {
    final now = _now;
    for (final entry in store.warningLetters.entries) {
      final account = store.account(entry.key);
      if (account == null || !account.active) continue;
      for (final l in entry.value) {
        if (!l.isExpiringSoon(now)) continue;
        final days = l.expiresAt.difference(now).inDays;
        for (final a in store.accounts.values) {
          if (!a.active || a.role != UserRole.superadmin) continue;
          final existing = store.notifications[a.username];
          if (existing != null &&
              existing.any((n) => n.id == 'WRN-EXP-${l.id}')) {
            continue;
          }
          store.notify(
            a.username,
            id: 'WRN-EXP-${l.id}',
            kind: NotificationKind.warningExpiring,
            title: '${l.levelLabel} segera kedaluwarsa',
            body:
                '${l.levelLabel} ${account.fullName} (${l.violationName}) '
                'kedaluwarsa ${DateFormatId.shortDate(l.expiresAt)} '
                '($days hari lagi).',
          );
        }
      }
    }
  }

  WarningLetter _owned(AuthUser user, String id) {
    final list = store.warningLetters[user.username] ?? const [];
    final index = list.indexWhere((l) => l.id == id);
    if (index < 0) {
      throw const AppException('Surat peringatan tidak ditemukan.');
    }
    return list[index];
  }

  void _replace(WarningLetter updated) {
    final list = store.warningLetters[updated.employeeUsername]!;
    final index = list.indexWhere((l) => l.id == updated.id);
    list[index] = updated;
    store.warningChanges.ping();
  }

  void _notifyIssuers(WarningLetter letter, {required String title, required String body}) {
    for (final a in store.accounts.values) {
      if (!a.active || a.role != UserRole.superadmin) continue;
      store.notify(
        a.username,
        kind: NotificationKind.warningIssued,
        title: title,
        body: body,
      );
    }
  }

  @override
  Future<WarningLetterDetail> acknowledge(
    AuthUser user, {
    required String id,
    required bool refused,
    String? witness1,
    String? witness2,
  }) async {
    await Future<void>.delayed(latency);
    final current = _owned(user, id);
    if (current.signed) {
      throw const AppException('Surat ini sudah ditandatangani.');
    }
    final w1 = witness1?.trim() ?? '';
    final w2 = witness2?.trim() ?? '';
    if (refused) {
      if (w1.length < WarningRules.minName ||
          w2.length < WarningRules.minName) {
        throw const AppException(
          'Penolakan wajib disertai berita acara dengan 2 nama saksi.',
        );
      }
      if (w1.toLowerCase() == w2.toLowerCase()) {
        throw const AppException('Kedua saksi harus orang yang berbeda.');
      }
    }
    final account = store.account(user.username)!;
    final updated = current.copyWith(
      acknowledgedAt: _now,
      acknowledgedBy: user.fullName,
      refused: refused,
      witness1: refused ? w1 : null,
      witness2: refused ? w2 : null,
    );
    _replace(updated);
    _notifyIssuers(
      updated,
      title: refused
          ? '${current.levelLabel} ditolak ditandatangani'
          : '${current.levelLabel} ditandatangani',
      body: refused
          ? '${account.fullName} menolak menandatangani '
              '${current.levelLabel}. Saksi: $w1, $w2.'
          : '${account.fullName} telah menandatangani ${current.levelLabel}.',
    );
    return _detail(account, updated);
  }

  @override
  Future<WarningLetterDetail> appeal(
    AuthUser user, {
    required String id,
    required String text,
  }) async {
    await Future<void>.delayed(latency);
    final current = _owned(user, id);
    if (current.appeal != null) {
      throw const AppException('Sanggahan sudah diajukan untuk surat ini.');
    }
    final appealError = WarningRules.validateAppeal(text);
    if (appealError != null) throw AppException(appealError);
    final account = store.account(user.username)!;
    final updated = current.copyWith(appeal: text.trim(), appealAt: _now);
    _replace(updated);
    _notifyIssuers(
      updated,
      title: 'Sanggahan atas ${current.levelLabel}',
      body: '${account.fullName} mengajukan sanggahan: “${text.trim()}”',
    );
    return _detail(account, updated);
  }

  WarningLetter _byId(String id) {
    for (final entry in store.warningLetters.entries) {
      final index = entry.value.indexWhere((l) => l.id == id);
      if (index >= 0) return entry.value[index];
    }
    throw const AppException('Surat peringatan tidak ditemukan.');
  }

  @override
  Future<WarningLetterDetail> respondAppeal(
    AuthUser actor, {
    required String id,
    required bool accept,
    required String note,
  }) async {
    await Future<void>.delayed(latency);
    _requireSuperAdmin(actor);
    final current = _byId(id);
    if (current.appeal == null) {
      throw const AppException('Belum ada sanggahan untuk surat ini.');
    }
    if (current.appealAccepted != null) {
      throw const AppException('Sanggahan ini sudah direspons.');
    }
    final trimmed = note.trim();
    if (trimmed.length < WarningRules.minResponseNote) {
      throw const AppException(
        'Tulis catatan respons minimal '
        '${WarningRules.minResponseNote} karakter.',
      );
    }
    final account = store.account(current.employeeUsername)!;
    final updated = current.copyWith(
      appealAccepted: accept,
      appealResponseNote: trimmed,
      appealRespondedAt: _now,
    );
    _replace(updated);
    store.notify(
      account.username,
      kind: NotificationKind.warningIssued,
      title: accept
          ? 'Sanggahan diterima, ${current.levelLabel} dicabut'
          : 'Sanggahan ditolak, ${current.levelLabel} tetap berlaku',
      body: '${actor.fullName}: “$trimmed”',
    );
    return _detail(account, updated);
  }
}
