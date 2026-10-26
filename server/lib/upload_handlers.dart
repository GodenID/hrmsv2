import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'authz.dart';
import 'config.dart';
import 'dates.dart';
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
      if (purpose != 'leave' &&
          purpose != 'avatar' &&
          purpose != 'announcement' &&
          purpose != 'apk') {
        throw const _Http(422, 'Tujuan upload tidak dikenal.');
      }
      if (purpose == 'apk' && u['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Super Admin yang dapat mengunggah APK.');
      }
      final ext = filename.split('.').last.toLowerCase();
      const apkExts = {'apk'};
      final maxBytes = switch (purpose) {
        'announcement' => 5 * 1024 * 1024,
        'apk' => 300 * 1024 * 1024,
        _ => maxFileBytes,
      };
      final allowed = switch (purpose) {
        'avatar' => avatarExts,
        'apk' => apkExts,
        _ => leaveExts,
      };
      if (!allowed.contains(ext)) {
        throw _Http(422, switch (purpose) {
          'avatar' => 'Foto harus PNG atau JPG.',
          'apk' => 'Berkas rilis harus .apk.',
          _ => 'Lampiran harus PDF / JPG / PNG.',
        });
      }
      if (size <= 0 || size > maxBytes) {
        throw _Http(422, switch (purpose) {
          'announcement' => 'Ukuran file maksimal 5 MB.',
          'apk' => 'Ukuran APK maksimal 300 MB.',
          _ => 'Ukuran file maksimal 2 MB.',
        });
      }
      final uname = (u['username'] as String).toLowerCase();
      final token = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      final key = switch (purpose) {
        'leave' => 'leave/$uname/$token.$ext',
        'avatar' => 'avatars/$uname/$token.$ext',
        'apk' => 'releases/$token.apk',
        _ => 'announcements/$uname/$token.$ext',
      };
      // APK besar butuh waktu unggah lebih lama dari lampiran biasa.
      final putUrl = s3.presignPut(
        key,
        expiresSeconds: purpose == 'apk' ? 3600 : 900,
      );
      return json({
        'key': key,
        'putUrl': putUrl,
        'publicUrl': purpose == 'avatar' && cfg.s3avatarPublic ? s3.publicUrl(key) : null,
        'expiresIn': purpose == 'apk' ? 3600 : 900,
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
  Map<String, dynamic> profileJson(Map<String, dynamic> a) => {
        'username': a['username'],
        'fullName': a['full_name'],
        'role': a['role'],
        'employeeId': a['employee_id'],
        'position': a['position'],
        'division': a['division'],
        'divisionLabel': (a['division_label'] ?? a['division'])?.toString(),
        'employmentStatus': a['employment_status'],
        'contractMonths': a['contract_months'],
        'joinDate': (a['join_date'] as DateTime).toIso8601String().substring(0, 10),
        'email': a['email'],
        'phone': a['phone'],
        'nikMasked': _maskNik((a['nik'] ?? '') as String),
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
        Sql.named('''
          SELECT u.*, d.label AS division_label
          FROM users u LEFT JOIN divisions d ON d.code=u.division
          WHERE u.id=@i::uuid
        '''),
        parameters: {'i': userId});
    return rs.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
  }

  r.get('/profile', (Request req) async {
    try {
      final u = await me(req);
      final row = await db.pool
          .runTx((tx) => accountOf(tx, (u['id'] as Object).toString()));
      return json(profileJson(row));
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
            'UPDATE users SET password_hash=@p, must_change_password=FALSE, updated_at=now() WHERE id=@i::uuid'),
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

  // ---------- lengkapi profil (login pertama akun bulk) ----------
  r.put('/profile/complete', (Request req) async {
    try {
      final u = await me(req);
      final b = await readJson(req);
      String s(String k) => ((b[k] ?? '') as Object).toString();
      final fullName = s('fullName').trim();
      final nik = s('nik').trim();
      final birthPlace = s('birthPlace').trim();
      final birthDate = s('birthDate').isEmpty
          ? null
          : dateOnly(
              DateTime.tryParse(s('birthDate')) ?? DateTime(1970));
      final gender = s('gender');
      final address = s('address').trim();
      final email = s('email').trim().toLowerCase();
      final phone = s('phone').trim();
      final en = s('emergencyName').trim();
      final er = s('emergencyRelation').trim();
      final ep = s('emergencyPhone').trim();
      final err = validateFullName(fullName) ??
          validateNik(nik) ??
          (birthPlace.length < 2 ? 'Tempat lahir minimal 2 karakter.' : null) ??
          (birthDate == null ? 'Tanggal lahir tidak valid.' : null) ??
          (!genders.contains(gender) ? 'Jenis kelamin tidak dikenal.' : null) ??
          (address.length < 10
              ? 'Tulis alamat lengkap: jalan, RT/RW, kelurahan, kota'
              : null) ??
          validateEmail(email) ??
          validatePhone(phone) ??
          (en.length < 2 ? 'Nama kontak darurat minimal 2 karakter.' : null) ??
          validatePhone(ep);
      if (err != null) return json({'message': err}, status: 422);
      if (canonicalPhone(ep) == canonicalPhone(phone)) {
        return json(
            {'message': 'Gunakan nomor orang lain, bukan nomor HP Anda sendiri.'},
            status: 422);
      }
      // usia kerja minimum 17 tahun
      final today = dateOnly(DateTime.now().toUtc().add(const Duration(hours: 7)));
      var age = today.year - birthDate!.year;
      if (today.month < birthDate.month ||
          (today.month == birthDate.month && today.day < birthDate.day)) {
        age--;
      }
      if (age < 17) {
        return json({'message': 'Usia minimal 17 tahun.'}, status: 422);
      }
      await db.pool.runTx((tx) async {
        for (final c in [
          ['nik', nik, 'NIK ini sudah terdaftar.'],
          ['email', email, 'Email ini sudah dipakai akun lain.'],
        ]) {
          final dup = await tx.execute(Sql.named(
            'SELECT 1 FROM users WHERE ${c[0]}=@v AND id<>@i::uuid LIMIT 1',
          ), parameters: {
            'v': c[1],
            'i': (u['id'] as Object).toString(),
          });
          if (dup.isNotEmpty) throw _Http(409, c[2]);
        }
        final phones = await tx.execute(Sql.named(
          'SELECT phone FROM users WHERE id<>@i::uuid',
        ), parameters: {
          'i': (u['id'] as Object).toString(),
        });
        final canon = canonicalPhone(phone);
        for (final row in phones) {
          if (canonicalPhone((row.toColumnMap()['phone'] ?? '').toString()) == canon) {
            throw const _Http(409, 'Nomor HP ini sudah dipakai akun lain.');
          }
        }
        await tx.execute(Sql.named('''
          UPDATE users SET full_name=@fn, nik=@nik, birth_place=@bp,
            birth_date=@bd, gender=@g, address=@ad, email=@em, phone=@ph,
            emergency_name=@en, emergency_relation=@er, emergency_phone=@ep,
            profile_complete=TRUE, updated_at=now()
          WHERE id=@i::uuid
        '''), parameters: {
          'fn': fullName,
          'nik': nik,
          'bp': birthPlace,
          'bd': birthDate.toIso8601String().substring(0, 10),
          'g': gender,
          'ad': address,
          'em': email,
          'ph': phone,
          'en': en,
          'er': er.isEmpty ? null : er,
          'ep': ep,
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
      return json(profileJson(row));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  return r;
}
