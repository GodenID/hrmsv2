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

/// Pastikan tabel bagian event ada walau migrasi otomatis tidak dijalankan.
/// Idempoten: aman dipanggil setiap server mulai.
Future<void> ensureEventCrewRoles(Db db) async {
  await db.pool.runTx((tx) async {
    await tx.execute(Sql.named('''
      CREATE TABLE IF NOT EXISTS event_crew_roles (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        code TEXT NOT NULL UNIQUE,
        label TEXT NOT NULL,
        note_hint TEXT NOT NULL DEFAULT 'Tambahkan keterangan bila perlu',
        requires_note BOOLEAN NOT NULL DEFAULT FALSE,
        sort_order INT NOT NULL DEFAULT 0,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now()
      )
    '''));
    const seeds = [
      ('crew', 'Crew', 'mis. Crew panggung, crew logistik', false, 1),
      ('pic', 'PIC', 'mis. PIC Venue, PIC Talent, PIC Konsumsi', true, 2),
      ('pm', 'PM', 'mis. Project manager utama', false, 3),
      ('sla', 'SLA', 'Tambahkan keterangan bila perlu', false, 4),
      ('slb', 'SLB', 'Tambahkan keterangan bila perlu', false, 5),
      ('slc', 'SLC', 'Tambahkan keterangan bila perlu', false, 6),
      ('design', 'Design', 'mis. Desain panggung, materi publikasi', false, 7),
    ];
    // Hanya isi tabel kosong. Bagian yang dihapus Super Admin tidak boleh
    // muncul lagi setiap server mulai.
    final count = await tx.execute(
        Sql.named('SELECT COUNT(*) AS c FROM event_crew_roles'));
    if (int.parse((count.first.toColumnMap()['c'] as Object).toString()) > 0) {
      return;
    }
    for (final seed in seeds) {
      await tx.execute(Sql.named('''
        INSERT INTO event_crew_roles(code, label, note_hint, requires_note, sort_order)
        VALUES(@c, @l, @h, @r, @s)
        ON CONFLICT (code) DO NOTHING
      '''), parameters: {
        'c': seed.$1,
        'l': seed.$2,
        'h': seed.$3,
        'r': seed.$4,
        's': seed.$5,
      });
    }
  });
}

/// Pastikan tabel hari kehadiran partisipan ada walau migrasi otomatis
/// tidak dijalankan. Idempoten: aman dipanggil setiap server mulai.
Future<void> ensureEventCrewDates(Db db) async {
  await db.pool.runTx((tx) async {
    await tx.execute(Sql.named('''
      CREATE TABLE IF NOT EXISTS event_crew_dates (
        event_id UUID NOT NULL,
        username TEXT NOT NULL,
        date DATE NOT NULL,
        PRIMARY KEY (event_id, username, date),
        FOREIGN KEY (event_id, username)
          REFERENCES event_crew(event_id, username) ON DELETE CASCADE
      )
    '''));
    await tx.execute(Sql.named('''
      CREATE INDEX IF NOT EXISTS event_crew_dates_event_idx
        ON event_crew_dates(event_id)
    '''));
  });
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

  bool canManage(String role) => isManagerLike(role);

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
    final dateRs = await tx.execute(Sql.named('''
      SELECT username, date FROM event_crew_dates
      WHERE event_id=@i::uuid ORDER BY username, date
    '''), parameters: {'i': (e['id'] as Object).toString()});
    final datesByUser = <String, List<String>>{};
    for (final row in dateRs) {
      final m = row.toColumnMap();
      datesByUser
          .putIfAbsent((m['username'] as Object).toString(), () => [])
          .add((m['date'] as DateTime).toIso8601String().substring(0, 10));
    }
    final roleRs = await tx.execute(Sql.named('''
      SELECT id, code, label, note_hint, requires_note
      FROM event_crew_roles ORDER BY sort_order, label
    '''));
    final catRs = await tx.execute(Sql.named('SELECT id, name FROM event_categories WHERE id=@i'),
        parameters: {'i': e['category_id']});
    final cat = catRs.isEmpty
        ? {'id': e['category_id'], 'name': e['category_id']}
        : catRs.first.toColumnMap();
    Map<String, dynamic>? entity;
    if (e['entity_id'] != null) {
      final entRs = await tx.execute(
          Sql.named('SELECT id, name, active FROM event_entities WHERE id=@i::uuid'),
          parameters: {'i': (e['entity_id'] as Object).toString()});
      if (entRs.isNotEmpty) {
        final m = entRs.first.toColumnMap();
        entity = {
          'id': (m['id'] as Object).toString(),
          'name': m['name'],
          'active': m['active'],
        };
      }
    }
    final po = (e['po_value'] as num).toInt();
    return {
      'id': (e['id'] as Object).toString(),
      'name': e['name'],
      'company': e['company'],
      'category': {'id': cat['id'], 'name': cat['name']},
      'entity': entity,
      'startDate': (e['start_date'] as DateTime).toIso8601String().substring(0, 10),
      'endDate': (e['end_date'] as DateTime).toIso8601String().substring(0, 10),
      'location': e['location'],
      // Nilai PO hanya untuk Manager/BOD/Super Admin. Staff melihat ukuran
      // event (size) tanpa nominalnya.
      'poValue': viewer['role'] == 'staff' ? null : po,
      'size': classify(po, thr),
      'createdBy': e['created_by'],
      'roles': [
        for (final row in roleRs)
          {
            'id': (row.toColumnMap()['id'] as Object).toString(),
            'code': row.toColumnMap()['code'],
            'label': row.toColumnMap()['label'],
            'noteHint': row.toColumnMap()['note_hint'],
            'requiresNote': row.toColumnMap()['requires_note'],
          }
      ],
      'crew': [
        for (final row in crewRs)
          {
            'username': row.toColumnMap()['username'],
            'fullName': row.toColumnMap()['full_name'],
            'role': row.toColumnMap()['role'],
            'note': row.toColumnMap()['note'],
            'joinedAt': isoUtc(row.toColumnMap()['joined_at'] as DateTime),
            'dates': datesByUser[(row.toColumnMap()['username'] as Object).toString()] ??
                const <String>[],
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

  // ---------- entity ----------
  r.get('/events/entities', (Request req) async {
    try {
      await me(req);
      final rows = await db.pool.runTx((tx) => tx.execute(
          Sql.named('SELECT id, name, active FROM event_entities ORDER BY name')));
      return json({
        'entities': [
          for (final row in rows)
            {
              'id': (row.toColumnMap()['id'] as Object).toString(),
              'name': row.toColumnMap()['name'],
              'active': row.toColumnMap()['active'],
            }
        ]
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/events/entities', (Request req) async {
    try {
      final actor = await me(req);
      if (!canManage(actor['role'] as String)) {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat menambah entity.');
      }
      final b = await readJson(req);
      final name = ((b['name'] ?? '') as String).trim();
      if (name.length < 2) throw const _Http(422, 'Nama entity minimal 2 karakter.');
      if (name.length > 80) throw const _Http(422, 'Nama entity maksimal 80 karakter.');
      final saved = await db.pool.runTx((tx) async {
        final dup = await tx.execute(Sql.named(
          'SELECT id FROM event_entities WHERE LOWER(BTRIM(name))=LOWER(@n)',
        ), parameters: {'n': name});
        if (dup.isNotEmpty) throw _Http(409, 'Entity "$name" sudah ada.');
        final ins = await tx.execute(Sql.named(
          'INSERT INTO event_entities(name) VALUES(@n) RETURNING id, name, active',
        ), parameters: {'n': name});
        return ins.first.toColumnMap();
      });
      return json({
        'id': (saved['id'] as Object).toString(),
        'name': saved['name'],
        'active': saved['active'],
      }, status: 201);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.patch('/events/entities/<id>', (Request req, String id) async {
    try {
      final actor = await me(req);
      if (!canManage(actor['role'] as String)) {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat mengubah entity.');
      }
      final b = await readJson(req);
      final hasName = b.containsKey('name');
      final hasActive = b.containsKey('active');
      if (!hasName && !hasActive) {
        throw const _Http(422, 'Tidak ada perubahan entity.');
      }
      if (hasActive && b['active'] is! bool) {
        throw const _Http(422, 'Status aktif entity tidak valid.');
      }
      if (hasName) {
        final name = ((b['name'] ?? '') as String).trim();
        if (name.length < 2) throw const _Http(422, 'Nama entity minimal 2 karakter.');
        if (name.length > 80) throw const _Http(422, 'Nama entity maksimal 80 karakter.');
      }
      final saved = await db.pool.runTx((tx) async {
        final cur = await tx.execute(Sql.named(
          'SELECT id, name, active FROM event_entities WHERE id=@i::uuid',
        ), parameters: {'i': id});
        if (cur.isEmpty) throw const _Http(404, 'Entity tidak ditemukan.');
        final curMap = cur.first.toColumnMap();
        final name = hasName
            ? ((b['name'] ?? '') as String).trim()
            : (curMap['name'] as String);
        final active = hasActive ? b['active'] as bool : curMap['active'] as bool;
        if (hasName) {
          final dup = await tx.execute(Sql.named(
            'SELECT id FROM event_entities WHERE LOWER(BTRIM(name))=LOWER(@n) AND id<>@i::uuid',
          ), parameters: {'n': name, 'i': id});
          if (dup.isNotEmpty) throw _Http(409, 'Entity "$name" sudah ada.');
        }
        final upd = await tx.execute(Sql.named(
          'UPDATE event_entities SET name=@n, active=@a WHERE id=@i::uuid RETURNING id, name, active',
        ), parameters: {'n': name, 'a': active, 'i': id});
        return upd.first.toColumnMap();
      });
      return json({
        'id': (saved['id'] as Object).toString(),
        'name': saved['name'],
        'active': saved['active'],
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.delete('/events/entities/<id>', (Request req, String id) async {
    try {
      final actor = await me(req);
      if (!canManage(actor['role'] as String)) {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat menghapus entity.');
      }
      await db.pool.runTx((tx) async {
        final used = await tx.execute(Sql.named(
          'SELECT COUNT(*) AS c FROM events WHERE entity_id=@i::uuid',
        ), parameters: {'i': id});
        final n = int.parse((used.first.toColumnMap()['c'] as Object).toString());
        if (n > 0) {
          throw _Http(400, 'Entity dipakai $n event. Pindahkan eventnya dulu sebelum menghapus.');
        }
        final del = await tx.execute(
          Sql.named('DELETE FROM event_entities WHERE id=@i::uuid'),
          parameters: {'i': id},
        );
        if (del.affectedRows == 0) throw const _Http(404, 'Entity tidak ditemukan.');
      });
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  // ---------- bagian crew (Master data) ----------
  Map<String, dynamic> roleJson(Map<String, dynamic> m, {int used = 0}) => {
        'id': (m['id'] as Object).toString(),
        'code': m['code'],
        'label': m['label'],
        'noteHint': m['note_hint'],
        'requiresNote': m['requires_note'],
        'used': used,
      };

  r.get('/events/crew-roles', (Request req) async {
    try {
      await me(req);
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT r.id, r.code, r.label, r.note_hint, r.requires_note,
               (SELECT COUNT(*) FROM event_crew c WHERE c.role=r.code) AS used
        FROM event_crew_roles r ORDER BY r.sort_order, r.label
      ''')));
      return json({
        'roles': [
          for (final row in rows)
            roleJson(
              row.toColumnMap(),
              used: int.parse(
                  (row.toColumnMap()['used'] as Object).toString()),
            )
        ]
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/events/crew-roles', (Request req) async {
    try {
      final actor = await me(req);
      if (actor['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Super Admin yang dapat menambah bagian event.');
      }
      final b = await readJson(req);
      final label = ((b['label'] ?? '') as String).trim();
      if (label.length < 2) throw const _Http(422, 'Nama bagian minimal 2 karakter.');
      if (label.length > 40) throw const _Http(422, 'Nama bagian maksimal 40 karakter.');
      final saved = await db.pool.runTx((tx) async {
        final dup = await tx.execute(Sql.named(
          'SELECT id FROM event_crew_roles WHERE LOWER(BTRIM(label))=LOWER(@l)',
        ), parameters: {'l': label});
        if (dup.isNotEmpty) throw _Http(409, 'Bagian "$label" sudah ada.');
        final base = label
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'^_+|_+$'), '');
        final prefix = base.isEmpty
            ? 'bagian'
            : (base.length > 24 ? base.substring(0, 24) : base);
        var code = prefix;
        var n = 1;
        while (true) {
          final used = await tx.execute(Sql.named(
            'SELECT 1 FROM event_crew_roles WHERE code=@c',
          ), parameters: {'c': code});
          if (used.isEmpty) break;
          n++;
          code = '${prefix}_$n';
        }
        final sort = await tx.execute(
            Sql.named('SELECT COALESCE(MAX(sort_order),0)+1 AS n FROM event_crew_roles'));
        final ins = await tx.execute(Sql.named('''
          INSERT INTO event_crew_roles(code, label, sort_order)
          VALUES(@c, @l, @s)
          RETURNING id, code, label, note_hint, requires_note
        '''), parameters: {
          'c': code,
          'l': label,
          's': int.parse(
              (sort.first.toColumnMap()['n'] as Object).toString()),
        });
        return ins.first.toColumnMap();
      });
      return json(roleJson(saved), status: 201);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.delete('/events/crew-roles/<id>', (Request req, String id) async {
    try {
      final actor = await me(req);
      if (actor['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Super Admin yang dapat menghapus bagian event.');
      }
      await db.pool.runTx((tx) async {
        final cur = await tx.execute(Sql.named(
          'SELECT code, label FROM event_crew_roles WHERE id=@i::uuid',
        ), parameters: {'i': id});
        if (cur.isEmpty) throw const _Http(404, 'Bagian tidak ditemukan.');
        final m = cur.first.toColumnMap();
        final used = await tx.execute(Sql.named(
          'SELECT COUNT(*) AS c FROM event_crew WHERE role=@r',
        ), parameters: {'r': m['code']});
        final n = int.parse((used.first.toColumnMap()['c'] as Object).toString());
        if (n > 0) {
          throw _Http(400,
              'Bagian "${m['label']}" dipakai $n partisipan. Pindahkan mereka ke bagian lain dulu.');
        }
        final total = await tx.execute(
            Sql.named('SELECT COUNT(*) AS c FROM event_crew_roles'));
        if (int.parse((total.first.toColumnMap()['c'] as Object).toString()) <= 1) {
          throw const _Http(400, 'Minimal satu bagian event harus tersisa.');
        }
        await tx.execute(
          Sql.named('DELETE FROM event_crew_roles WHERE id=@i::uuid'),
          parameters: {'i': id},
        );
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
      final attends = await tx.execute(Sql.named('''
        SELECT (
          NOT EXISTS (
            SELECT 1 FROM event_crew_dates
            WHERE event_id=@i::uuid AND username=@u
          ) OR EXISTS (
            SELECT 1 FROM event_crew_dates
            WHERE event_id=@i::uuid AND username=@u AND date=@d
          )
        ) AS ok
      '''), parameters: {
        'i': (e['id'] as Object).toString(),
        'u': viewer,
        'd': today.toIso8601String().substring(0, 10),
      });
      if (attends.isEmpty || attends.first.toColumnMap()['ok'] != true) {
        continue;
      }
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
    // Entity wajib: event lama tanpa entity harus diisi dulu lewat formulir
    // atau aksi "Atur entity" sebelum bisa disimpan ulang.
    final entityId = s('entityId');
    if (entityId.isEmpty) {
      throw const _Http(422, 'Entity event wajib dipilih.');
    }
    final ent = await tx.execute(
        Sql.named('SELECT id FROM event_entities WHERE id=@i::uuid'),
        parameters: {'i': entityId});
    if (ent.isEmpty) throw const _Http(422, 'Entity event tidak dikenal.');
    final params = <String, dynamic>{
      'n': s('name'),
      'c': s('company'),
      'cat': s('categoryId'),
      'ent': entityId.isEmpty ? null : entityId,
      'sd': dateOnly(DateTime.parse(b['startDate'] as String)).toIso8601String().substring(0, 10),
      'ed': dateOnly(DateTime.parse(b['endDate'] as String)).toIso8601String().substring(0, 10),
      'l': s('location'),
      'po': (b['poValue'] as num).toInt(),
      'by': actor['full_name'],
    };
    if (id == null) {
      final ins = await tx.execute(Sql.named('''
        INSERT INTO events(name, company, category_id, entity_id, start_date, end_date, location, po_value, created_by)
        VALUES(@n,@c,@cat,@ent::uuid,@sd,@ed,@l,@po,@by) RETURNING *
      '''), parameters: params);
      return ins.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
    }
    final upd = await tx.execute(Sql.named('''
      UPDATE events SET name=@n, company=@c, category_id=@cat, entity_id=@ent::uuid,
        start_date=@sd, end_date=@ed, location=@l, po_value=@po
      WHERE id=@i::uuid RETURNING *
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

  r.post('/events/<id>/join', (Request req, String id) async {
    try {
      final u = await me(req);
      final b = await readJson(req);
      final role = ((b['role'] ?? '') as String);
      final note = ((b['note'] ?? '') as String).trim();
      if (note.length > 80) throw const _Http(422, 'Keterangan maksimal 80 karakter.');
      final e = await db.pool.runTx((tx) async {
        final cur = await tx.execute(
            Sql.named('SELECT * FROM events WHERE id=@i::uuid'), parameters: {'i': id});
        if (cur.isEmpty) {
          throw const _Http(404, 'Event tidak ditemukan. Mungkin sudah dihapus.');
        }
        final roleRs = await tx.execute(Sql.named(
          'SELECT label, requires_note FROM event_crew_roles WHERE code=@c',
        ), parameters: {'c': role});
        if (roleRs.isEmpty) throw const _Http(422, 'Bagian crew tidak dikenal.');
        final rm = roleRs.first.toColumnMap();
        if ((rm['requires_note'] as bool) && note.isEmpty) {
          throw _Http(422,
              'Keterangan wajib untuk ${rm['label']}, mis. ${rm['label']} Venue.');
        }
        final rawDates = (b['dates'] as List?) ?? const <Object>[];
        final picked = <DateTime>{};
        for (final value in rawDates) {
          final parsed = DateTime.tryParse(value.toString());
          if (parsed == null) throw const _Http(422, 'Tanggal kehadiran tidak valid.');
          picked.add(dateOnly(parsed));
        }
        final firstDay = dateOnly(cur.first.toColumnMap()['start_date'] as DateTime);
        final lastDay = dateOnly(cur.first.toColumnMap()['end_date'] as DateTime);
        if (picked.isNotEmpty &&
            picked.any((d) => d.isBefore(firstDay) || d.isAfter(lastDay))) {
          throw const _Http(422, 'Tanggal kehadiran harus berada dalam rentang event.');
        }
        final chosenDates = picked.toList()..sort();
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
        await tx.execute(Sql.named('''
          DELETE FROM event_crew_dates WHERE event_id=@i::uuid AND username=@u
        '''), parameters: {'i': id, 'u': u['username']});
        for (final d in chosenDates) {
          await tx.execute(Sql.named('''
            INSERT INTO event_crew_dates(event_id, username, date)
            VALUES(@i::uuid, @u, @d)
          '''), parameters: {
            'i': id,
            'u': u['username'],
            'd': d.toIso8601String().substring(0, 10),
          });
        }
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
