import 'package:flutter/foundation.dart';

import 'auth_repository.dart';

/// Kontrak notifikasi di dalam aplikasi.
///
/// Notifikasi dibuat oleh server saat terjadi sesuatu yang menyangkut
/// pengguna (pengajuan disetujui/ditolak, ada pengajuan baru untuk
/// diproses, pengumuman baru, event dibatalkan, hari-H event yang
/// diikutinya, kontrak karyawan yang dikelolanya tersisa ≤ 30 hari).
/// Aplikasi hanya membaca & menandai sudah dibaca.
///
/// Catatan backend: [changes] di mock berbunyi langsung; di API nyata
/// gunakan push (FCM / WebSocket) atau polling berkala.
abstract class NotificationRepository {
  Listenable get changes;

  /// Terbaru lebih dulu.
  Future<List<AppNotification>> fetch(AuthUser user);

  Future<int> unreadCount(AuthUser user);

  Future<void> markRead(AuthUser user, {required String id});

  Future<void> markAllRead(AuthUser user);

  /// Menghapus semua notifikasi milik [user] (permanen).
  Future<void> clearAll(AuthUser user);

  /// Siaran Super Admin: judul + isi bebas ke [audience].
  /// Mengembalikan jumlah penerima. Non-Super Admin ditolak server.
  Future<int> broadcast(
    AuthUser actor, {
    required String title,
    required String body,
    required BroadcastAudience audience,
  });
}

/// Sasaran siaran Super Admin.
enum BroadcastAudience {
  all('Semua karyawan'),
  staff('Staff saja'),
  managers('Manager & Super Admin');

  const BroadcastAudience(this.label);

  final String label;
}

enum NotificationKind {
  leaveApproved,
  leaveRejected,
  correctionApproved,
  correctionRejected,

  /// Ada pengajuan cuti / koreksi / luar-area baru yang perlu diproses.
  reviewRequested,
  announcement,
  eventCancelled,

  /// Hari ini event yang diikutinya berlangsung (untuk crew).
  eventToday,

  /// Karyawan baru mendaftar mandiri (untuk Manager & Super Admin).
  accountRegistered,

  /// Kontrak PKWT / magang / masa percobaan karyawan yang dikelola tersisa
  /// ≤ 30 hari (untuk Manager & Super Admin yang berhak mengelolanya).
  contractExpiring,

  /// Kontrak karyawan yang dikelola sudah lewat tanggal berakhirnya tetapi
  /// akun masih aktif (maks. 90 hari lewat, agar riwayat lama tidak
  /// meng-spam).
  contractExpired,

  /// Pengajuan absensi luar-area disetujui / ditolak.
  outOfAreaApproved,
  outOfAreaRejected,

  /// Pengajuan lembur disetujui / ditolak.
  overtimeApproved,
  overtimeRejected,

  /// Cuti tahunan dipotong untuk cuti bersama (untuk karyawan yang
  /// terpotong).
  collectiveLeaveApplied,

  /// Surat peringatan diterbitkan / ditanggapi (untuk karyawan, manager,
  /// dan Super Admin sesuai cakupannya).
  warningIssued,

  /// SP aktif yang akan kedaluwarsa ≤ 30 hari (untuk Super Admin).
  warningExpiring;

  /// Menu tujuan saat notifikasi diketuk.
  NotificationTarget get target => switch (this) {
    leaveApproved || leaveRejected || collectiveLeaveApplied =>
        NotificationTarget.leave,
    correctionApproved ||
    correctionRejected ||
    outOfAreaApproved ||
    outOfAreaRejected => NotificationTarget.attendance,
    overtimeApproved || overtimeRejected => NotificationTarget.leave,
    reviewRequested => NotificationTarget.approvals,
    announcement => NotificationTarget.dashboard,
    eventCancelled || eventToday => NotificationTarget.events,
    accountRegistered || contractExpiring || contractExpired =>
        NotificationTarget.employees,
    warningIssued || warningExpiring => NotificationTarget.warnings,
  };
}

enum NotificationTarget {
  dashboard,
  attendance,
  leave,
  events,
  approvals,
  employees,
  warnings,
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    this.refType,
    this.refId,
  });

  final String id;
  final NotificationKind kind;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;

  /// Tautan ke pengajuan spesifik (mis. refType=outOfArea, refId=id).
  /// null = buka menu tujuan saja.
  final String? refType;
  final String? refId;
}
