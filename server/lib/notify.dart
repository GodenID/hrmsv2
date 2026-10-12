import 'package:postgres/postgres.dart';

import 'db.dart';
import 'fcm.dart';

/// Bus push global (diisi sekali saat startup). notifyTx mengirim FCM
/// best-effort setelah INSERT; gagal push tidak menggagalkan transaksi.
class PushBus {
  static Db? db;
  static FcmSender? fcm;

  static void configure({required Db database, required FcmSender sender}) {
    db = database;
    fcm = sender;
  }
}

/// Sisip notifikasi dalam transaksi yang sama dengan aksi pemicunya.
/// [tx] = sesi transaksi aktif (TxSession).
Future<void> notifyTx(
  TxSession tx,
  String username, {
  required String kind,
  required String title,
  required String body,
}) async {
  await tx.execute(
    Sql.named(
      'INSERT INTO notifications(username, kind, title, body) VALUES(@u,@k,@t,@b)',
    ),
    parameters: {'u': username, 'k': kind, 't': title, 'b': body},
  );
  // Push best-effort: token mati / FCM mati / timeout tidak menggagalkan.
  final sender = PushBus.fcm;
  if (sender == null || !sender.enabled) return;
  try {
    final rows = await tx.execute(Sql.named('''
      SELECT f.token FROM fcm_tokens f JOIN users u ON u.id=f.user_id
      WHERE u.username=@u
    '''), parameters: {
      'u': username,
    });
    for (final row in rows) {
      final token = (row.toColumnMap()['token'] ?? '').toString();
      if (token.isEmpty) continue;
      final alive = await sender
          .send(token, title, body, kind)
          .timeout(const Duration(seconds: 10), onTimeout: () => true);
      if (!alive) {
        await tx.execute(Sql.named('DELETE FROM fcm_tokens WHERE token=@t'),
            parameters: {'t': token});
      }
    }
  } catch (_) {
    // Abaikan: notifikasi dalam aplikasi sudah tersimpan.
  }
}

/// username Mikaere aktif dengan role yang bisa me-review [requesterRole],
/// kecuali requester sendiri. Cermin MockStore.reviewersFor.
Future<List<Map<String, dynamic>>> reviewersFor(
  TxSession tx,
  String requesterUsername,
  String requesterRole,
) async {
  final rs = await tx.execute(Sql.named('''
    SELECT username, full_name, role FROM users
    WHERE active AND username<>@me AND role IN ('manager','superadmin')
  '''), parameters: {'me': requesterUsername});
  return [
    for (final row in rs)
      row.toColumnMap().map((k, v) => MapEntry(k.toString(), v)),
  ].where((m) {
    final r = m['role'] as String;
    if (r == 'superadmin') return true;
    return requesterRole == 'staff'; // manager hanya atas staff
  }).toList();
}
