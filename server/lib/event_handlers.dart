import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'authz.dart';
import 'config.dart';
import 'dates.dart';
import 'db.dart';
import 'notify.dart';

Response json(Object body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

Future<Map<String, dynamic>> readJson(Request req) async {
  try {
    return jsonDecode(await req.readAsString()) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

class _Http implements Exception {
  const _Http(this.status, this.message);
  final int status;
  final String message;
}

const defaultThresholds = {
  'smallMax': 50000000,
  'mediumMax': 200000000,
  'largeMax': 1000000000,
};

String classify(int po, Map<String, int> t) {
  if (po <= t['smallMax']!) return 'small';
  if (po <= t['mediumMax']!) return 'medium';
  if (po <= t['largeMax']!) return 'large';
  return 'overLimit';
}

Router eventRouter(Db db, Config cfg) {
  final r = Router();

  Future<Map<String, dynamic>> me(Request req) async {
    final u = await authedUser(req, db, cfg);
    if (u == null) throw const _Http(401, 'Sesi berakhir. Silakan masuk kembali.');
    return u;
  }

  Future<Map<String, int>> thresholds(TxSession tx) async {
    final rs = await tx.execute(
        Sql.named('SELECT key, value FROM settings WHERE key LIKE \'event_thr_%\''));
    final m = Map<String, int>.from(defaultThresholds);
    for (final row in rs) {
      final c = row.toColumnMap();
      final v = int.tryParse((c['value'] ?? '').toString());
      if (v == null) continue;
      if (c['key'] == 'event_thr_small') m['smallMax'] = v;
      if (c['key'] == 'event_thr_medium') m['mediumMax'] = v;
      if (c['key'] == 'event_thr_large') m['largeMax'] = v;
    }
    return m;
  }

  bool canViewPo(String role) => role == 'manager' || role == 'superadmin';
  bool canManage(String role) => role == 'manager' || role == 'superadmin';

  String? validateEvent(Map<String, dynamic> b) {
    if (((b['name'] ?? '') as String).trim().length < 3) {
      return 'Nama event minimal 3 karakter.';
    }
    if (((b['company'] ?? '') as String).trim().length < 3) {
      return 'Nama perusahaan minimal 3 karakter.';
    }
    if (((b['location'] ?? '') as String).trim().length < 3) {
      return 'Lokasi acara minimal 3 karakter.';
    }
    final s = b['startDate'] == null ? null : DateTime.tryParse(b['startDate'] as String);
    final e = b['endDate'] == null ? null : DateTime.tryParse(b['endDate'] as String);
    if (s == null || e == null) return 'Tanggal event tidak valid.';
    if (dateOnly(e).isBefore(dateOnly(s))) {
      return 'Tanggal selesai tidak boleh sebelum tanggal mulai.';
    }
    if (((b['poValue'] as num?)?.toInt() ?? 0) <= 0) {
      return 'Nilai PO harus lebih dari Rp 0.';
    }
    return null;
  }

  Future<Map<String, dynamic>> itemOf(
    TxSession tx,
    Map<String, dynamic> e,
    Map<String, dynamic> viewer,
    Map<String, int> thr,
  ) async {
    final crewRs = await tx.execute(Sql.named('''
      SELECT username, full_name, role, note, joined_at FROM event_crew
      WHERE event_id=@i::uuid ORDER BY role, full_name
    '''), parameters: {'i': (e['id'] as Object).toString()});
    final catRs = await tx.execute(Sql.named('SELECT id, name FROM event_categories WHERE id=@i'),
        parameters: {'i': e['category_id']});
    final cat = catRs.isEmpty
        ? {'id': e['category_id'], 'name': e['category_id']}
        : catRs.first.toColumnMap();
    final po = (e['po_value'] as num).toInt();
    return {
      'id': (e['id'] as Object).toString(),
      'name': e['name'],
      'company': e['company'],
      'category': {'id': cat['id'], 'name': cat['name']},
      'startDate': (e['start_date'] as DateTime).toIso8601String().substring(0, 10),
      'endDate': (e['end_date'] as DateTime).toIso8601String().substring(0, 10),
      'location': e['location'],
      'poValue': canViewPo(viewer['role'] as String) ? po : null,
      'size': classify(po, thr),
      'createdBy': e['created_by'],
      'crew': [
        for (final row in crewRs)
          {
            'username': row.toColumnMap()['username'],
            'fullName': row.toColumnMap()['full_name'],
            'role': row.toColumnMap()['role'],
            'note': row.toColumnMap()['note'],
            'joinedAt': (row.toColumnMap()['joined_at'] as DateTime).toIso8601String(),
          }
      ],
    };
  }

  // ---------- ambang & kategori ----------
  r.get('/events/thresholds', (Request req) async {
    try {
      await me(req);
      final t = await db.pool.runTx(thresholds);
      return json(t);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.put('/events/thresholds', (Request req) async {
    try {
      final actor = await me(req);
      if (!canManage(actor['role'] as String)) {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat mengatur ambang event.');
      }
      final b = await readJson(req);
      final t = {
        'smallMax': (b['smallMax'] as num?)?.toInt() ?? 0,
        'mediumMax': (b['mediumMax'] as num?)?.toInt() ?? 0,
        'largeMax': (b['largeMax'] as num?)?.toInt() ?? 0,
      };
      if (t['smallMax']! <= 0 || t['mediumMax']! <= 0 || t['largeMax']! <= 0) {
        throw const _Http(422, 'Semua batas harus lebih dari Rp 0.');
      }
      if (t['smallMax']! >= t['mediumMax']!) {
        throw const _Http(422, 'Batas event sedang harus lebih besar dari batas event kecil.');
      }
      if (t['mediumMax']! >= t['largeMax']!) {
        throw const _Http(422, 'Batas event besar harus lebih besar dari batas event sedang.');
      }
      await db.pool.runTx((tx) async {
        for (final e in [('event_thr_small', t['smallMax']!), ('event_thr_medium', t['mediumMax']!), ('event_thr_large', t['largeMax']!)]) {
          await tx.execute(Sql.named(
            'INSERT INTO settings(key,value) VALUES(@k,@v) ON CONFLICT (key) DO UPDATE SET value=@v',
          ), parameters: {'k': e.$1, 'v': '${e.$2}'});
        }
      });
      return json(t);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/events/categories', (Request req) async {
    try {
      await me(req);
      final rows = await db.pool.runTx(
          (tx) => tx.execute(Sql.named('SELECT id, name FROM event_categories ORDER BY name')));
      return json({
        'categories': [
          for (final row in rows)
            {'id': row.toColumnMap()['id'], 'name': row.toColumnMap()['name']}
        ]
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/events/categories', (Request req) async {
    try {
      final actor = await me(req);
      if (!canManage(actor['role'] as String)) {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat mengelola kategori.');
      }
      final b = await readJson(req);
      final id = ((b['id'] ?? '') as String).trim();
      final name = ((b['name'] ?? '') as String).trim();
      if (name.length < 3) throw const _Http(422, 'Nama kategori minimal 3 karakter.');
      if (name.length > 40) throw const _Http(422, 'Nama kategori maksimal 40 karakter.');
      final saved = await db.pool.runTx((tx) async {
        final dup = await tx.execute(Sql.named(
          'SELECT id FROM event_categories WHERE LOWER(name)=LOWER(@n) AND id<>@i',
        ), parameters: {'n': name, 'i': id});
        if (dup.isNotEmpty) throw _Http(409, 'Kategori "$name" sudah ada.');
        if (id.isEmpty) {
          final ins = await tx.execute(Sql.named(
            'INSERT INTO event_categories(id, name) VALUES(@i,@n) RETURNING id, name',
          ), parameters: {
            'i': 'EC-${DateTime.now().millisecondsSinceEpoch}',
            'n': name,
          });
          return ins.first.toColumnMap();
        }
        final upd = await tx.execute(Sql.named(
          'UPDATE event_categories SET name=@n WHERE id=@i RETURNING id, name',
        ), parameters: {'n': name, 'i': id});
        if (upd.isEmpty) throw const _Http(404, 'Kategori tidak ditemukan.');
        return upd.first.toColumnMap();
      });
      return json({'id': saved['id'], 'name': saved['name']});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.delete('/events/categories/<id>', (Request req, String id) async {
    try {
      final actor = await me(req);
      if (!canManage(actor['role'] as String)) {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat mengelola kategori.');
      }
      await db.pool.runTx((tx) async {
        final c = await tx.execute(Sql.named('SELECT COUNT(*) AS c FROM event_categories'));
        if (int.parse((c.first.toColumnMap()['c'] as Object).toString()) <= 1) {
          throw const _Http(400, 'Minimal satu kategori event tersisa.');
        }
        final used = await tx.execute(Sql.named(
          'SELECT COUNT(*) AS c FROM events WHERE category_id=@i',
        ), parameters: {'i': id});
        final n = int.parse((used.first.toColumnMap()['c'] as Object).toString());
        if (n > 0) {
          throw _Http(400, 'Kategori dipakai $n event. Pindahkan eventnya dulu sebelum menghapus.');
        }
        final del = await tx.execute(
            Sql.named('DELETE FROM event_categories WHERE id=@i'), parameters: {'i': id});
        if (del.affectedRows == 0) throw const _Http(404, 'Kategori tidak ditemukan.');
      });
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  // ---------- event ----------
  Future<void> ensureToday(TxSession tx, String viewer, List<Map<String, dynamic>> evs) async {
    final today = dateOnly(nowWib());
    final stamp =
        '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    for (final e in evs) {
      if (today.isBefore(dateOnly(e['start_date'] as DateTime)) ||
          today.isAfter(dateOnly(e['end_date'] as DateTime))) {
        continue;
      }
      final crew = await tx.execute(Sql.named('''
        SELECT username, full_name, role FROM event_crew
        WHERE event_id=@i::uuid AND username=@u
      '''), parameters: {'i': (e['id'] as Object).toString(), 'u': viewer});
      if (crew.isEmpty) continue;
      final m = crew.first.toColumnMap();
      await tx.execute(Sql.named('''
        INSERT INTO notifications(id, username, kind, title, body)
        VALUES(@i,@u,'eventToday',@t,@b) ON CONFLICT (id) DO NOTHING
      '''), parameters: {
        'i': 'EVD-${e['id']}-$stamp',
        'u': viewer,
        't': 'Hari ini: ${e['name']}',
        'b': '${e['company']} di ${e['location']}. Anda bertugas sebagai ${m['role']}. Sampai jumpa di venue!',
      });
    }
  }

  r.get('/events', (Request req) async {
    try {
      final viewer = await me(req);
      final rows = await db.pool.runTx((tx) => tx.execute(
          Sql.named('SELECT * FROM events ORDER BY start_date')));
      final evs = [
        for (final row in rows)
          row.toColumnMap().map((k, v) => MapEntry(k.toString(), v))
      ];
      await db.pool.runTx((tx) => ensureToday(tx, viewer['username'] as String, evs));
      final thr = await db.pool.runTx(thresholds);
      return json({
        'events': [
          for (final e in evs)
            await db.pool.runTx((tx) => itemOf(tx, e, viewer, thr)),
        ]
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/events/<id>', (Request req, String id) async {
    try {
      final viewer = await me(req);
      final rows = await db.pool.runTx((tx) => tx.execute(
          Sql.named('SELECT * FROM events WHERE id=@i::uuid'), parameters: {'i': id}));
      if (rows.isEmpty) {
        return json({'message': 'Event tidak ditemukan. Mungkin sudah dihapus.'}, status: 404);
      }
      final e = rows.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
      await db.pool.runTx((tx) => ensureToday(tx, viewer['username'] as String, [e]));
      final thr = await db.pool.runTx(thresholds);
      return json(await db.pool.runTx((tx) => itemOf(tx, e, viewer, thr)));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  Future<Map<String, dynamic>> writeEvent(
      TxSession tx, Map<String, dynamic> actor, Map<String, dynamic> b, String? id) async {
    final err = validateEvent(b);
    if (err != null) throw _Http(422, err);
    final cat = await tx.execute(Sql.named('SELECT id FROM event_categories WHERE id=@i'),
        parameters: {'i': ((b['categoryId'] ?? '') as String)});
    if (cat.isEmpty) throw const _Http(422, 'Kategori event tidak dikenal.');
    String s(String k) => ((b[k] ?? '') as String).trim();
    final params = <String, dynamic>{
      'n': s('name'),
      'c': s('company'),
      'cat': s('categoryId'),
      'sd': dateOnly(DateTime.parse(b['startDate'] as String)).toIso8601String().substring(0, 10),
      'ed': dateOnly(DateTime.parse(b['endDate'] as String)).toIso8601String().substring(0, 10),
      'l': s('location'),
      'po': (b['poValue'] as num).toInt(),
      'by': actor['full_name'],
    };
    if (id == null) {
      final ins = await tx.execute(Sql.named('''
        INSERT INTO events(name, company, category_id, start_date, end_date, location, po_value, created_by)
        VALUES(@n,@c,@cat,@sd,@ed,@l,@po,@by) RETURNING *
      '''), parameters: params);
      return ins.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
    }
    final upd = await tx.execute(Sql.named('''
      UPDATE events SET name=@n, company=@c, category_id=@cat, start_date=@sd,
        end_date=@ed, location=@l, po_value=@po WHERE id=@i::uuid RETURNING *
    '''), parameters: {...params, 'i': id});
    if (upd.isEmpty) {
      throw const _Http(404, 'Event tidak ditemukan. Mungkin sudah dihapus.');
    }
    return upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
  }

  r.post('/events', (Request req) async {
    try {
      final actor = await me(req);
      if (!canManage(actor['role'] as String)) {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat membuat atau mengubah event.');
      }
      final body = await readJson(req);
      final e = await db.pool.runTx((tx) => writeEvent(tx, actor, body, null));
      final thr = await db.pool.runTx(thresholds);
      return json(await db.pool.runTx((tx) => itemOf(tx, e, actor, thr)), status: 201);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.put('/events/<id>', (Request req, String id) async {
    try {
      final actor = await me(req);
      if (!canManage(actor['role'] as String)) {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat membuat atau mengubah event.');
      }
      final body = await readJson(req);
      final e = await db.pool.runTx((tx) => writeEvent(tx, actor, body, id));
      final thr = await db.pool.runTx(thresholds);
      return json(await db.pool.runTx((tx) => itemOf(tx, e, actor, thr)));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.delete('/events/<id>', (Request req, String id) async {
    try {
      final actor = await me(req);
      if (!canManage(actor['role'] as String)) {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat menghapus event.');
      }
      await db.pool.runTx((tx) async {
        final cur = await tx.execute(
            Sql.named('SELECT * FROM events WHERE id=@i::uuid'), parameters: {'i': id});
        if (cur.isEmpty) {
          throw const _Http(404, 'Event tidak ditemukan. Mungkin sudah dihapus.');
        }
        final e = cur.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        final c = await tx.execute(Sql.named('SELECT username, role FROM event_crew WHERE event_id=@i::uuid'),
            parameters: {'i': id});
        await tx.execute(
            Sql.named('DELETE FROM events WHERE id=@i::uuid'), parameters: {'i': id});
        for (final row in c) {
          final m = row.toColumnMap();
          if ((m['username'] as String).toLowerCase() ==
              (actor['username'] as String).toLowerCase()) {
            continue;
          }
          await notifyTx(tx, m['username'] as String,
              kind: 'eventCancelled',
              title: 'Event dibatalkan',
              body: '${e['name']} dibatalkan oleh ${actor['full_name']}. '
                  'Anda tidak lagi terdaftar sebagai ${m['role']}.');
        }
        return null;
      });
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  const crewRoles = {'crew', 'pic', 'pm', 'sla', 'slb', 'slc', 'design'};

  r.post('/events/<id>/join', (Request req, String id) async {
    try {
      final u = await me(req);
      final b = await readJson(req);
      final role = ((b['role'] ?? '') as String);
      final note = ((b['note'] ?? '') as String).trim();
      if (!crewRoles.contains(role)) throw const _Http(422, 'Bagian crew tidak dikenal.');
      if (role == 'pic' && note.isEmpty) {
        throw const _Http(422, 'Keterangan wajib untuk PIC, mis. PIC Venue atau PIC Talent.');
      }
      if (note.length > 80) throw const _Http(422, 'Keterangan maksimal 80 karakter.');
      final e = await db.pool.runTx((tx) async {
        final cur = await tx.execute(
            Sql.named('SELECT * FROM events WHERE id=@i::uuid'), parameters: {'i': id});
        if (cur.isEmpty) {
          throw const _Http(404, 'Event tidak ditemukan. Mungkin sudah dihapus.');
        }
        await tx.execute(Sql.named('''
          INSERT INTO event_crew(event_id, username, full_name, role, note)
          VALUES(@i::uuid,@u,@fn,@r,@n)
          ON CONFLICT (event_id, username) DO UPDATE
          SET role=@r, note=@n, full_name=@fn
        '''), parameters: {
          'i': id,
          'u': u['username'],
          'fn': u['full_name'],
          'r': role,
          'n': note,
        });
        return cur.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
      });
      final thr = await db.pool.runTx(thresholds);
      return json(await db.pool.runTx((tx) => itemOf(tx, e, u, thr)));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.delete('/events/<id>/leave', (Request req, String id) async {
    try {
      final u = await me(req);
      final e = await db.pool.runTx((tx) async {
        final cur = await tx.execute(
            Sql.named('SELECT * FROM events WHERE id=@i::uuid'), parameters: {'i': id});
        if (cur.isEmpty) {
          throw const _Http(404, 'Event tidak ditemukan. Mungkin sudah dihapus.');
        }
        await tx.execute(Sql.named(
          'DELETE FROM event_crew WHERE event_id=@i::uuid AND username=@u',
        ), parameters: {'i': id, 'u': u['username']});
        return cur.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
      });
      final thr = await db.pool.runTx(thresholds);
      return json(await db.pool.runTx((tx) => itemOf(tx, e, u, thr)));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  return r;
}
