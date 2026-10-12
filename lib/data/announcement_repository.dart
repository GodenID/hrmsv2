import 'auth_repository.dart';
import 'employee.dart';

export 'employee.dart';

/// Kontrak pengumuman.
///
/// - Semua role dapat membaca. Membuka detail ([open]) mencatat bahwa
///   karyawan tersebut sudah melihat pengumuman.
/// - Laporan siapa yang sudah/belum melihat: semua role.
/// - Tambah/ubah/hapus: hanya Super Admin.
///
/// Implementasi WAJIB menolak aksi dari role yang tidak berhak
/// (di backend nyata: dicek di server, bukan hanya disembunyikan di UI).
abstract class AnnouncementRepository {
  /// Daftar untuk dashboard, terbaru lebih dulu, beserta status
  /// "sudah dilihat" milik [viewer].
  Future<List<AnnouncementFeedItem>> fetchFeed(AuthUser viewer);

  /// Membuka pengumuman: mencatat [viewer] sebagai sudah melihat
  /// (hanya sekali, waktu pertama dipertahankan), lalu mengembalikan isinya.
  Future<Announcement> open({required AuthUser viewer, required String id});

  /// Siapa saja yang sudah & belum melihat. Semua role.
  Future<AnnouncementReadReport> fetchReadReport({
    required AuthUser actor,
    required String id,
  });

  Future<Announcement> create({
    required AuthUser actor,
    required AnnouncementDraft draft,
  });

  Future<Announcement> update({
    required AuthUser actor,
    required String id,
    required AnnouncementDraft draft,
  });

  Future<void> delete({required AuthUser actor, required String id});
}

/// Isi formulir tambah / ubah pengumuman.
class AnnouncementDraft {
  const AnnouncementDraft({
    required this.title,
    required this.body,
    this.publishAt,
    this.expiresAt,
    this.pinned = false,
    this.targetDivisions = const [],
    this.attachments = const [],
  });

  final String title;
  final String body;

  /// Kapan mulai terlihat. null = segera.
  final DateTime? publishAt;

  /// Kapan hilang dari feed. null = selamanya.
  final DateTime? expiresAt;

  /// Disematkan di paling atas feed.
  final bool pinned;

  /// Divisi sasaran. Kosong = semua karyawan.
  final List<Division> targetDivisions;

  final List<AnnouncementAttachment> attachments;
}

/// Lampiran pengumuman (hanya metadata; unduhan mengikuti API file).
class AnnouncementAttachment {
  const AnnouncementAttachment({required this.name, required this.sizeBytes, this.key});

  final String name;
  final int sizeBytes;

  /// Key objek di S3 (mode API). null = hanya metadata (mode mock).
  final String? key;

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).ceil()} KB';
  }
}

/// Aturan pengumuman (dipakai formulir & mock server).
abstract final class AnnouncementRules {
  static const int maxAttachments = 3;
  static const int maxBytes = 5 * 1024 * 1024;
  static const List<String> allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

  /// Pesan galat jadwal, null bila valid.
  static String? validateSchedule(DateTime? publishAt, DateTime? expiresAt) {
    if (publishAt != null &&
        expiresAt != null &&
        !expiresAt.isAfter(publishAt)) {
      return 'Tanggal kedaluwarsa harus setelah tanggal terbit.';
    }
    return null;
  }

  static String? validateAttachment(String name, int sizeBytes) {
    final ext = name.split('.').last.toLowerCase();
    if (!allowedExtensions.contains(ext)) {
      return 'Format file harus PDF, JPG, atau PNG.';
    }
    if (sizeBytes > maxBytes) {
      return 'Ukuran file maksimal 5 MB.';
    }
    return null;
  }
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.authorName,
    required this.publishedAt,
    this.updatedAt,
    this.expiresAt,
    this.pinned = false,
    this.targetDivisions = const [],
    this.attachments = const [],
  });

  final String id;
  final String title;
  final String body;
  final String authorName;

  /// Kapan mulai terlihat (dibuat segera = waktu pembuatan).
  final DateTime publishedAt;
  final DateTime? updatedAt;

  /// Kapan hilang dari feed. null = selamanya.
  final DateTime? expiresAt;

  /// Disematkan di paling atas feed.
  final bool pinned;

  /// Divisi sasaran. Kosong = semua karyawan.
  final List<Division> targetDivisions;

  final List<AnnouncementAttachment> attachments;

  Announcement copyWith({
    String? title,
    String? body,
    DateTime? updatedAt,
    DateTime? publishedAt,
    DateTime? Function()? expiresAt,
    bool? pinned,
    List<Division>? targetDivisions,
    List<AnnouncementAttachment>? attachments,
  }) {
    return Announcement(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      authorName: authorName,
      publishedAt: publishedAt ?? this.publishedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      expiresAt: expiresAt != null ? expiresAt() : this.expiresAt,
      pinned: pinned ?? this.pinned,
      targetDivisions: targetDivisions ?? this.targetDivisions,
      attachments: attachments ?? this.attachments,
    );
  }
}

/// Satu kartu di dashboard.
class AnnouncementFeedItem {
  const AnnouncementFeedItem({
    required this.announcement,
    required this.viewedByMe,
    required this.viewCount,
  });

  final Announcement announcement;
  final bool viewedByMe;
  final int viewCount;
}

class AnnouncementViewer {
  const AnnouncementViewer({required this.employee, required this.viewedAt});

  final EmployeeRef employee;
  final DateTime viewedAt;
}

class AnnouncementReadReport {
  const AnnouncementReadReport({required this.viewed, required this.notViewed});

  /// Terbaru lebih dulu.
  final List<AnnouncementViewer> viewed;

  /// Urut nama.
  final List<EmployeeRef> notViewed;

  int get total => viewed.length + notViewed.length;
}
