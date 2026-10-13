import 'package:flutter/foundation.dart';

import 'auth_repository.dart';
import 'employee.dart';

/// Kontrak surat peringatan (SP1–SP3).
///
/// - **Hanya Super Admin** yang boleh membuat / menerbitkan SP
///   (keputusan produk). Manager & staff hanya membaca dalam cakupannya.
/// - Karyawan menandatangani (atau menolak dengan berita acara + 2 saksi)
///   dan boleh mengajukan sanggahan tertulis.
/// - Satu kejadian = satu tingkat (diambil bobot terberat), tidak pernah
///   naik dua tingkat sekaligus.
///
/// Aturan masa berlaku mengikuti UU Ketenagakerjaan: tiap SP hidup
/// 6 bulan sejak diterbitkan. Melanggar lagi
/// saat SP masih aktif -> naik tingkat; setelah kedaluwarsa -> kembali
/// ke SP 1. Bila SP 3 masih aktif lalu melanggar lagi, sistem menandai
/// "memenuhi syarat PHK" (keputusan PHK tetap manusia, bukan otomatis).
///
/// Implementasi WAJIB menegakkan aturan ini di server.
abstract class WarningRepository {
  Listenable get changes;

  /// Karyawan yang boleh diterbitkan SP oleh [actor] (aktif, bukan diri
  /// sendiri). Hanya Super Admin (selainnya melempar).
  Future<List<EmployeeRef>> fetchIssuableEmployees(AuthUser actor);

  /// Saran tingkat berdasarkan SP yang masih aktif milik [username].
  /// Hanya Super Admin.
  Future<WarningSuggestion> suggestLevel(
    AuthUser actor, {
    required String username,
  });

  /// Menerbitkan SP. Hanya Super Admin. Nama pelanggaran diisi manual
  /// beserta kategorinya (Ringan / Sedang / Berat).
  Future<WarningLetterDetail> issue(
    AuthUser actor, {
    required String username,
    required String violationName,
    required WarningSeverity severity,
    required int level,
    required DateTime incidentDate,
    required String description,
    required String articleRef,
  });

  /// Daftar SP dalam cakupan [actor], terbaru lebih dulu:
  /// Super Admin -> semua; Manager -> karyawan yang boleh dikelolanya;
  /// Staff -> melempar (pakai [fetchMyLetters]).
  Future<List<WarningLetterDetail>> fetchLetters(AuthUser actor);

  /// SP milik sendiri, terbaru lebih dulu. Semua role.
  Future<List<WarningLetterDetail>> fetchMyLetters(AuthUser user);

  /// Tanda tangan digital (setuju diterima, belum tentu setuju isinya)
  /// atau penolakan (berita acara + 2 saksi). Hanya pemilik SP, sekali saja.
  Future<WarningLetterDetail> acknowledge(
    AuthUser user, {
    required String id,
    required bool refused,
    String? witness1,
    String? witness2,
  });

  /// Sanggahan tertulis. Hanya pemilik SP, sekali saja.
  Future<WarningLetterDetail> appeal(
    AuthUser user, {
    required String id,
    required String text,
  });

  /// Merespons sanggahan. Hanya Super Admin.
  /// - [accept] true = sanggahan diterima -> SP dicabut (tetap terlihat
  ///   bertanda "Dicabut", tidak dihitung eskalasi).
  /// - [accept] false = sanggahan ditolak -> SP tetap berlaku.
  Future<WarningLetterDetail> respondAppeal(
    AuthUser actor, {
    required String id,
    required bool accept,
    required String note,
  });
}

/// Bobot pelanggaran. Menentukan pasal & urgensi, bukan tingkat SP
/// (tingkat SP ditentukan riwayat aktif).
enum WarningSeverity {
  ringan('Ringan'),
  sedang('Sedang'),
  berat('Berat');

  const WarningSeverity(this.label);

  final String label;
}

/// Satu surat peringatan yang diterbitkan.
class WarningLetter {
  const WarningLetter({
    required this.id,
    required this.employeeUsername,
    required this.violationName,
    required this.severity,
    required this.level,
    required this.incidentDate,
    required this.description,
    required this.articleRef,
    required this.issuedBy,
    required this.issuedByName,
    required this.issuedAt,
    required this.expiresAt,
    this.acknowledgedAt,
    this.acknowledgedBy,
    this.refused = false,
    this.witness1,
    this.witness2,
    this.appeal,
    this.appealAt,
    this.appealAccepted,
    this.appealResponseNote,
    this.appealRespondedAt,
  });

  final String id;
  final String employeeUsername;

  /// Nama pelanggaran diisi manual saat menerbitkan.
  final String violationName;
  final WarningSeverity severity;

  /// 1, 2, atau 3.
  final int level;
  final DateTime incidentDate;
  final String description;
  final String articleRef;
  final String issuedBy;
  final String issuedByName;
  final DateTime issuedAt;
  final DateTime expiresAt;

  final DateTime? acknowledgedAt;
  final String? acknowledgedBy;

  /// true = menolak tanda tangan (berita acara + saksi).
  final bool refused;
  final String? witness1;
  final String? witness2;

  final String? appeal;
  final DateTime? appealAt;

  /// null = belum direspons; true = diterima (SP dicabut);
  /// false = ditolak (SP tetap berlaku).
  final bool? appealAccepted;
  final String? appealResponseNote;
  final DateTime? appealRespondedAt;

  String get levelLabel => 'SP $level';

  bool get signed => acknowledgedAt != null;

  /// Sanggahan menunggu respons Super Admin.
  bool get appealPending => appeal != null && appealAccepted == null;

  /// SP yang dicabut karena sanggahan diterima.
  bool get voided => appealAccepted == true;

  bool isActive(DateTime now) => !voided && now.isBefore(expiresAt);

  WarningLetter copyWith({
    DateTime? acknowledgedAt,
    String? acknowledgedBy,
    bool? refused,
    String? witness1,
    String? witness2,
    String? appeal,
    DateTime? appealAt,
    bool? appealAccepted,
    String? appealResponseNote,
    DateTime? appealRespondedAt,
  }) => WarningLetter(
    id: id,
    employeeUsername: employeeUsername,
    violationName: violationName,
    severity: severity,
    level: level,
    incidentDate: incidentDate,
    description: description,
    articleRef: articleRef,
    issuedBy: issuedBy,
    issuedByName: issuedByName,
    issuedAt: issuedAt,
    expiresAt: expiresAt,
    acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
    acknowledgedBy: acknowledgedBy ?? this.acknowledgedBy,
    refused: refused ?? this.refused,
    witness1: witness1 ?? this.witness1,
    witness2: witness2 ?? this.witness2,
    appeal: appeal ?? this.appeal,
    appealAt: appealAt ?? this.appealAt,
    appealAccepted: appealAccepted ?? this.appealAccepted,
    appealResponseNote: appealResponseNote ?? this.appealResponseNote,
    appealRespondedAt: appealRespondedAt ?? this.appealRespondedAt,
  );
}

class WarningLetterDetail {
  const WarningLetterDetail({required this.employee, required this.letter});

  final EmployeeRef employee;
  final WarningLetter letter;
}

/// Hasil perhitungan eskalasi untuk satu karyawan.
class WarningSuggestion {
  const WarningSuggestion({
    required this.suggestedLevel,
    required this.activeCount,
    required this.phkEligible,
  });

  /// 1–3. Bila [phkEligible], SP 3 sudah tidak menaikkan lagi.
  final int suggestedLevel;

  /// Jumlah SP yang masih aktif (belum kedaluwarsa).
  final int activeCount;

  /// true = SP 3 masih aktif dan ada pelanggaran baru.
  final bool phkEligible;
}

abstract final class WarningRules {
  /// Kejadian maksimal berapa hari ke belakang yang boleh diterbitkan SP.
  static const int maxIncidentDaysBack = 90;

  static const int minDescription = 20;
  static const int maxDescription = 1000;
  static const int maxAppeal = 1000;
  static const int minName = 3;
  static const int maxName = 120;
  static const int minResponseNote = 10;

  static String? validateDescription(String value) {
    final v = value.trim();
    if (v.length < minDescription) {
      return 'Uraikan kejadian minimal $minDescription karakter.';
    }
    if (v.length > maxDescription) {
      return 'Uraian maksimal $maxDescription karakter.';
    }
    return null;
  }

  static String? validateViolationName(String value) {
    final v = value.trim();
    if (v.length < minName) {
      return 'Nama pelanggaran minimal $minName karakter.';
    }
    if (v.length > maxName) {
      return 'Nama pelanggaran maksimal $maxName karakter.';
    }
    return null;
  }
}
