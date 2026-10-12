import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'authz.dart';
import 'config.dart';
import 'db.dart';
import 's3.dart';
import 'validate.dart';

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

const leaveExts = {'pdf', 'jpg', 'jpeg', 'png'};
const avatarExts = {'png', 'jpg', 'jpeg'};
const maxFileBytes = 2 * 1024 * 1024;

String _maskNik(String nik) {
  if (nik.length != 16) return '•••• •••• •••• ••••';
  return '${nik.substring(0, 4)} •••• •••• ${nik.substring(12)}';
}

Router uploadRouter(Db db, Config cfg) {
  final r = Router();

  Future<Map<String, dynamic>> me(Request req) async {
    final u = await authedUser(req, db, cfg);
    if (u == null) throw const _Http(401, 'Sesi berakhir. Silakan masuk kembali.');
    return u;
  }

  // ---------- presign: HP upload langsung ke S3 ----------
  r.post('/uploads/presign', (Request req) async {
    try {
      final u = await me(req);
      final s3 = storeOf(cfg);
      if (s3 == null) {
        throw const _Http(503, 'Penyimpanan file belum dikonfigurasi.');
      }
      final b = await readJson(req);
      final purpose = ((b['purpose'] ?? '') as String);
      final filename = ((b['filename'] ?? '') as String).trim();
      final size = (b['size'] as num?)?.toInt() ?? 0;
      if (purpose != 'leave' && purpose != 'avatar' && purpose != 'announcement') {
        throw const _Http(422, 'Tujuan upload tidak dikenal.');
      }
      final ext = filename.split('.').last.toLowerCase();
      final maxBytes = purpose == 'announcement' ? 5 * 1024 * 1024 : maxFileBytes;
      final allowed = purpose == 'avatar' ? avatarExts : leaveExts;
      if (!allowed.contains(ext)) {
        throw _Http(422,
            purpose == 'avatar' ? 'Foto harus PNG atau JPG.' : 'Lampiran harus PDF / JPG / PNG.');
      }
      if (size <= 0 || size > maxBytes) {
        throw _Http(422,
            purpose == 'announcement' ? 'Ukuran file maksimal 5 MB.' : 'Ukuran file maksimal 2 MB.');
      }
      final uname = (u['username'] as String).toLowerCase();
      final token = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      final key = purpose == 'leave'
          ? 'leave/$uname/$token.$ext'
          : purpose == 'avatar'
              ? 'avatars/$uname/$token.$ext'
              : 'announcements/$uname/$token.$ext';
      final putUrl = s3.presignPut(key);
      return json({
        'key': key,
        'putUrl': putUrl,
        'publicUrl': purpose == 'avatar' && cfg.s3avatarPublic ? s3.publicUrl(key) : null,
        'expiresIn': 900,
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  // ---------- baca file: {url} (presigned utk privat, publik utk avatar) ----------
  r.get('/uploads/view', (Request req) async {
    try {
      final u = await me(req);
      final s3 = storeOf(cfg);
      if (s3 == null) throw const _Http(503, 'Penyimpanan file belum dikonfigurasi.');
      final key = (req.url.queryParameters['key'] ?? '').trim();
      if (key.isEmpty) throw const _Http(422, 'Key file wajib diisi.');
      if (key.startsWith('avatars/')) {
        if (cfg.s3avatarPublic) return json({'url': s3.publicUrl(key)});
        return json({'url': s3.presignGet(key)});
      }
      if (key.startsWith('announcements/')) {
        final row = await db.pool.runTx((tx) => tx.execute(Sql.named('''
          SELECT a.name, a.announcement_id, n.target_divisions
          FROM announcement_attachments a
          JOIN announcements n ON n.id=a.announcement_id
          WHERE a.s3_key=@k LIMIT 1
        '''), parameters: {'k': key}));
        if (row.isEmpty) return json({'message': 'File tidak ditemukan.'}, status: 404);
        final m = row.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        final targets = ((m['target_divisions'] ?? '') as String)
            .split(',')
            .where((s) => s.isNotEmpty);
        if (targets.isNotEmpty &&
            !targets.contains((u['division'] ?? '') as String)) {
          throw const _Http(403, 'Anda tidak berhak membuka file ini.');
        }
        return json({
          'url': s3.presignGet(key, filename: (m['name'] ?? 'lampiran').toString())
        });
      }
      if (key.startsWith('leave/')) {
        final row = await db.pool.runTx((tx) => tx.execute(Sql.named('''
          SELECT l.attachment_name, l.user_id, u.username, u.role AS urel
          FROM leave_requests l JOIN users u ON u.id=l.user_id
          WHERE l.attachment_key=@k LIMIT 1
        '''), parameters: {'k': key}));
        if (row.isEmpty) return json({'message': 'File tidak ditemukan.'}, status: 404);
        final m = row.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        final owner = m['username'] as String;
        final allowed = owner == u['username'] ||
            ((u['role'] == 'manager' || u['role'] == 'superadmin') &&
                canManageRole(u['role'] as String, (m['urel'] ?? 'staff') as String));
        if (!allowed) throw const _Http(403, 'Anda tidak berhak membuka file ini.');
        return json({
          'url': s3.presignGet(key, filename: (m['attachment_name'] ?? 'dokumen').toString())
        });
      }
      return json({'message': 'File tidak ditemukan.'}, status: 404);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  // ---------- profil ----------
  Map<String, dynamic> profileJson(Map<String, dynamic> a, String? managerName) => {
        'username': a['username'],
        'fullName': a['full_name'],
        'role': a['role'],
        'employeeId': a['employee_id'],
        'position': a['position'],
        'division': a['division'],
        'employmentStatus': a['employment_status'],
        'contractMonths': a['contract_months'],
        'joinDate': (a['join_date'] as DateTime).toIso8601String().substring(0, 10),
        'email': a['email'],
        'phone': a['phone'],
        'nikMasked': _maskNik((a['nik'] ?? '') as String),
        'managerName': managerName,
        'gender': a['gender'],
        'birthPlace': a['birth_place'],
        'birthDate': (a['birth_date'] as DateTime?)?.toIso8601String().substring(0, 10),
        'address': a['address'],
        'emergencyContact': a['emergency_name'] == null
            ? null
            : {
                'name': a['emergency_name'],
                'relation': a['emergency_relation'],
                'phone': a['emergency_phone'],
              },
        'hasPhoto': a['photo_key'] != null,
      };

  Future<Map<String, dynamic>> accountOf(TxSession tx, String userId) async {
    final rs = await tx.execute(
        Sql.named('SELECT * FROM users WHERE id=@i::uuid'),
        parameters: {'i': userId});
    return rs.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
  }

  r.get('/profile', (Request req) async {
    try {
      final u = await me(req);
      final row = await db.pool
          .runTx((tx) => accountOf(tx, (u['id'] as Object).toString()));
      String? mgr;
      if (row['manager_username'] != null) {
        final m = await db.pool.runTx((tx) => tx.execute(Sql.named(
              'SELECT full_name FROM users WHERE username=@u',
            ), parameters: {'u': row['manager_username']}));
        if (m.isNotEmpty) mgr = m.first.toColumnMap()['full_name'] as String?;
      }
      return json(profileJson(row, mgr));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/profile/photo', (Request req) async {
    try {
      final u = await me(req);
      final s3 = storeOf(cfg);
      if (s3 == null) throw const _Http(503, 'Penyimpanan file belum dikonfigurasi.');
      final row = await db.pool
          .runTx((tx) => accountOf(tx, (u['id'] as Object).toString()));
      final key = row['photo_key'] as String?;
      if (key == null) return json({'message': 'Belum ada foto.'}, status: 404);
      // bytes langsung (http client mengikuti; presigned tanpa auth ok)
      return json({
        'url': cfg.s3avatarPublic ? s3.publicUrl(key) : s3.presignGet(key),
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.put('/profile/photo', (Request req) async {
    try {
      final u = await me(req);
      final s3 = storeOf(cfg);
      if (s3 == null) throw const _Http(503, 'Penyimpanan file belum dikonfigurasi.');
      final b = await readJson(req);
      final key = ((b['key'] ?? '') as String).trim();
      final uname = (u['username'] as String).toLowerCase();
      if (!key.startsWith('avatars/$uname/')) {
        throw const _Http(422, 'Key foto tidak valid.');
      }
      final ext = key.split('.').last.toLowerCase();
      if (!avatarExts.contains(ext)) {
        throw const _Http(422, 'Foto harus PNG atau JPG.');
      }
      if (!await s3.exists(key)) {
        throw const _Http(422, 'Upload foto tidak ditemukan. Unggah ulang.');
      }
      final old = await db.pool.runTx((tx) async {
        final cur = await accountOf(tx, (u['id'] as Object).toString());
        final prev = cur['photo_key'] as String?;
        await tx.execute(Sql.named('UPDATE users SET photo_key=@k, updated_at=now() WHERE id=@i::uuid'),
            parameters: {'k': key, 'i': (u['id'] as Object).toString()});
        return prev;
      });
      if (old != null && old != key) await s3.delete(old);
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.delete('/profile/photo', (Request req) async {
    try {
      final u = await me(req);
      final s3 = storeOf(cfg);
      final old = await db.pool.runTx((tx) async {
        final cur = await accountOf(tx, (u['id'] as Object).toString());
        final prev = cur['photo_key'] as String?;
        await tx.execute(Sql.named(
            'UPDATE users SET photo_key=NULL, updated_at=now() WHERE id=@i::uuid'),
            parameters: {'i': (u['id'] as Object).toString()});
        return prev;
      });
      if (old != null && s3 != null) await s3.delete(old);
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/profile/change-password', (Request req) async {
    try {
      final u = await me(req);
      final b = await readJson(req);
      final cur = ((b['currentPassword'] ?? '') as String);
      final next = ((b['newPassword'] ?? '') as String);
      await db.pool.runTx((tx) async {
        final acc = await accountOf(tx, (u['id'] as Object).toString());
        if (!BCrypt.checkpw(cur, acc['password_hash'] as String)) {
          throw const _Http(401, 'Password lama salah.');
        }
        if (!passwordOk(next, acc['username'] as String)) {
          throw const _Http(422, 'Password masih lemah. Penuhi semua ketentuan wajib.');
        }
        if (BCrypt.checkpw(next, acc['password_hash'] as String)) {
          throw const _Http(422, 'Password baru tidak boleh sama dengan password lama.');
        }
        await tx.execute(Sql.named(
            'UPDATE users SET password_hash=@p, updated_at=now() WHERE id=@i::uuid'),
            parameters: {
              'p': BCrypt.hashpw(next, BCrypt.gensalt()),
              'i': (u['id'] as Object).toString(),
            });
      });
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.put('/profile/contact', (Request req) async {
    try {
      final u = await me(req);
      final b = await readJson(req);
      final phone = ((b['phone'] ?? '') as String).trim();
      final address = ((b['address'] ?? '') as String).trim();
      final en = ((b['emergencyName'] ?? '') as String).trim();
      final er = ((b['emergencyRelation'] ?? '') as String).trim();
      final ep = ((b['emergencyPhone'] ?? '') as String).trim();
      final err = validatePhone(phone) ??
          (address.length < 10 ? 'Tulis alamat lengkap: jalan, RT/RW, kelurahan, kota' : null) ??
          (en.length < 2 ? 'Nama kontak darurat minimal 2 karakter.' : null) ??
          validatePhone(ep);
      if (err != null) return json({'message': err}, status: 422);
      if (canonicalPhone(ep) == canonicalPhone(phone)) {
        return json(
            {'message': 'Gunakan nomor orang lain, bukan nomor HP Anda sendiri.'},
            status: 422);
      }
      final row = await db.pool.runTx((tx) async {
        await tx.execute(Sql.named('''
          UPDATE users SET phone=@p, address=@a, emergency_name=@en,
            emergency_relation=@er, emergency_phone=@ep, updated_at=now()
          WHERE id=@i::uuid
        '''), parameters: {
          'p': phone,
          'a': address,
          'en': en,
          'er': er.isEmpty ? null : er,
          'ep': ep,
          'i': (u['id'] as Object).toString(),
        });
        return accountOf(tx, (u['id'] as Object).toString());
      });
      String? mgrName;
      if (row['manager_username'] != null) {
        final m = await db.pool.runTx((tx) => tx.execute(Sql.named(
              'SELECT full_name FROM users WHERE username=@u',
            ), parameters: {'u': row['manager_username']}));
        if (m.isNotEmpty) mgrName = m.first.toColumnMap()['full_name'] as String?;
      }
      return json(profileJson(row, mgrName));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  return r;
}
