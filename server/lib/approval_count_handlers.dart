import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

import 'authz.dart';
import 'config.dart';
import 'db.dart';

Response json(Object body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

/// Jumlah pengajuan yang masih menunggu diproses untuk badge menu
/// Persetujuan. Filternya sengaja sama persis dengan empat halaman antrean.
Future<Response> approvalCount(
  Request req,
  Db db,
  Config cfg,
) async {
  try {
    final actor = await authedUser(req, db, cfg);
    if (actor == null) {
      return json({'message': 'Sesi berakhir. Silakan masuk kembali.'}, status: 401);
    }
    final role = actor['role'] as String;
    if (!isManagerLike(role)) {
      return json({'message': 'Hanya Manager, BOD, dan Super Admin.'}, status: 403);
    }
    final me = (actor['username'] as String).toLowerCase();

    // Manager & BOD hanya boleh memproses staff; Super Admin semua peran.
    const scope =
        "AND (@role IN ('superadmin','manager','bod') OR u.role='staff')";

    Future<int> count(String table, {bool active = false}) async {
      final activeSql = active ? 'AND u.active' : '';
      final rs = await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT COUNT(*) AS c FROM $table t
          JOIN users u ON u.id=t.user_id
        WHERE t.status='pending'
          AND LOWER(u.username)<>@me
          $activeSql
          $scope
      '''), parameters: {'me': me, 'role': role}));
      return int.parse((rs.first.toColumnMap()['c'] as Object).toString());
    }

    final leave = await count('leave_requests', active: true);
    final overtime = await count('overtime_requests', active: true);
    final correction = await count('attendance_corrections');
    final outOfArea = await count('out_of_area_requests');

    return json({
      'total': leave + overtime + correction + outOfArea,
      'leave': leave,
      'overtime': overtime,
      'correction': correction,
      'outOfArea': outOfArea,
    });
  } catch (_) {
    return json({'message': 'Gagal menghitung antrean persetujuan.'}, status: 500);
  }
}
