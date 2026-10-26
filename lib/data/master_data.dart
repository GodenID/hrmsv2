import 'package:flutter/foundation.dart';

import 'auth_repository.dart';

/// Master data organisasi: divisi & jabatan.
///
/// Semua role boleh membaca (dipakai formulir karyawan, filter daftar, dan
/// penargetan pengumuman). Menambah / mengubah / menghapus hanya Super Admin.
/// Server menegakkan aturan itu; implementasi WAJIB meneruskan penolakannya.
abstract class MasterDataRepository {
  Listenable get changes;

  Future<List<MasterDivision>> fetchDivisions(AuthUser actor);

  Future<List<MasterPosition>> fetchPositions(AuthUser actor);

  Future<MasterDivision> createDivision(
    AuthUser actor, {
    required String label,
  });

  Future<MasterDivision> updateDivision(
    AuthUser actor, {
    required String code,
    String? label,
    bool? active,
  });

  /// Ditolak server bila divisi masih dipakai karyawan.
  Future<void> deleteDivision(AuthUser actor, {required String code});

  Future<MasterPosition> createPosition(
    AuthUser actor, {
    required String name,
  });

  Future<MasterPosition> updatePosition(
    AuthUser actor, {
    required String id,
    String? name,
    bool? active,
  });

  /// Ditolak server bila jabatan masih dipakai karyawan.
  Future<void> deletePosition(AuthUser actor, {required String id});
}

/// Divisi beserta jumlah karyawan yang memakainya.
class MasterDivision {
  const MasterDivision({
    required this.code,
    required this.label,
    required this.active,
    required this.employees,
  });

  final String code;
  final String label;
  final bool active;
  final int employees;

  Division get division => Division(code: code, label: label);
}

/// Jabatan beserta jumlah karyawan yang memakainya.
class MasterPosition {
  const MasterPosition({
    required this.id,
    required this.name,
    required this.active,
    required this.employees,
  });

  final String id;
  final String name;
  final bool active;
  final int employees;
}
