import 'package:postgres/postgres.dart';

/// Sisip notifikasi dalam transaksi yang sama dengan aksi pemicunya.
/// [tx] = sesi transaksi aktif (TxSession).
Future<void> notifyTx(
  TxSession tx,
  String username, {
  required String kind,
  required String title,
  required String body,
}) {
  return tx.execute(
    Sql.named(
      'INSERT INTO notifications(username, kind, title, body) VALUES(@u,@k,@t,@b)',
    ),
    parameters: {'u': username, 'k': kind, 't': title, 'b': body},
  );
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
