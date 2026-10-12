import '../announcement_repository.dart';
import '../auth_repository.dart';
import '../notification_repository.dart';
import 'mock_store.dart';

/// Pengumuman palsu di memori, dipakai bersama semua akun selama aplikasi
/// berjalan — perubahan oleh Super Admin dan catatan "sudah melihat"
/// langsung terlihat oleh akun lain setelah login ulang.
class MockAnnouncementRepository implements AnnouncementRepository {
  MockAnnouncementRepository(
    this.store, {
    this.latency = const Duration(milliseconds: 600),
  });

  final MockStore store;
  final Duration latency;

  List<EmployeeRef> get employees => store.directory;
  int _nextId = 4;

  final List<Announcement> _items = [
    Announcement(
      id: '3',
      title: 'Pemeliharaan sistem Prasasti Connect',
      body:
          'Prasasti Connect tidak dapat diakses pada Sabtu, 10 Oktober 2026 '
          'pukul 22.00–24.00 WIB karena pemeliharaan rutin.\n\n'
          'Pastikan Anda sudah clock out sebelum jadwal tersebut. Absensi yang '
          'belum ditutup akan ditutup otomatis oleh sistem pukul 21.55 WIB dan '
          'dapat dikoreksi melalui Tim HR pada hari kerja berikutnya.',
      authorName: 'Andi Pratama',
      publishedAt: DateTime(2026, 10, 6, 16, 30),
      pinned: true,
    ),
    Announcement(
      id: '2',
      title: 'Pelengkapan data BPJS Ketenagakerjaan',
      body:
          'Karyawan yang belum melengkapi data BPJS Ketenagakerjaan diminta '
          'menyerahkan salinan KTP dan Kartu Keluarga ke Tim HR paling lambat '
          '15 Oktober 2026.\n\n'
          'Dokumen dapat diserahkan langsung di lantai 3 atau dikirim melalui '
          'email HR dalam format PDF.',
      authorName: 'Andi Pratama',
      publishedAt: DateTime(2026, 10, 5, 9, 15),
    ),
    Announcement(
      id: '1',
      title: 'Jam masuk fleksibel mulai 1 Oktober',
      body:
          'Mulai 1 Oktober 2026, jam masuk kantor dapat dimulai antara pukul '
          '07.30–09.00 WIB dengan total jam kerja 8 jam per hari, tidak '
          'termasuk istirahat.\n\n'
          'Durasi kerja dihitung dari clock in hingga clock out di Prasasti '
          'Connect.',
      authorName: 'Andi Pratama',
      publishedAt: DateTime(2026, 9, 28, 10, 0),
    ),
  ];

  /// id pengumuman -> (username -> waktu pertama melihat)
  final Map<String, Map<String, DateTime>> _views = {
    '3': {
      'andi.pratama': DateTime(2026, 10, 6, 16, 31),
      'dewi.lestari': DateTime(2026, 10, 6, 17, 4),
      'rizky.ramadhan': DateTime(2026, 10, 7, 8, 12),
    },
    '2': {
      'andi.pratama': DateTime(2026, 10, 5, 9, 16),
      'siti.rahma': DateTime(2026, 10, 5, 9, 40),
      'dewi.lestari': DateTime(2026, 10, 5, 10, 2),
      'agus.setiawan': DateTime(2026, 10, 5, 13, 25),
      'fajar.nugroho': DateTime(2026, 10, 6, 8, 3),
    },
    '1': {
      'andi.pratama': DateTime(2026, 9, 28, 10, 1),
      'siti.rahma': DateTime(2026, 9, 28, 10, 20),
      'dewi.lestari': DateTime(2026, 9, 28, 11, 5),
      'rizky.ramadhan': DateTime(2026, 9, 28, 13, 47),
      'agus.setiawan': DateTime(2026, 9, 29, 8, 2),
      'fajar.nugroho': DateTime(2026, 9, 29, 8, 30),
    },
  };

  void _requireSuperadmin(AuthUser actor) {
    if (!actor.role.canManageAnnouncements) {
      throw const PermissionDeniedException(
        'Hanya Super Admin yang dapat mengelola pengumuman.',
      );
    }
  }

  int _indexOf(String id) {
    final index = _items.indexWhere((a) => a.id == id);
    if (index < 0) {
      throw const AppException(
        'Pengumuman tidak ditemukan. Mungkin sudah dihapus.',
      );
    }
    return index;
  }

  EmployeeRef _employee(String username) {
    for (final e in employees) {
      if (e.username == username) return e;
    }
    return EmployeeRef(username: username, fullName: username);
  }

  /// Terlihat oleh [username] pada [now]: sudah terbit, belum kedaluwarsa,
  /// dan divisinya termasuk sasaran (atau untuk semua).
  bool _visibleTo(Announcement a, String username, DateTime now) {
    if (a.publishedAt.isAfter(now)) return false;
    if (a.expiresAt != null && !now.isBefore(a.expiresAt!)) return false;
    if (a.targetDivisions.isEmpty) return true;
    final division = store.account(username)?.division;
    return division != null && a.targetDivisions.contains(division);
  }

  @override
  Future<List<AnnouncementFeedItem>> fetchFeed(AuthUser viewer) async {
    await Future<void>.delayed(latency);
    final now = store.now();
    final visible = [
      for (final a in _items)
        if (_visibleTo(a, viewer.username, now)) a,
    ];
    // Disematkan dulu, lalu terbaru.
    visible.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.publishedAt.compareTo(a.publishedAt);
    });
    return List.unmodifiable([
      for (final a in visible)
        AnnouncementFeedItem(
          announcement: a,
          viewedByMe: _views[a.id]?.containsKey(viewer.username) ?? false,
          viewCount: _views[a.id]?.length ?? 0,
        ),
    ]);
  }

  @override
  Future<Announcement> open({
    required AuthUser viewer,
    required String id,
  }) async {
    await Future<void>.delayed(latency);
    final announcement = _items[_indexOf(id)];
    final now = store.now();
    _views.putIfAbsent(id, () => {}).putIfAbsent(viewer.username, () => now);
    return announcement;
  }

  @override
  Future<AnnouncementReadReport> fetchReadReport({
    required AuthUser actor,
    required String id,
  }) async {
    await Future<void>.delayed(latency);
    if (!actor.role.canViewAnnouncementReaders) {
      throw const PermissionDeniedException(
        'Anda tidak berhak melihat daftar pembaca.',
      );
    }
    _indexOf(id);
    final views = _views[id] ?? const {};
    final viewed = [
      for (final entry in views.entries)
        AnnouncementViewer(
          employee: _employee(entry.key),
          viewedAt: entry.value,
        ),
    ]..sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    final notViewed = [
      for (final e in employees)
        if (!views.containsKey(e.username)) e,
    ]..sort((a, b) => a.fullName.compareTo(b.fullName));
    return AnnouncementReadReport(viewed: viewed, notViewed: notViewed);
  }

  void _validateDraft(AnnouncementDraft draft) {
    if (draft.title.trim().length < 5) {
      throw const AppException('Judul minimal 5 karakter.');
    }
    if (draft.body.trim().length < 10) {
      throw const AppException('Isi pengumuman minimal 10 karakter.');
    }
    final scheduleError = AnnouncementRules.validateSchedule(
      draft.publishAt,
      draft.expiresAt,
    );
    if (scheduleError != null) throw AppException(scheduleError);
    if (draft.attachments.length > AnnouncementRules.maxAttachments) {
      throw const AppException('Maksimal 3 lampiran.');
    }
    for (final a in draft.attachments) {
      final error = AnnouncementRules.validateAttachment(a.name, a.sizeBytes);
      if (error != null) throw AppException(error);
    }
  }

  @override
  Future<Announcement> create({
    required AuthUser actor,
    required AnnouncementDraft draft,
  }) async {
    await Future<void>.delayed(latency);
    _requireSuperadmin(actor);
    _validateDraft(draft);
    final now = store.now();
    final item = Announcement(
      id: '${_nextId++}',
      title: draft.title.trim(),
      body: draft.body.trim(),
      authorName: actor.fullName,
      publishedAt: draft.publishAt ?? now,
      expiresAt: draft.expiresAt,
      pinned: draft.pinned,
      targetDivisions: List.unmodifiable(draft.targetDivisions),
      attachments: List.unmodifiable(draft.attachments),
    );
    _items.add(item);
    // Penulis otomatis dianggap sudah melihat.
    _views[item.id] = {actor.username: now};
    // Diberitahu sekarang hanya yang langsung terlihat dan tersasar;
    // yang terjadwal akan didorong server sungguhan saat waktunya tiba.
    for (final e in employees) {
      if (e.username == actor.username) continue;
      if (!_visibleTo(item, e.username, now)) continue;
      store.notify(
        e.username,
        kind: NotificationKind.announcement,
        title: 'Pengumuman baru',
        body: item.title,
        at: now,
      );
    }
    return item;
  }

  @override
  Future<Announcement> update({
    required AuthUser actor,
    required String id,
    required AnnouncementDraft draft,
  }) async {
    await Future<void>.delayed(latency);
    _requireSuperadmin(actor);
    _validateDraft(draft);
    final index = _indexOf(id);
    final updated = _items[index].copyWith(
      title: draft.title.trim(),
      body: draft.body.trim(),
      updatedAt: store.now(),
      publishedAt: draft.publishAt ?? _items[index].publishedAt,
      expiresAt: () => draft.expiresAt,
      pinned: draft.pinned,
      targetDivisions: List.unmodifiable(draft.targetDivisions),
      attachments: List.unmodifiable(draft.attachments),
    );
    _items[index] = updated;
    return updated;
  }

  @override
  Future<void> delete({required AuthUser actor, required String id}) async {
    await Future<void>.delayed(latency);
    _requireSuperadmin(actor);
    _items.removeAt(_indexOf(id));
    _views.remove(id);
  }
}
