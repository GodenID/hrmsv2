import 'package:flutter/foundation.dart';

import '../core/utils/currency_format.dart';
import 'auth_repository.dart';

/// Kontrak event.
///
/// - Semua role: melihat event & mendaftarkan diri sebagai crew.
/// - Manager & Super Admin: membuat, mengubah & menghapus event; mengelola
///   daftar kategori event; mengatur ambang nilai PO (kecil/sedang/besar).
/// - Nilai PO terlihat semua role (keputusan produk).
/// - Server mengingatkan crew pada hari-H event berlangsung.
///
/// Implementasi WAJIB menegakkan aturan ini di server.
abstract class EventRepository {
  Listenable get changes;

  Future<EventThresholds> fetchThresholds();

  Future<EventThresholds> updateThresholds(
    AuthUser actor,
    EventThresholds thresholds,
  );

  /// Semua kategori event (untuk formulir). Semua role boleh melihat.
  Future<List<EventCategory>> fetchCategories(AuthUser viewer);

  /// Tambah ([id] null) / ubah nama kategori — Manager & Super Admin.
  /// Nama wajib unik (abaikan kapitalisasi).
  Future<EventCategory> saveCategory(
    AuthUser actor, {
    String? id,
    required String name,
  });

  /// Hapus kategori — Manager & Super Admin. Ditolak bila kategori masih
  /// dipakai event (pesan menyebut jumlahnya); minimal satu kategori
  /// tersisa.
  Future<void> deleteCategory(AuthUser actor, {required String id});

  /// Semua event, terdekat lebih dulu (urut tanggal mulai).
  Future<List<EventItem>> fetchEvents(AuthUser viewer);

  Future<EventItem> fetchEvent(AuthUser viewer, {required String id});

  /// Tanggal selesai ≥ tanggal mulai (event 1 hari: isi sama dengan mulai).
  Future<EventItem> createEvent(
    AuthUser actor, {
    required String name,
    required String company,
    required String categoryId,
    required DateTime startDate,
    required DateTime endDate,
    required String location,
    required int poValue,
  });

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
  });

  /// Menghapus event (mis. batal diadakan). Seluruh tim event menerima
  /// notifikasi pembatalan.
  Future<void> deleteEvent(AuthUser actor, {required String id});

  /// Mendaftarkan / mengubah bagian pengguna sendiri di event.
  /// Satu orang satu bagian per event.
  Future<EventItem> joinEvent(
    AuthUser user, {
    required String id,
    required CrewRole role,
    required String note,
  });

  Future<EventItem> leaveEvent(AuthUser user, {required String id});
}

/// Bagian di dalam tim event (urutan sesuai permintaan bisnis).
enum CrewRole {
  crew('Crew', 'mis. Crew panggung, crew logistik'),
  pic('PIC', 'mis. PIC Venue, PIC Talent, PIC Konsumsi'),
  pm('PM', 'mis. Project manager utama'),
  sla('SLA', 'Tambahkan keterangan bila perlu'),
  slb('SLB', 'Tambahkan keterangan bila perlu'),
  slc('SLC', 'Tambahkan keterangan bila perlu'),
  design('Design', 'mis. Desain panggung, materi publikasi');

  const CrewRole(this.label, this.noteHint);

  final String label;
  final String noteHint;

  /// PIC wajib menjelaskan PIC bagian apa.
  bool get requiresNote => this == CrewRole.pic;
}

enum EventSize {
  small('Kecil'),
  medium('Sedang'),
  large('Besar'),
  overLimit('Melebihi batas');

  const EventSize(this.label);

  final String label;
}

/// Ambang nilai PO dari Manager / Super Admin. Setiap angka adalah nilai
/// PO MAKSIMAL untuk kategorinya.
class EventThresholds {
  const EventThresholds({
    required this.smallMax,
    required this.mediumMax,
    required this.largeMax,
  });

  final int smallMax;
  final int mediumMax;
  final int largeMax;

  EventSize classify(int poValue) {
    if (poValue <= smallMax) return EventSize.small;
    if (poValue <= mediumMax) return EventSize.medium;
    if (poValue <= largeMax) return EventSize.large;
    return EventSize.overLimit;
  }

  /// Penjelasan rentang, mis. "Rp50.000.001 – Rp200.000.000".
  String rangeLabel(EventSize size) => switch (size) {
    EventSize.small => 's.d. ${Rupiah.format(smallMax)}',
    EventSize.medium =>
      '${Rupiah.format(smallMax + 1)} – ${Rupiah.format(mediumMax)}',
    EventSize.large =>
      '${Rupiah.format(mediumMax + 1)} – ${Rupiah.format(largeMax)}',
    EventSize.overLimit => 'di atas ${Rupiah.format(largeMax)}',
  };

  /// Pesan galat bila tidak valid, null bila valid.
  String? validate() {
    if (smallMax <= 0 || mediumMax <= 0 || largeMax <= 0) {
      return 'Semua batas harus lebih dari Rp 0.';
    }
    if (smallMax >= mediumMax) {
      return 'Batas event sedang harus lebih besar dari batas event kecil.';
    }
    if (mediumMax >= largeMax) {
      return 'Batas event besar harus lebih besar dari batas event sedang.';
    }
    return null;
  }
}

class CrewMember {
  const CrewMember({
    required this.username,
    required this.fullName,
    required this.role,
    required this.note,
    required this.joinedAt,
  });

  final String username;
  final String fullName;
  final CrewRole role;
  final String note;
  final DateTime joinedAt;
}

/// Kategori event (Employee Gathering, Family Gathering, dsb.) yang
/// dikelola Manager & Super Admin.
class EventCategory {
  const EventCategory({required this.id, required this.name});

  final String id;
  final String name;
}

class EventItem {
  const EventItem({
    required this.id,
    required this.name,
    required this.company,
    required this.category,
    required this.startDate,
    required this.endDate,
    required this.location,
    required this.size,
    required this.createdBy,
    required this.crew,
    this.poValue,
  });

  final String id;
  final String name;

  /// Perusahaan penyelenggara / klien event.
  final String company;

  final EventCategory category;

  /// Tanggal mulai. Event 1 hari: [endDate] sama dengan ini.
  final DateTime startDate;
  final DateTime endDate;
  final String location;

  /// null bila peminta tidak berhak melihat nilai PO.
  final int? poValue;

  /// Dihitung server dari nilai PO & ambang saat ini.
  final EventSize size;
  final String createdBy;

  /// Diurutkan per bagian lalu nama.
  final List<CrewMember> crew;

  bool get isMultiDay =>
      startDate.year != endDate.year ||
      startDate.month != endDate.month ||
      startDate.day != endDate.day;

  CrewMember? memberFor(String username) {
    for (final m in crew) {
      if (m.username == username) return m;
    }
    return null;
  }
}
