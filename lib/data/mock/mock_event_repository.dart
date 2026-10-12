import 'package:flutter/foundation.dart';

import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../auth_repository.dart';
import '../event_repository.dart';
import '../notification_repository.dart';
import 'mock_store.dart';

/// Event palsu di memori. Aturan hak akses di sini meniru yang WAJIB
/// ditegakkan server.
class MockEventRepository implements EventRepository {
  MockEventRepository(
    this.store, {
    this.latency = const Duration(milliseconds: 500),
  }) {
    _seed();
  }

  final MockStore store;
  final Duration latency;
  final ChangeSignal _changes = ChangeSignal();

  EventThresholds _thresholds = EventThresholds.defaults;
  final List<_EventRecord> _events = [];
  final List<EventCategory> _categories = [];

  @override
  Listenable get changes => _changes;

  // ---------------------------------------------------------------------------
  // Ambang & kategori
  // ---------------------------------------------------------------------------

  @override
  Future<EventThresholds> fetchThresholds() async {
    await Future<void>.delayed(latency);
    return _thresholds;
  }

  @override
  Future<EventThresholds> updateThresholds(
    AuthUser actor,
    EventThresholds thresholds,
  ) async {
    await Future<void>.delayed(latency);
    if (!actor.role.canManageEventThresholds) {
      throw const PermissionDeniedException(
        'Hanya Manager dan Super Admin yang dapat mengatur ambang event.',
      );
    }
    final error = thresholds.validate();
    if (error != null) throw AppException(error);
    _thresholds = thresholds;
    _changes.ping();
    return _thresholds;
  }

  @override
  Future<List<EventCategory>> fetchCategories(AuthUser viewer) async {
    await Future<void>.delayed(latency);
    return List.unmodifiable(_categories);
  }

  @override
  Future<EventCategory> saveCategory(
    AuthUser actor, {
    String? id,
    required String name,
  }) async {
    await Future<void>.delayed(latency);
    _requireEventManager(actor);
    final clean = name.trim();
    if (clean.length < 3) {
      throw const AppException('Nama kategori minimal 3 karakter.');
    }
    if (clean.length > 40) {
      throw const AppException('Nama kategori maksimal 40 karakter.');
    }
    for (final c in _categories) {
      if (c.id != id && c.name.toLowerCase() == clean.toLowerCase()) {
        throw AppException('Kategori "$clean" sudah ada.');
      }
    }
    if (id == null) {
      final created = EventCategory(id: store.nextId('EC'), name: clean);
      _categories.add(created);
      _changes.ping();
      return created;
    }
    final index = _categories.indexWhere((c) => c.id == id);
    if (index < 0) throw const AppException('Kategori tidak ditemukan.');
    final updated = EventCategory(id: id, name: clean);
    _categories[index] = updated;
    _changes.ping();
    return updated;
  }

  @override
  Future<void> deleteCategory(AuthUser actor, {required String id}) async {
    await Future<void>.delayed(latency);
    _requireEventManager(actor);
    if (_categories.length <= 1) {
      throw const AppException('Minimal satu kategori event tersisa.');
    }
    final index = _categories.indexWhere((c) => c.id == id);
    if (index < 0) throw const AppException('Kategori tidak ditemukan.');
    final used = _events.where((e) => e.categoryId == id).length;
    if (used > 0) {
      throw AppException(
        'Kategori dipakai $used event. Pindahkan eventnya dulu sebelum '
        'menghapus.',
      );
    }
    _categories.removeAt(index);
    _changes.ping();
  }

  // ---------------------------------------------------------------------------
  // Event
  // ---------------------------------------------------------------------------

  EventItem _toItem(_EventRecord r, AuthUser viewer) {
    final crew = [...r.crew]
      ..sort((a, b) {
        final byRole = a.role.index.compareTo(b.role.index);
        return byRole != 0 ? byRole : a.fullName.compareTo(b.fullName);
      });
    return EventItem(
      id: r.id,
      name: r.name,
      company: r.company,
      category: _categories.firstWhere(
        (c) => c.id == r.categoryId,
        // Tak terjangkau (hapus kategori yang dipakai ditolak), pengaman
        // agar aplikasi tidak crash bila data tidak konsisten.
        orElse: () => _categories.first,
      ),
      startDate: r.startDate,
      endDate: r.endDate,
      location: r.location,
      // Nilai PO terbuka untuk semua role (keputusan produk).
      poValue: r.poValue,
      size: _thresholds.classify(r.poValue),
      createdBy: r.createdBy,
      crew: List.unmodifiable(crew),
    );
  }

  /// Mengingatkan crew pada hari-H event berlangsung. Id stabil per event +
  /// tanggal hari ini sehingga tiap hari event multi-hari mengingatkan
  /// sekali, tanpa duplikat.
  void _ensureTodayReminders(AuthUser viewer, List<_EventRecord> records) {
    final today = WorkCalendar.dateOnly(store.now());
    for (final r in records) {
      final start = WorkCalendar.dateOnly(r.startDate);
      final end = WorkCalendar.dateOnly(r.endDate);
      if (today.isBefore(start) || today.isAfter(end)) continue;
      CrewMember? member;
      for (final m in r.crew) {
        if (m.username == viewer.username) member = m;
      }
      if (member == null) continue;
      final id =
          'EVD-${r.id}-${today.year}'
          '${today.month.toString().padLeft(2, '0')}'
          '${today.day.toString().padLeft(2, '0')}';
      final existing = store.notifications[viewer.username];
      if (existing != null && existing.any((n) => n.id == id)) continue;
      store.notify(
        viewer.username,
        kind: NotificationKind.eventToday,
        title: 'Hari ini: ${r.name}',
        body:
            '${r.company} di ${r.location}. Anda bertugas sebagai '
            '${member.role.label}. Sampai jumpa di venue!',
        id: id,
      );
    }
  }

  _EventRecord _find(String id) {
    for (final e in _events) {
      if (e.id == id) return e;
    }
    throw const AppException('Event tidak ditemukan. Mungkin sudah dihapus.');
  }

  void _requireEventManager(AuthUser actor) {
    if (!actor.role.canManageEvents) {
      throw const PermissionDeniedException(
        'Hanya Manager dan Super Admin yang dapat membuat atau mengubah event.',
      );
    }
  }

  void _validate({
    required String name,
    required String company,
    required String categoryId,
    required DateTime start,
    required DateTime end,
    required String location,
    required int poValue,
  }) {
    if (name.trim().length < 3) {
      throw const AppException('Nama event minimal 3 karakter.');
    }
    if (company.trim().length < 3) {
      throw const AppException('Nama perusahaan minimal 3 karakter.');
    }
    if (!_categories.any((c) => c.id == categoryId)) {
      throw const AppException('Kategori event tidak dikenal.');
    }
    if (end.isBefore(start)) {
      throw const AppException(
        'Tanggal selesai tidak boleh sebelum tanggal mulai.',
      );
    }
    if (location.trim().length < 3) {
      throw const AppException('Lokasi acara minimal 3 karakter.');
    }
    if (poValue <= 0) {
      throw const AppException('Nilai PO harus lebih dari Rp 0.');
    }
  }

  @override
  Future<List<EventItem>> fetchEvents(AuthUser viewer) async {
    await Future<void>.delayed(latency);
    _ensureTodayReminders(viewer, _events);
    final sorted = [..._events]
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    return List.unmodifiable([for (final e in sorted) _toItem(e, viewer)]);
  }

  @override
  Future<EventItem> fetchEvent(AuthUser viewer, {required String id}) async {
    await Future<void>.delayed(latency);
    final record = _find(id);
    _ensureTodayReminders(viewer, [record]);
    return _toItem(record, viewer);
  }

  @override
  Future<EventItem> createEvent(
    AuthUser actor, {
    required String name,
    required String company,
    required String categoryId,
    required DateTime startDate,
    required DateTime endDate,
    required String location,
    required int poValue,
  }) async {
    await Future<void>.delayed(latency);
    _requireEventManager(actor);
    final start = WorkCalendar.dateOnly(startDate);
    final end = WorkCalendar.dateOnly(endDate);
    _validate(
      name: name,
      company: company,
      categoryId: categoryId,
      start: start,
      end: end,
      location: location,
      poValue: poValue,
    );
    final record = _EventRecord(
      id: store.nextId('EV'),
      name: name.trim(),
      company: company.trim(),
      categoryId: categoryId,
      startDate: start,
      endDate: end,
      location: location.trim(),
      poValue: poValue,
      createdBy: actor.fullName,
    );
    _events.add(record);
    _changes.ping();
    return _toItem(record, actor);
  }

  @override
  Future<EventItem> updateEvent(
    AuthUser actor, {
    required String id,
    required String name,
    required String company,
    required String categoryId,
    required DateTime startDate,
    required DateTime endDate,
    required String location,
    required int poValue,
  }) async {
    await Future<void>.delayed(latency);
    _requireEventManager(actor);
    final start = WorkCalendar.dateOnly(startDate);
    final end = WorkCalendar.dateOnly(endDate);
    _validate(
      name: name,
      company: company,
      categoryId: categoryId,
      start: start,
      end: end,
      location: location,
      poValue: poValue,
    );
    final r = _find(id)
      ..name = name.trim()
      ..company = company.trim()
      ..categoryId = categoryId
      ..startDate = start
      ..endDate = end
      ..location = location.trim()
      ..poValue = poValue;
    _changes.ping();
    return _toItem(r, actor);
  }

  @override
  Future<void> deleteEvent(AuthUser actor, {required String id}) async {
    await Future<void>.delayed(latency);
    if (!actor.role.canManageEvents) {
      throw const PermissionDeniedException(
        'Hanya Manager dan Super Admin yang dapat menghapus event.',
      );
    }
    final r = _find(id);
    _events.remove(r);
    _changes.ping();
    for (final m in r.crew) {
      if (m.username == actor.username) continue;
      store.notify(
        m.username,
        kind: NotificationKind.eventCancelled,
        title: 'Event dibatalkan',
        body:
            '${r.name} (${DateFormatId.dateRange(r.startDate, r.endDate)}) '
            'dibatalkan oleh ${actor.fullName}. Anda tidak lagi terdaftar '
            'sebagai ${m.role.label}.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Crew
  // ---------------------------------------------------------------------------

  @override
  Future<EventItem> joinEvent(
    AuthUser user, {
    required String id,
    required CrewRole role,
    required String note,
  }) async {
    await Future<void>.delayed(latency);
    final r = _find(id);
    // Event yang sudah selesai tetap bisa didaftari (susulan pencatatan
    // crew) — tidak diblokir.
    final trimmed = note.trim();
    if (role.requiresNote && trimmed.isEmpty) {
      throw const AppException(
        'Keterangan wajib untuk PIC, mis. PIC Venue atau PIC Talent.',
      );
    }
    if (trimmed.length > 80) {
      throw const AppException('Keterangan maksimal 80 karakter.');
    }
    final existing = r.crew.indexWhere((m) => m.username == user.username);
    // Nama selalu dari akun yang login, bukan dari input pengguna.
    final member = CrewMember(
      username: user.username,
      fullName: user.fullName,
      role: role,
      note: trimmed,
      joinedAt: existing >= 0 ? r.crew[existing].joinedAt : store.now(),
    );
    if (existing >= 0) {
      r.crew[existing] = member;
    } else {
      r.crew.add(member);
    }
    _changes.ping();
    return _toItem(r, user);
  }

  @override
  Future<EventItem> leaveEvent(AuthUser user, {required String id}) async {
    await Future<void>.delayed(latency);
    final r = _find(id);
    r.crew.removeWhere((m) => m.username == user.username);
    _changes.ping();
    return _toItem(r, user);
  }

  // ---------------------------------------------------------------------------
  // Data contoh
  // ---------------------------------------------------------------------------

  void _seed() {
    CrewMember m(String username, CrewRole role, String note) {
      final a = store.account(username)!;
      return CrewMember(
        username: a.username,
        fullName: a.fullName,
        role: role,
        note: note,
        joinedAt: DateTime(2026, 9, 1, 9),
      );
    }

    _categories.addAll(const [
      EventCategory(id: 'EC-1', name: 'Employee Gathering'),
      EventCategory(id: 'EC-2', name: 'Family Gathering'),
      EventCategory(id: 'EC-3', name: 'Product Launch'),
      EventCategory(id: 'EC-4', name: 'Pernikahan'),
      EventCategory(id: 'EC-5', name: 'Festival'),
      EventCategory(id: 'EC-6', name: 'Workshop'),
    ]);

    _events.addAll([
      _EventRecord(
        id: 'EV-1',
        name: 'Peluncuran Produk Aurora',
        company: 'PT Aurora Indonesia',
        categoryId: 'EC-3',
        startDate: DateTime(2026, 10, 15),
        endDate: DateTime(2026, 10, 16),
        location: 'Jakarta Convention Center, Hall A',
        poValue: 180000000,
        createdBy: 'Siti Rahma',
        crew: [
          m('agus.setiawan', CrewRole.pm, 'Project manager utama'),
          m('dewi.lestari', CrewRole.pic, 'PIC Vendor & keuangan'),
          m('rizky.ramadhan', CrewRole.sla, 'Area panggung utama'),
          m('maya.putri', CrewRole.design, 'Desain panggung & backdrop'),
          m('fajar.nugroho', CrewRole.crew, 'Crew logistik'),
        ],
      ),
      _EventRecord(
        id: 'EV-2',
        name: 'Gathering Tahunan Mitra',
        company: 'Prasasti Group',
        categoryId: 'EC-1',
        startDate: DateTime(2026, 10, 24),
        endDate: DateTime(2026, 10, 25),
        location: 'Bali Nusa Dua Convention Center',
        poValue: 850000000,
        createdBy: 'Siti Rahma',
        crew: [
          m('agus.setiawan', CrewRole.pm, ''),
          m('maya.putri', CrewRole.pic, 'PIC Talent'),
        ],
      ),
      _EventRecord(
        id: 'EV-3',
        name: 'Workshop Internal Q4',
        company: 'Prasasti Group',
        categoryId: 'EC-6',
        startDate: DateTime(2026, 10, 30),
        endDate: DateTime(2026, 10, 30),
        location: 'Kantor Pusat Prasasti, Ruang Serbaguna',
        poValue: 35000000,
        createdBy: 'Siti Rahma',
      ),
      _EventRecord(
        id: 'EV-4',
        name: 'Konser Amal Prasasti',
        company: 'Yayasan Amal Bangsa',
        categoryId: 'EC-5',
        startDate: DateTime(2026, 9, 20),
        endDate: DateTime(2026, 9, 20),
        location: 'Istora Senayan, Jakarta',
        poValue: 650000000,
        createdBy: 'Siti Rahma',
        crew: [
          m('agus.setiawan', CrewRole.pm, ''),
          m('dewi.lestari', CrewRole.pic, 'PIC Tiket & registrasi'),
          m('budi.santoso', CrewRole.crew, 'Crew panggung'),
          m('rizky.ramadhan', CrewRole.slb, 'Area tribun'),
          m('fajar.nugroho', CrewRole.crew, 'Crew logistik'),
        ],
      ),
      _EventRecord(
        id: 'EV-5',
        name: 'Pameran Otomotif Regional',
        company: 'PT Oto Maju',
        categoryId: 'EC-5',
        startDate: DateTime(2026, 9, 5),
        endDate: DateTime(2026, 9, 7),
        location: 'ICE BSD, Tangerang',
        poValue: 120000000,
        createdBy: 'Siti Rahma',
        crew: [m('maya.putri', CrewRole.design, 'Materi publikasi')],
      ),
    ]);
  }
}

class _EventRecord {
  _EventRecord({
    required this.id,
    required this.name,
    required this.company,
    required this.categoryId,
    required this.startDate,
    required this.endDate,
    required this.location,
    required this.poValue,
    required this.createdBy,
    List<CrewMember>? crew,
  }) : crew = crew ?? [];

  final String id;
  String name;
  String company;
  String categoryId;
  DateTime startDate;
  DateTime endDate;
  String location;
  int poValue;
  final String createdBy;
  final List<CrewMember> crew;
}
