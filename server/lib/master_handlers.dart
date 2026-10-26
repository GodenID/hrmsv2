import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'authz.dart';
import 'config.dart';
import 'db.dart';
import 'upload_handlers.dart' show json, readJson;

class _Http implements Exception {
  const _Http(this.status, this.message);
  final int status;
  final String message;
}

Map<String, dynamic> _row(dynamic r) =>
    (r.toColumnMap() as Map).map((k, v) => MapEntry(k.toString(), v));

/// Master data organisasi: divisi & jabatan.
///
/// - `GET /master/...` untuk semua pengguna terautentikasi (dipakai formulir
///   karyawan dan penargetan pengumuman).
/// - `POST/PATCH/DELETE` hanya Super Admin.
///
/// Hapus ditolak bila masih dipakai karyawan; nonaktifkan sebagai gantinya
/// agar data lama tetap utuh.
Router masterRouter(Db db, Config cfg) {
  final r = Router();

  Future<Map<String, dynamic>> me(Request req) async {
    final u = await authedUser(req, db, cfg);
    if (u == null) {
      throw const _Http(401, 'Sesi berakhir. Silakan masuk kembali.');
    }
    return u;
  }

  Future<Map<String, dynamic>> superadmin(Request req) async {
    final u = await me(req);
    if (u['role'] != 'superadmin') {
      throw const _Http(403, 'Hanya Super Admin yang dapat mengubah master data.');
    }
    return u;
  }

  // ---------- divisi ----------
  Map<String, dynamic> divisionJson(Map<String, dynamic> m) => {
        'code': (m['code'] ?? '').toString(),
        'label': (m['label'] ?? '').toString(),
        'active': m['active'] == true,
        'employees': ((m['employees'] as num?) ?? 0).toInt(),
      };

  Future<Map<String, dynamic>?> divisionOf(TxSession tx, String code) async {
    final rows = await tx.execute(Sql.named('''
      SELECT d.code, d.label, d.active,
             (SELECT COUNT(*) FROM users u WHERE u.division=d.code) AS employees
      FROM divisions d WHERE d.code=@c
    '''), parameters: {'c': code});
    return rows.isEmpty ? null : _row(rows.first);
  }

  r.get('/master/divisions', (Request req) async {
    try {
      await me(req);
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT d.code, d.label, d.active,
               (SELECT COUNT(*) FROM users u WHERE u.division=d.code) AS employees
        FROM divisions d
        ORDER BY d.active DESC, d.label
      ''')));
      return json({'divisions': [for (final row in rows) divisionJson(_row(row))]});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  /// "Produksi Prasasti" -> "produksiPrasasti". Kode tidak bisa diubah
  /// setelah tersimpan karena dipakai data karyawan & pengumuman.
  String slug(String label) {
    final words = label
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    final first = words.first.toLowerCase();
    final rest = words
        .skip(1)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join();
    return '$first$rest';
  }

  r.post('/master/divisions', (Request req) async {
    try {
      await superadmin(req);
      final b = await readJson(req);
      final label = ((b['label'] ?? '') as Object).toString().trim();
      if (label.length < 2 || label.length > 60) {
        throw const _Http(422, 'Nama divisi 2-60 karakter.');
      }
      final base = slug(label);
      if (base.length < 2 || !RegExp(r'^[a-z]').hasMatch(base)) {
        throw const _Http(422, 'Nama divisi harus memuat huruf.');
      }
      final created = await db.pool.runTx((tx) async {
        var code = base.substring(0, base.length > 40 ? 40 : base.length);
        var suffix = 2;
        while (true) {
          final clash = await tx.execute(
            Sql.named('SELECT 1 FROM divisions WHERE lower(code)=lower(@c)'),
            parameters: {'c': code},
          );
          if (clash.isEmpty) break;
          final tail = suffix.toString();
          final head = base.substring(
            0,
            base.length + tail.length > 40 ? 40 - tail.length : base.length,
          );
          code = '$head$tail';
          suffix++;
          if (suffix > 99) {
            throw const _Http(409, 'Terlalu banyak divisi dengan nama mirip.');
          }
        }
        await tx.execute(
          Sql.named('INSERT INTO divisions(code, label) VALUES(@c, @l)'),
          parameters: {'c': code, 'l': label},
        );
        return divisionOf(tx, code);
      });
      return json({'division': divisionJson(created!)}, status: 201);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.patch('/master/divisions/<code>', (Request req, String code) async {
    try {
      await superadmin(req);
      final b = await readJson(req);
      final updated = await db.pool.runTx((tx) async {
        final cur = await divisionOf(tx, code);
        if (cur == null) throw const _Http(404, 'Divisi tidak ditemukan.');
        final label = b.containsKey('label')
            ? ((b['label'] ?? '') as Object).toString().trim()
            : (cur['label'] as String);
        if (label.length < 2 || label.length > 60) {
          throw const _Http(422, 'Nama divisi 2-60 karakter.');
        }
        final active =
            b.containsKey('active') ? b['active'] == true : cur['active'] == true;
        if (!active && (cur['employees'] as num).toInt() > 0) {
          throw _Http(409,
              'Divisi masih dipakai ${cur['employees']} karyawan. Pindahkan dulu.');
        }
        await tx.execute(Sql.named(
          'UPDATE divisions SET label=@l, active=@a WHERE code=@c',
        ), parameters: {'l': label, 'a': active, 'c': code});
        return divisionOf(tx, code);
      });
      return json({'division': divisionJson(updated!)});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.delete('/master/divisions/<code>', (Request req, String code) async {
    try {
      await superadmin(req);
      await db.pool.runTx((tx) async {
        final cur = await divisionOf(tx, code);
        if (cur == null) throw const _Http(404, 'Divisi tidak ditemukan.');
        final used = (cur['employees'] as num).toInt();
        if (used > 0) {
          throw _Http(409,
              'Divisi masih dipakai $used karyawan. Pindahkan atau nonaktifkan dulu.');
        }
        await tx.execute(
          Sql.named('DELETE FROM divisions WHERE code=@c'),
          parameters: {'c': code},
        );
      });
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  // ---------- jabatan ----------
  Map<String, dynamic> positionJson(Map<String, dynamic> m) => {
        'id': (m['id'] ?? '').toString(),
        'name': (m['name'] ?? '').toString(),
        'active': m['active'] == true,
        'employees': ((m['employees'] as num?) ?? 0).toInt(),
      };

  Future<Map<String, dynamic>?> positionOf(TxSession tx, String id) async {
    if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) return null;
    final rows = await tx.execute(Sql.named('''
      SELECT p.id, p.name, p.active,
             (SELECT COUNT(*) FROM users u WHERE lower(btrim(u.position))=lower(btrim(p.name))) AS employees
      FROM positions p WHERE p.id=@i::uuid
    '''), parameters: {'i': id});
    return rows.isEmpty ? null : _row(rows.first);
  }

  r.get('/master/positions', (Request req) async {
    try {
      await me(req);
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT p.id, p.name, p.active,
               (SELECT COUNT(*) FROM users u WHERE lower(btrim(u.position))=lower(btrim(p.name))) AS employees
        FROM positions p
        ORDER BY p.active DESC, p.name
      ''')));
      return json({'positions': [for (final row in rows) positionJson(_row(row))]});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/master/positions', (Request req) async {
    try {
      await superadmin(req);
      final b = await readJson(req);
      final name = ((b['name'] ?? '') as Object).toString().trim();
      if (name.length < 2 || name.length > 60) {
        throw const _Http(422, 'Nama jabatan 2-60 karakter.');
      }
      final created = await db.pool.runTx((tx) async {
        final clash = await tx.execute(
          Sql.named('SELECT 1 FROM positions WHERE lower(btrim(name))=lower(btrim(@n))'),
          parameters: {'n': name},
        );
        if (clash.isNotEmpty) {
          throw const _Http(409, 'Jabatan itu sudah ada.');
        }
        final ins = await tx.execute(
          Sql.named('INSERT INTO positions(name) VALUES(@n) RETURNING id'),
          parameters: {'n': name},
        );
        return positionOf(
          tx,
          (ins.first.toColumnMap()['id'] as Object).toString(),
        );
      });
      return json({'position': positionJson(created!)}, status: 201);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.patch('/master/positions/<id>', (Request req, String id) async {
    try {
      await superadmin(req);
      final b = await readJson(req);
      final updated = await db.pool.runTx((tx) async {
        final cur = await positionOf(tx, id);
        if (cur == null) throw const _Http(404, 'Jabatan tidak ditemukan.');
        final name = b.containsKey('name')
            ? ((b['name'] ?? '') as Object).toString().trim()
            : (cur['name'] as String);
        if (name.length < 2 || name.length > 60) {
          throw const _Http(422, 'Nama jabatan 2-60 karakter.');
        }
        final active = b.containsKey('active')
            ? b['active'] == true
            : cur['active'] == true;
        if (!active && (cur['employees'] as num).toInt() > 0) {
          throw _Http(409,
              'Jabatan masih dipakai ${cur['employees']} karyawan. Pindahkan dulu.');
        }
        if (name != cur['name']) {
          final clash = await tx.execute(
            Sql.named('SELECT 1 FROM positions WHERE lower(btrim(name))=lower(btrim(@n)) AND id<>@i::uuid'),
            parameters: {'n': name, 'i': id},
          );
          if (clash.isNotEmpty) {
            throw const _Http(409, 'Jabatan itu sudah ada.');
          }
        }
        await tx.execute(
          Sql.named('UPDATE positions SET name=@n, active=@a WHERE id=@i::uuid'),
          parameters: {'n': name, 'a': active, 'i': id},
        );
        return positionOf(tx, id);
      });
      return json({'position': positionJson(updated!)});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.delete('/master/positions/<id>', (Request req, String id) async {
    try {
      await superadmin(req);
      await db.pool.runTx((tx) async {
        final cur = await positionOf(tx, id);
        if (cur == null) throw const _Http(404, 'Jabatan tidak ditemukan.');
        final used = (cur['employees'] as num).toInt();
        if (used > 0) {
          throw _Http(409,
              'Jabatan masih dipakai $used karyawan. Pindahkan atau nonaktifkan dulu.');
        }
        await tx.execute(
          Sql.named('DELETE FROM positions WHERE id=@i::uuid'),
          parameters: {'i': id},
        );
      });
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  return r;
}
