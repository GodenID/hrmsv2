import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'authz.dart';
import 'config.dart';
import 'dates.dart';
import 'db.dart';
import 'notify.dart';
import 's3.dart';

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

Map<String, dynamic> annJson(
  Map<String, dynamic> a,
  List<Map<String, dynamic>> atts,
) =>
    {
      'id': (a['id'] as Object).toString(),
      'title': a['title'],
      'body': a['body'],
      'authorName': a['author_name'],
      'publishedAt': isoUtc(a['published_at'] as DateTime),
      'updatedAt': isoUtcOpt(a['updated_at'] as DateTime?),
      'expiresAt': isoUtcOpt(a['expires_at'] as DateTime?),
      'pinned': a['pinned'],
      'targetDivisions': ((a['target_divisions'] ?? '') as String)
          .split(',')
          .where((s) => s.isNotEmpty)
          .toList(),
      'attachments': [
        for (final t in atts)
          {
            'name': t['name'],
            'sizeBytes': t['size_bytes'],
            'key': t['s3_key'],
          }
      ],
    };

Router announcementRouter(Db db, Config cfg) {
  final r = Router();

  Future<Map<String, dynamic>> me(Request req) async {
    final u = await authedUser(req, db, cfg);
    if (u == null) throw const _Http(401, 'Sesi berakhir. Silakan masuk kembali.');
    return u;
  }

  Future<List<Map<String, dynamic>>> attsFor(
      TxSession tx, String annId) async {
    final rs = await tx.execute(Sql.named(
      'SELECT name, size_bytes, s3_key FROM announcement_attachments WHERE announcement_id=@i::uuid ORDER BY name',
    ), parameters: {'i': annId});
    return [
      for (final row in rs)
        row.toColumnMap().map((k, v) => MapEntry(k.toString(), v))
    ];
  }

  bool visible(Map<String, dynamic> a, String division, DateTime now) {
    if ((a['published_at'] as DateTime).isAfter(now)) return false;
    final exp = a['expires_at'] as DateTime?;
    if (exp != null && !now.isBefore(exp)) return false;
    final targets = ((a['target_divisions'] ?? '') as String)
        .split(',')
        .where((s) => s.isNotEmpty);
    if (targets.isEmpty) return true;
    return targets.contains(division);
  }

  void requireSuperadmin(Map<String, dynamic> actor) {
    if (actor['role'] != 'superadmin') {
      throw const _Http(403, 'Hanya Super Admin yang dapat mengelola pengumuman.');
    }
  }

  String? validateDraft(Map<String, dynamic> b) {
    if (((b['title'] ?? '') as String).trim().length < 5) {
      return 'Judul minimal 5 karakter.';
    }
    if (((b['body'] ?? '') as String).trim().length < 10) {
      return 'Isi pengumuman minimal 10 karakter.';
    }
    final pub = b['publishAt'] == null ? null : DateTime.tryParse(b['publishAt'] as String);
    final exp = b['expiresAt'] == null ? null : DateTime.tryParse(b['expiresAt'] as String);
    if (pub != null && exp != null && !exp.isAfter(pub)) {
      return 'Tanggal kedaluwarsa harus setelah tanggal terbit.';
    }
    final atts = (b['attachments'] as List?) ?? [];
    if (atts.length > 3) return 'Maksimal 3 lampiran.';
    const exts = {'pdf', 'jpg', 'jpeg', 'png'};
    for (final a in atts) {
      final m = Map<String, dynamic>.from(a as Map);
      final name = ((m['name'] ?? '') as String);
      final size = (m['sizeBytes'] as num?)?.toInt() ?? 0;
      if (!exts.contains(name.split('.').last.toLowerCase())) {
        return 'Format file harus PDF, JPG, atau PNG.';
      }
      if (size > 5 * 1024 * 1024) return 'Ukuran file maksimal 5 MB.';
    }
    return null;
  }

  r.get('/announcements/feed', (Request req) async {
    try {
      final u = await me(req);
      final now = nowWib();
      final rows = await db.pool.runTx((tx) => tx.execute(
          Sql.named('SELECT * FROM announcements ORDER BY published_at DESC')));
      final items = <Map<String, dynamic>>[];
      for (final row in rows) {
        final a = row.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if (!visible(a, (u['division'] ?? '') as String, now)) continue;
        final views = await db.pool.runTx((tx) => tx.execute(Sql.named(
              'SELECT COUNT(*) AS c, BOOL_OR(username=@u) AS me FROM announcement_views WHERE announcement_id=@i::uuid',
            ), parameters: {
              'u': u['username'],
              'i': (a['id'] as Object).toString(),
            }));
        final vm = views.first.toColumnMap();
        items.add({
          'announcement':
              annJson(a, await db.pool.runTx((tx) => attsFor(tx, (a['id'] as Object).toString()))),
          'viewedByMe': vm['me'] == true,
          'viewCount': int.parse((vm['c'] as Object).toString()),
        });
      }
      items.sort((x, y) {
        final xp = (x['announcement'] as Map)['pinned'] == true;
        final yp = (y['announcement'] as Map)['pinned'] == true;
        if (xp != yp) return xp ? -1 : 1;
        return ((y['announcement'] as Map)['publishedAt'] as String)
            .compareTo((x['announcement'] as Map)['publishedAt'] as String);
      });
      return json({'feed': items});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/announcements/<id>/open', (Request req, String id) async {
    try {
      final u = await me(req);
      final a = await db.pool.runTx((tx) async {
        final cur = await tx.execute(Sql.named('SELECT * FROM announcements WHERE id=@i::uuid'),
            parameters: {'i': id});
        if (cur.isEmpty) throw const _Http(404, 'Pengumuman tidak ditemukan. Mungkin sudah dihapus.');
        await tx.execute(Sql.named('''
          INSERT INTO announcement_views(announcement_id, username)
          VALUES(@i::uuid, @u) ON CONFLICT DO NOTHING
        '''), parameters: {'i': id, 'u': u['username']});
        final m = cur.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        return annJson(m, await attsFor(tx, id));
      });
      return json(a);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/announcements/<id>/readers', (Request req, String id) async {
    try {
      await me(req);
      final s3 = storeOf(cfg);
      String? photoUrl(String? key) {
        if (key == null || key.isEmpty || s3 == null) return null;
        return cfg.s3avatarPublic ? s3.publicUrl(key) : s3.presignGet(key);
      }

      final v = await db.pool.runTx((tx) => tx.execute(
          Sql.named('SELECT v.username, u.full_name, u.photo_key, v.viewed_at FROM announcement_views v '
              'LEFT JOIN users u ON u.username=v.username '
              'WHERE v.announcement_id=@i::uuid ORDER BY v.viewed_at DESC'),
          parameters: {'i': id}));
      final seen = <String>{};
      final viewed = <Map<String, dynamic>>[];
      for (final row in v) {
        final m = row.toColumnMap();
        seen.add((m['username'] as String).toLowerCase());
        viewed.add({
          'employee': {
            'username': m['username'],
            'fullName': m['full_name'] ?? m['username'],
            'photoUrl': photoUrl(m['photo_key'] as String?),
          },
          'viewedAt': isoUtc(m['viewed_at'] as DateTime),
        });
      }
      final rest = await db.pool.runTx((tx) => tx.execute(
          Sql.named('SELECT username, full_name, photo_key FROM users WHERE active ORDER BY full_name')));
      final notViewed = <Map<String, dynamic>>[];
      for (final row in rest) {
        final m = row.toColumnMap();
        if (seen.contains((m['username'] as String).toLowerCase())) continue;
        notViewed.add({
          'username': m['username'],
          'fullName': m['full_name'],
          'photoUrl': photoUrl(m['photo_key'] as String?),
        });
      }
      return json({'viewed': viewed, 'notViewed': notViewed});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  Future<Map<String, dynamic>> save(
      TxSession tx, Map<String, dynamic> actor, Map<String, dynamic> b, String? id) async {
    final err = validateDraft(b);
    if (err != null) throw _Http(422, err);
    final title = ((b['title'] ?? '') as String).trim();
    final body = ((b['body'] ?? '') as String).trim();
    final pub = b['publishAt'] == null
        ? null
        : DateTime.tryParse(b['publishAt'] as String)?.toUtc().toIso8601String();
    final exp = b['expiresAt'] == null
        ? null
        : DateTime.tryParse(b['expiresAt'] as String)?.toUtc().toIso8601String();
    final pinned = b['pinned'] == true;
    final targets = [
      for (final v in ((b['targetDivisions'] as List?) ?? [])) (v ?? '').toString()
    ];
    final atts = (b['attachments'] as List?) ?? [];
    // verifikasi key S3 milik penulis
    final s3 = storeOf(cfg);
    final uname = (actor['username'] as String).toLowerCase();
    for (final a in atts) {
      final m = Map<String, dynamic>.from(a as Map);
      final key = ((m['key'] ?? '') as String).trim();
      if (key.isEmpty) continue;
      if (!key.startsWith('announcements/$uname/')) {
        throw const _Http(422, 'Key lampiran tidak valid.');
      }
      if (s3 != null && !await s3.exists(key)) {
        throw const _Http(422, 'Upload lampiran tidak ditemukan. Unggah ulang.');
      }
    }
    late String annId;
    if (id == null) {
      final ins = await tx.execute(Sql.named('''
        INSERT INTO announcements(title, body, author_username, author_name,
          published_at, expires_at, pinned, target_divisions)
        VALUES(@t,@b,@au,@an,COALESCE(@p,now()),@e,@pin,@td) RETURNING *
      '''), parameters: {
        't': title,
        'b': body,
        'au': actor['username'],
        'an': actor['full_name'],
        'p': pub,
        'e': exp,
        'pin': pinned,
        'td': targets.join(','),
      });
      final m = ins.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
      annId = (m['id'] as Object).toString();
      await tx.execute(Sql.named('''
        INSERT INTO announcement_views(announcement_id, username)
        VALUES(@i::uuid,@u) ON CONFLICT DO NOTHING
      '''), parameters: {'i': annId, 'u': actor['username']});
    } else {
      final cur = await tx.execute(Sql.named('SELECT id FROM announcements WHERE id=@i::uuid'),
          parameters: {'i': id});
      if (cur.isEmpty) {
        throw const _Http(404, 'Pengumuman tidak ditemukan. Mungkin sudah dihapus.');
      }
      await tx.execute(Sql.named('''
        UPDATE announcements SET title=@t, body=@b, updated_at=now(),
          published_at=COALESCE(@p,published_at), expires_at=@e,
          pinned=@pin, target_divisions=@td WHERE id=@i::uuid
      '''), parameters: {
        't': title,
        'b': body,
        'p': pub,
        'e': exp,
        'pin': pinned,
        'td': targets.join(','),
        'i': id,
      });
      await tx.execute(Sql.named(
          'DELETE FROM announcement_attachments WHERE announcement_id=@i::uuid'),
          parameters: {'i': id});
      annId = id;
    }
    for (final a in atts) {
      final m = Map<String, dynamic>.from(a as Map);
      await tx.execute(Sql.named('''
        INSERT INTO announcement_attachments(announcement_id, name, size_bytes, s3_key)
        VALUES(@i::uuid,@n,@s,@k)
      '''), parameters: {
        'i': annId,
        'n': ((m['name'] ?? '') as String),
        's': (m['sizeBytes'] as num?)?.toInt() ?? 0,
        'k': (((m['key'] ?? '') as String).isEmpty) ? null : (m['key'] as String),
      });
    }
    final fin = await tx.execute(Sql.named('SELECT * FROM announcements WHERE id=@i::uuid'),
        parameters: {'i': annId});
    final fm = fin.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
    return annJson(fm, await attsFor(tx, annId));
  }

  r.post('/announcements', (Request req) async {
    try {
      final actor = await me(req);
      requireSuperadmin(actor);
      final body = await readJson(req);
      final out =
          await db.pool.runTx((tx) => save(tx, actor, body, null));
      // notifikasi ke yg langsung terlihat & tersasar
      final now = nowWib();
      final divs = out['targetDivisions'] as List;
      final emps = await db.pool.runTx((tx) => tx.execute(Sql.named(
            'SELECT username, division FROM users WHERE active AND username<>@me',
          ), parameters: {'me': actor['username']}));
      final pubAt = DateTime.parse(out['publishedAt'] as String);
      final expAt = out['expiresAt'] == null ? null : DateTime.parse(out['expiresAt'] as String);
      if (!pubAt.isAfter(now) && (expAt == null || now.isBefore(expAt))) {
        await db.pool.runTx((tx) async {
          for (final row in emps) {
            final m = row.toColumnMap();
            if (divs.isNotEmpty && !(divs.contains(m['division']))) continue;
            await notifyTx(tx, m['username'] as String,
                kind: 'announcement',
                title: 'Pengumuman baru',
                body: (out['title'] ?? '').toString(),
                refType: 'announcement',
                refId: (out['id'] ?? '').toString());
          }
        });
      }
      return json(out, status: 201);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.put('/announcements/<id>', (Request req, String id) async {
    try {
      final actor = await me(req);
      requireSuperadmin(actor);
      final body = await readJson(req);
      final out = await db.pool.runTx((tx) => save(tx, actor, body, id));
      return json(out);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.delete('/announcements/<id>', (Request req, String id) async {
    try {
      final actor = await me(req);
      requireSuperadmin(actor);
      final keys = await db.pool.runTx((tx) async {
        final atts = await attsFor(tx, id);
        final n = await tx.execute(Sql.named('DELETE FROM announcements WHERE id=@i::uuid'),
            parameters: {'i': id});
        if (n.affectedRows == 0) {
          throw const _Http(404, 'Pengumuman tidak ditemukan. Mungkin sudah dihapus.');
        }
        return [for (final a in atts) a['s3_key'] as String?];
      });
      final s3 = storeOf(cfg);
      if (s3 != null) {
        for (final k in keys) {
          if (k != null) await s3.delete(k);
        }
      }
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  return r;
}
