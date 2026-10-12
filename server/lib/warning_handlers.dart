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

const validityMonths = 6;

Map<String, dynamic> letterJson(
  Map<String, dynamic> l,
  String username,
  String fullName,
) =>
    {
      'employee': {'username': username, 'fullName': fullName},
      'letter': {
        'id': (l['id'] as Object).toString(),
        'employeeUsername': username,
        'violationName': l['violation_name'],
        'severity': l['severity'],
        'level': l['level'],
        'incidentDate': (l['incident_date'] as DateTime).toIso8601String().substring(0, 10),
        'description': l['description'],
        'articleRef': l['article_ref'],
        'issuedBy': l['issued_by'],
        'issuedByName': l['issued_by_name'],
        'issuedAt': (l['issued_at'] as DateTime).toIso8601String(),
        'expiresAt': (l['expires_at'] as DateTime).toIso8601String(),
        'acknowledgedAt': (l['acknowledged_at'] as DateTime?)?.toIso8601String(),
        'acknowledgedBy': l['acknowledged_by'],
        'refused': l['refused'] == true,
        'witness1': l['witness1'],
        'witness2': l['witness2'],
        'appeal': l['appeal'],
        'appealAt': (l['appeal_at'] as DateTime?)?.toIso8601String(),
        'appealAccepted': l['appeal_accepted'],
        'appealResponseNote': l['appeal_response_note'],
        'appealRespondedAt':
            (l['appeal_responded_at'] as DateTime?)?.toIso8601String(),
      },
    };

bool letterActive(Map<String, dynamic> l, DateTime now) {
  if (l['appeal_accepted'] == true) return false;
  return now.isBefore(l['expires_at'] as DateTime);
}

Router warningRouter(Db db, Config cfg) {
  final r = Router();

  Future<Map<String, dynamic>> me(Request req) async {
    final u = await authedUser(req, db, cfg);
    if (u == null) throw const _Http(401, 'Sesi berakhir. Silakan masuk kembali.');
    return u;
  }

  void requireSuperadmin(Map<String, dynamic> actor) {
    if (actor['role'] != 'superadmin') {
      throw const _Http(403, 'Hanya Super Admin yang dapat menerbitkan surat peringatan.');
    }
  }

  Future<List<Map<String, dynamic>>> activeFor(TxSession tx, String userId, DateTime now) async {
    final rs = await tx.execute(Sql.named('''
      SELECT * FROM warnings WHERE employee_user_id=@i::uuid
        AND (appeal_accepted IS NULL OR appeal_accepted=FALSE)
        AND expires_at>@n ORDER BY issued_at
    '''), parameters: {'i': userId, 'n': now.toUtc().toIso8601String()});
    return [
      for (final row in rs)
        row.toColumnMap().map((k, v) => MapEntry(k.toString(), v))
    ];
  }

  r.get('/warnings/issuable', (Request req) async {
    try {
      final actor = await me(req);
      requireSuperadmin(actor);
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT username, full_name FROM users
        WHERE active AND username<>@me ORDER BY full_name
      '''), parameters: {'me': actor['username']}));
      return json({
        'employees': [
          for (final row in rows)
            {'username': row.toColumnMap()['username'], 'fullName': row.toColumnMap()['full_name']}
        ]
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/warnings/suggest', (Request req) async {
    try {
      final actor = await me(req);
      requireSuperadmin(actor);
      final username = (req.url.queryParameters['username'] ?? '').trim().toLowerCase();
      final target = await db.pool.runTx((tx) => tx.execute(
          Sql.named('SELECT id, active FROM users WHERE username=@u'),
          parameters: {'u': username}));
      if (target.isEmpty || target.first.toColumnMap()['active'] != true) {
        return json({'message': 'Karyawan tidak ditemukan atau nonaktif.'}, status: 404);
      }
      final uid = (target.first.toColumnMap()['id'] as Object).toString();
      final active = await db.pool.runTx((tx) => activeFor(tx, uid, nowWib()));
      if (active.any((l) => (l['level'] as int) >= 3)) {
        return json({'suggestedLevel': 3, 'activeCount': active.length, 'phkEligible': true});
      }
      return json({
        'suggestedLevel': (active.length + 1).clamp(1, 3),
        'activeCount': active.length,
        'phkEligible': false,
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/warnings', (Request req) async {
    try {
      final actor = await me(req);
      requireSuperadmin(actor);
      final b = await readJson(req);
      final username = ((b['username'] ?? '') as String).trim().toLowerCase();
      final vname = ((b['violationName'] ?? '') as String).trim();
      final severity = ((b['severity'] ?? '') as String);
      final level = (b['level'] as num?)?.toInt() ?? 0;
      final incident = b['incidentDate'] == null
          ? null
          : dateOnly(DateTime.tryParse(b['incidentDate'] as String) ?? DateTime(1970));
      final desc = ((b['description'] ?? '') as String).trim();
      var article = ((b['articleRef'] ?? '') as String).trim();
      if (vname.length < 3) throw const _Http(422, 'Nama pelanggaran minimal 3 karakter.');
      if (vname.length > 120) throw const _Http(422, 'Nama pelanggaran maksimal 120 karakter.');
      if (!{'ringan', 'sedang', 'berat'}.contains(severity)) {
        throw const _Http(422, 'Bobot pelanggaran tidak dikenal.');
      }
      if (level < 1 || level > 3) throw const _Http(422, 'Tingkat SP harus 1, 2, atau 3.');
      if (incident == null) throw const _Http(422, 'Tanggal kejadian tidak valid.');
      final today = dateOnly(nowWib());
      if (incident.isAfter(today)) {
        throw const _Http(422, 'Tanggal kejadian tidak boleh di masa depan.');
      }
      if (today.difference(incident).inDays > 90) {
        throw const _Http(422, 'Kejadian lebih dari 90 hari lalu sudah kedaluwarsa untuk diterbitkan SP.');
      }
      if (desc.length < 20) {
        throw const _Http(422, 'Uraikan kejadian minimal 20 karakter.');
      }
      if (desc.length > 1000) throw const _Http(422, 'Uraian maksimal 1000 karakter.');
      if (article.isEmpty) throw const _Http(422, 'Pasal peraturan wajib diisi.');
      if (article.length > 200) article = article.substring(0, 200);
      final done = await db.pool.runTx((tx) async {
        final t = await tx.execute(
            Sql.named('SELECT * FROM users WHERE username=@u'), parameters: {'u': username});
        if (t.isEmpty || t.first.toColumnMap()['active'] != true) {
          throw const _Http(404, 'Karyawan tidak ditemukan atau nonaktif.');
        }
        final target = t.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if ((target['username'] as String).toLowerCase() ==
            (actor['username'] as String).toLowerCase()) {
          throw const _Http(403, 'Anda tidak dapat menerbitkan SP untuk diri sendiri.');
        }
        final issuedAt = nowWib();
        final ins = await tx.execute(Sql.named('''
          INSERT INTO warnings(employee_user_id, violation_name, severity, level,
            incident_date, description, article_ref, issued_by, issued_by_name,
            issued_at, expires_at)
          VALUES(@i::uuid,@v,@s,@l,@d,@desc,@a,@ib,@ibn,@ia,@ea) RETURNING *
        '''), parameters: {
          'i': (target['id'] as Object).toString(),
          'v': vname,
          's': severity,
          'l': level,
          'd': incident.toIso8601String().substring(0, 10),
          'desc': desc,
          'a': article,
          'ib': actor['username'],
          'ibn': actor['full_name'],
          'ia': issuedAt.toUtc().toIso8601String(),
          'ea': addMonths(issuedAt, validityMonths).toUtc().toIso8601String(),
        });
        final lm = ins.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        await notifyTx(tx, target['username'] as String,
            kind: 'warningIssued',
            title: 'Surat peringatan SP $level',
            body: 'Anda menerima SP $level ($vname). Buka untuk membaca dan menandatangani.');
        for (final rev in await reviewersFor(
            tx, target['username'] as String, target['role'] as String)) {
          await notifyTx(tx, rev['username'] as String,
              kind: 'warningIssued',
              title: 'SP $level diterbitkan',
              body: '${target['full_name']} menerima SP $level ($vname) dari ${actor['full_name']}.');
        }
        return letterJson(lm, target['username'] as String, target['full_name'] as String);
      });
      return json(done, status: 201);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  Future<List<Map<String, dynamic>>> lettersFor(TxSession tx, String? userId) async {
    final rs = userId == null
        ? await tx.execute(Sql.named('''
            SELECT w.*, u.username, u.full_name AS efn, u.role AS urel FROM warnings w
            JOIN users u ON u.id=w.employee_user_id ORDER BY w.issued_at DESC'''))
        : await tx.execute(Sql.named('''
            SELECT w.*, u.username, u.full_name AS efn, u.role AS urel FROM warnings w
            JOIN users u ON u.id=w.employee_user_id
            WHERE w.employee_user_id=@i::uuid ORDER BY w.issued_at DESC'''),
            parameters: {'i': userId});
    return [
      for (final row in rs)
        (() {
          final m = row.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
          return letterJson(m, m['username'] as String, (m['efn'] ?? m['username']).toString());
        })()
    ];
  }

  r.get('/warnings', (Request req) async {
    try {
      final actor = await me(req);
      if (actor['role'] == 'staff') {
        throw const _Http(403, 'Gunakan menu Peringatan untuk melihat SP Anda sendiri.');
      }
      final all = await db.pool.runTx((tx) => lettersFor(tx, null));
      // manager hanya atas staff (cek peran tiap pemilik)
      final filtered = <Map<String, dynamic>>[];
      for (final d in all) {
        if (actor['role'] == 'superadmin') {
          filtered.add(d);
          continue;
        }
        final letter = d['letter'] as Map;
        final t = await db.pool.runTx((tx) => tx.execute(
            Sql.named('SELECT role FROM users WHERE username=@u'),
            parameters: {'u': (letter['employeeUsername'] as String)}));
        final role = t.isEmpty ? 'staff' : (t.first.toColumnMap()['role'] as String);
        if (canManageRole('manager', role)) filtered.add(d);
      }
      // pengingat H-30 untuk superadmin
      if (actor['role'] == 'superadmin') {
        final now = nowWib();
        await db.pool.runTx((tx) async {
          final rs = await tx.execute(Sql.named('''
            SELECT w.*, u.username, u.full_name AS efn FROM warnings w
            JOIN users u ON u.id=w.employee_user_id
            WHERE w.appeal_accepted IS NULL OR w.appeal_accepted=FALSE
          '''));
          for (final row in rs) {
            final m = row.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
            final exp = m['expires_at'] as DateTime;
            if (now.isBefore(exp) && exp.difference(now).inDays <= 30) {
              await tx.execute(Sql.named('''
                INSERT INTO notifications(id, username, kind, title, body)
                VALUES(@i,@u,'warningExpiring',@t,@b) ON CONFLICT (id) DO NOTHING
              '''), parameters: {
                'i': 'WRN-EXP-${m['id']}',
                'u': actor['username'],
                't': 'SP ${m['level']} segera kedaluwarsa',
                'b': 'SP ${m['level']} ${m['efn']} (${m['violation_name']}) kedaluwarsa.',
              });
            }
          }
        });
      }
      return json({'letters': filtered});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/warnings/mine', (Request req) async {
    try {
      final u = await me(req);
      final list = await db.pool
          .runTx((tx) => lettersFor(tx, (u['id'] as Object).toString()));
      return json({'letters': list});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  Future<Map<String, dynamic>> owned(TxSession tx, String userId, String id) async {
    final rs = await tx.execute(Sql.named('''
      SELECT w.*, u.username, u.full_name AS efn FROM warnings w
      JOIN users u ON u.id=w.employee_user_id
      WHERE w.id=@i::uuid AND w.employee_user_id=@u::uuid
    '''), parameters: {'i': id, 'u': userId});
    if (rs.isEmpty) throw const _Http(404, 'Surat peringatan tidak ditemukan.');
    return rs.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
  }

  Future<void> notifySuperadmins(TxSession tx, String title, String body) async {
    final rs = await tx.execute(
        Sql.named('SELECT username FROM users WHERE active AND role=\'superadmin\''));
    for (final row in rs) {
      await notifyTx(tx, row.toColumnMap()['username'] as String,
          kind: 'warningIssued', title: title, body: body);
    }
  }

  r.post('/warnings/<id>/acknowledge', (Request req, String id) async {
    try {
      final u = await me(req);
      final done = await db.pool.runTx((tx) async {
        final b = await readJson(req);
        final refused = b['refused'] == true;
        final w1 = ((b['witness1'] ?? '') as String).trim();
        final w2 = ((b['witness2'] ?? '') as String).trim();
        final m = await owned(tx, (u['id'] as Object).toString(), id);
        if (m['acknowledged_at'] != null) {
          throw const _Http(400, 'Surat ini sudah ditandatangani.');
        }
        if (refused) {
          if (w1.length < 3 || w2.length < 3) {
            throw const _Http(422, 'Penolakan wajib disertai berita acara dengan 2 nama saksi.');
          }
          if (w1.toLowerCase() == w2.toLowerCase()) {
            throw const _Http(422, 'Kedua saksi harus orang yang berbeda.');
          }
        }
        final upd = await tx.execute(Sql.named('''
          UPDATE warnings SET acknowledged_at=now(), acknowledged_by=@by,
            refused=@r, witness1=@w1, witness2=@w2 WHERE id=@i::uuid RETURNING *
        '''), parameters: {
          'by': u['full_name'],
          'r': refused,
          'w1': refused ? w1 : null,
          'w2': refused ? w2 : null,
          'i': id,
        });
        final lm = upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        final lvl = 'SP ${m['level']}';
        await notifySuperadmins(
            tx,
            refused ? '$lvl ditolak ditandatangani' : '$lvl ditandatangani',
            refused
                ? '${u['full_name']} menolak menandatangani $lvl. Saksi: $w1, $w2.'
                : '${u['full_name']} telah menandatangani $lvl.');
        return letterJson(lm, m['username'] as String, (m['efn'] ?? m['username']).toString());
      });
      return json(done);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/warnings/<id>/appeal', (Request req, String id) async {
    try {
      final u = await me(req);
      final done = await db.pool.runTx((tx) async {
        final b = await readJson(req);
        final text = ((b['text'] ?? '') as String).trim();
        final m = await owned(tx, (u['id'] as Object).toString(), id);
        if (m['appeal'] != null) {
          throw const _Http(400, 'Sanggahan sudah diajukan untuk surat ini.');
        }
        if (text.length < 20) {
          throw const _Http(422, 'Sanggahan minimal 20 karakter agar jelas duduk perkaranya.');
        }
        if (text.length > 1000) {
          throw const _Http(422, 'Sanggahan maksimal 1000 karakter.');
        }
        final upd = await tx.execute(Sql.named('''
          UPDATE warnings SET appeal=@t, appeal_at=now() WHERE id=@i::uuid RETURNING *
        '''), parameters: {'t': text, 'i': id});
        final lm = upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        await notifySuperadmins(tx, 'Sanggahan atas SP ${m['level']}',
            '${u['full_name']} mengajukan sanggahan: "$text"');
        return letterJson(lm, m['username'] as String, (m['efn'] ?? m['username']).toString());
      });
      return json(done);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/warnings/<id>/respond-appeal', (Request req, String id) async {
    try {
      final actor = await me(req);
      requireSuperadmin(actor);
      final done = await db.pool.runTx((tx) async {
        final b = await readJson(req);
        final accept = b['accept'] == true;
        final note = ((b['note'] ?? '') as String).trim();
        if (note.length < 10) {
          throw const _Http(422, 'Tulis catatan respons minimal 10 karakter.');
        }
        final cur = await tx.execute(Sql.named('''
          SELECT w.*, u.username, u.full_name AS efn FROM warnings w
          JOIN users u ON u.id=w.employee_user_id WHERE w.id=@i::uuid
        '''), parameters: {'i': id});
        if (cur.isEmpty) throw const _Http(404, 'Surat peringatan tidak ditemukan.');
        final m = cur.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if (m['appeal'] == null) {
          throw const _Http(400, 'Belum ada sanggahan untuk surat ini.');
        }
        if (m['appeal_accepted'] != null) {
          throw const _Http(400, 'Sanggahan ini sudah direspons.');
        }
        final upd = await tx.execute(Sql.named('''
          UPDATE warnings SET appeal_accepted=@a, appeal_response_note=@n,
            appeal_responded_at=now() WHERE id=@i::uuid RETURNING *
        '''), parameters: {'a': accept, 'n': note, 'i': id});
        final lm = upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        final lvl = 'SP ${m['level']}';
        await notifyTx(tx, m['username'] as String,
            kind: 'warningIssued',
            title: accept ? 'Sanggahan diterima, $lvl dicabut' : 'Sanggahan ditolak, $lvl tetap berlaku',
            body: '${actor['full_name']}: "$note"');
        return letterJson(lm, m['username'] as String, (m['efn'] ?? m['username']).toString());
      });
      return json(done);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  return r;
}
