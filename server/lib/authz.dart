import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

import 'config.dart';
import 'db.dart';
import 'tokens.dart';

/// Pengguna terautentikasi dari Bearer token + baris users.
/// null = tanpa token / sesi dicabut / kedaluwarsa / nonaktif.
Future<Map<String, dynamic>?> authedUser(
  Request req,
  Db db,
  Config cfg,
) async {
  final h = req.headers['authorization'] ?? '';
  if (!h.toLowerCase().startsWith('bearer ')) return null;
  final jwt = verifyJwt(h.substring(7).trim(), cfg.jwtSecret);
  if (jwt == null || jwt.jwtId == null || jwt.subject == null) return null;
  return db.pool.runTx((tx) async {
    final s = await tx.execute(
      Sql.named('SELECT revoked_at, expires_at FROM sessions WHERE jti=@j::uuid'),
      parameters: {'j': jwt.jwtId},
    );
    if (s.isEmpty) return null;
    final m = s.first.toColumnMap();
    if (m['revoked_at'] != null) return null;
    if (DateTime.now().toUtc().isAfter((m['expires_at'] as DateTime).toUtc())) {
      return null;
    }
    final u = await tx.execute(
      Sql.named('SELECT * FROM users WHERE id=@i::uuid'),
      parameters: {'i': jwt.subject},
    );
    if (u.isEmpty) return null;
    final um = u.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
    if (um['active'] != true) return null;
    return {'jti': jwt.jwtId, ...um};
  });
}

bool canManageEmployees(String role) => role == 'manager' || role == 'superadmin';

/// manager hanya boleh atas staff; superadmin atas semua.
bool canManageRole(String actorRole, String targetRole) {
  if (actorRole == 'superadmin') return true;
  if (actorRole == 'manager') return targetRole == 'staff';
  return false;
}

String maskNik(String nik) {
  if (nik.length != 16) return '•••• •••• •••• ••••';
  return '${nik.substring(0, 4)} •••• •••• ${nik.substring(12)}';
}
