import 'dart:convert';
import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'db.dart';
import 'notify.dart';
import 'tokens.dart';
import 'validate.dart';

const _maxAttempts = 5;
const _sessionTtl = Duration(days: 30);

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

String lockoutMsg(DateTime until) {
  final mins =
      ((until.difference(DateTime.now().toUtc()).inSeconds + 59) ~/ 60).clamp(1, 1 << 30);
  return 'Terlalu banyak percobaan yang gagal. Silakan mencoba lagi dalam $mins menit.';
}

Map<String, dynamic> userJson(Map<String, dynamic> r) => {
      'username': r['username'],
      'fullName': r['full_name'],
      'role': r['role'],
    };

Future<bool> registrationOpen(TxSession tx) async {
  final rs = await tx.execute(
    Sql.named('SELECT value FROM settings WHERE key = \'registration_open\''),
  );
  if (rs.isEmpty) return true;
  return (rs.first.toColumnMap()['value'] as String).toLowerCase() == 'true';
}

Router authRouter(Db db, Config cfg) {
  final r = Router();

  r.get('/health', (Request req) => json({'ok': true}));

  r.get('/auth/registration-open', (Request req) async {
    final open = await db.pool.runTx((tx) => registrationOpen(tx));
    return json({'open': open});
  });

  r.post('/auth/check-username', (Request req) async {
    final body = await readJson(req);
    final name = ((body['username'] ?? '') as String).trim().toLowerCase();
    final err = validateUsername(name);
    if (err != null) return json({'message': err, 'field': 'username'}, status: 422);
    final count = await db.pool.runTx((tx) async {
      final rs = await tx.execute(
        Sql.named('SELECT 1 FROM users WHERE username = @u'),
        parameters: {'u': name},
      );
      return rs.length;
    });
    if (count > 0) return json({'message': 'Username "$name" sudah dipakai.', 'field': 'username'}, status: 409);
    return json({'available': true});
  });

  Future<Response> doRegister(Db db, Config cfg, Request req) async {
  final b = await readJson(req);
  String s(String k) => ((b[k] ?? '') as Object).toString();
  final name = s('username').trim().toLowerCase();

    String? fail(String? e, String field) =>
        e == null ? null : '$field:$e';

    var e = validateUsername(name) ?? validateFullName(s('fullName')) ?? validateNik(s('nik'));
    if (e != null) return json({'message': e}, status: 422);
    e = validateEmail(s('email')) ?? validatePhone(s('phone'));
    if (e != null) return json({'message': e}, status: 422);
    if (!passwordOk(s('password'), name)) {
      return json({'message': 'Password masih lemah. Penuhi semua ketentuan wajib.', 'field': 'password'}, status: 422);
    }
    if (fail(null, '') != null) return json({'message': 'bad'}, status: 422);
    if ((s('privacyConsent').toLowerCase() != 'true') && b['privacyConsent'] != true) {
      return json({'message': 'Centang persetujuan pemrosesan data pribadi untuk melanjutkan pendaftaran.'}, status: 422);
    }
    if (!divisions.contains(s('division'))) {
      return json({'message': 'Divisi tidak dikenal.'}, status: 422);
    }
    if (!employmentStatuses.contains(s('employmentStatus'))) {
      return json({'message': 'Status kepegawaian tidak dikenal.'}, status: 422);
    }

    try {
      final out = await db.pool.runTx((tx) async {
        final n = await tx.execute(Sql.named('SELECT COUNT(*) AS c FROM users'));
        final total = (n.first.toColumnMap()['c'] as Object).toString();
        final isFirst = int.parse(total) == 0;
        if (!isFirst && !(await registrationOpen(tx))) {
          throw const _Http(403, 'Pendaftaran akun sedang ditutup. Hubungi Tim HR bila Anda belum memiliki akun.');
        }
        // unik: username, nik, email
        final dupe = await tx.execute(Sql.named(
          'SELECT username, nik, email FROM users WHERE username=@u OR nik=@n OR email=@e LIMIT 1',
        ), parameters: {'u': name, 'n': s('nik').trim(), 'e': s('email').trim().toLowerCase()});
        if (dupe.isNotEmpty) {
          final m = dupe.first.toColumnMap();
          if ((m['username'] as String).toLowerCase() == name) {
            throw _Http(409, 'Username "$name" sudah dipakai. Pilih username lain.');
          }
          if (m['nik'] == s('nik').trim()) {
            throw const _Http(409, 'NIK ini sudah terdaftar. Bila Anda sudah punya akun, gunakan "Lupa password" di halaman masuk atau hubungi Tim HR.');
          }
          throw const _Http(409, 'Email ini sudah dipakai akun lain. Gunakan email lain.');
        }
        final role = isFirst ? 'superadmin' : 'staff';
        final empId = 'PG-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
        final hash = BCrypt.hashpw(s('password'), BCrypt.gensalt());
        final now = DateTime.now().toUtc();
        final ins = await tx.execute(Sql.named('''
          INSERT INTO users(username, full_name, role, nik, employee_id, position,
            division, employment_status, contract_months, join_date, email, phone,
            password_hash, gender, birth_place, birth_date, address,
            emergency_name, emergency_relation, emergency_phone, privacy_consented_at)
          VALUES(@u,@fn,@role,@nik,@eid,'Staf',@div,@es,@cm,@jd,@em,@ph,
            @pw,@g,@bp,@bd,@ad,@en,@er,@ep,@pc)
          RETURNING id, username, full_name, role
        '''), parameters: {
          'u': name,
          'fn': s('fullName').trim(),
          'role': role,
          'nik': s('nik').trim(),
          'eid': empId,
          'div': s('division'),
          'es': s('employmentStatus'),
          'cm': int.tryParse(s('contractMonths')),
          'jd': DateTime.now().toUtc().toIso8601String().substring(0, 10),
          'em': s('email').trim().toLowerCase(),
          'ph': s('phone').trim(),
          'pw': hash,
          'g': s('gender').isEmpty ? null : s('gender'),
          'bp': s('birthPlace').isEmpty ? null : s('birthPlace').trim(),
          'bd': s('birthDate').isEmpty ? null : s('birthDate').substring(0, 10),
          'ad': s('address').isEmpty ? null : s('address').trim(),
          'en': s('emergencyName').isEmpty ? null : s('emergencyName').trim(),
          'er': s('emergencyRelation').isEmpty ? null : s('emergencyRelation'),
          'ep': s('emergencyPhone').isEmpty ? null : s('emergencyPhone').trim(),
          'pc': now.toIso8601String(),
        });
        final row = ins.first.toColumnMap();
        // token langsung agar pendaftar pertama bisa masuk tanpa login ulang
        final jti = newJti();
        await tx.execute(Sql.named(
          'INSERT INTO sessions(jti, user_id, expires_at) VALUES(@j::uuid, @u::uuid, @e)',
        ), parameters: {'j': jti, 'u': (row['id'] as Object).toString(), 'e': now.add(_sessionTtl).toIso8601String()});
        final token = issueJwt(secret: cfg.jwtSecret, userId: (row['id'] as Object).toString(),
            username: row['username'] as String, role: row['role'] as String, jti: jti);
        // kabari pengelola (kecuali pendaftar pertama yg belum ada siapa2)
        if (!isFirst) {
          for (final rev in await reviewersFor(
              tx, row['username'] as String, row['role'] as String)) {
            await notifyTx(tx, rev['username'] as String,
                kind: 'accountRegistered',
                title: 'Akun karyawan baru',
                body: '${row['full_name']} mendaftar sebagai Staff.');
          }
        }
        return {'token': token, 'user': {'username': row['username'], 'fullName': row['full_name'], 'role': row['role']}};
      });
      return json(out, status: 201);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  }

  // ---- register: pendaftar pertama jadi superadmin otomatis ----
  r.post('/auth/register', (Request req) async {
    try {
      return await doRegister(db, cfg, req);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    } catch (e, st) {
      // Perangkap 500 misterius: catat detail ke log server (dashboard),
      // klien terima JSON generik agar bisa ditampilkan.
      stderr.writeln('REGISTER FAIL: $e\n$st');
      return json(
          {'message': 'Pendaftaran gagal diproses di server. Coba lagi.'},
          status: 500);
    }
  });

  // ---- login (5x gagal -> kunci 15 mnt) ----
  r.post('/auth/login', (Request req) async {
    final b = await readJson(req);
    final name = ((b['username'] ?? '') as String).trim().toLowerCase();
    final pw = ((b['password'] ?? '') as String);
    try {
      final out = await db.pool.runTx((tx) async {
        final att = await tx.execute(Sql.named(
          'SELECT failures, locked_until FROM login_attempts WHERE username=@u',
        ), parameters: {'u': name});
        if (att.isNotEmpty) {
          final m = att.first.toColumnMap();
          final locked = m['locked_until'] as DateTime?;
          if (locked != null && DateTime.now().toUtc().isBefore(locked.toUtc())) {
            throw _Http(429, lockoutMsg(locked));
          }
        }
        Future<void> fail(String msg) async {
          await tx.execute(Sql.named('''
            INSERT INTO login_attempts(username, failures, locked_until, updated_at)
            VALUES(@u,1,NULL,now())
            ON CONFLICT (username) DO UPDATE SET
              failures = login_attempts.failures + 1,
              locked_until = CASE WHEN login_attempts.failures + 1 >= @m
                THEN now() + make_interval(mins => 15) ELSE NULL END,
              updated_at = now()
          '''), parameters: {'u': name, 'm': _maxAttempts});
          final cur = await tx.execute(Sql.named(
            'SELECT locked_until FROM login_attempts WHERE username=@u',
          ), parameters: {'u': name});
          final locked = cur.first.toColumnMap()['locked_until'] as DateTime?;
          if (locked != null) throw _Http(429, lockoutMsg(locked));
          throw _Http(401, msg);
        }

        final rs = await tx.execute(Sql.named(
          'SELECT * FROM users WHERE username=@u',
        ), parameters: {'u': name});
        if (rs.isEmpty) {
          await fail('Username tidak ditemukan. Pastikan penulisan sudah benar, atau daftar akun bila Anda belum memilikinya.');
        }
        final m = rs.first.toColumnMap();
        if (!BCrypt.checkpw(pw, m['password_hash'] as String)) {
          await fail('Password salah. Silakan coba lagi atau gunakan "Lupa password?" untuk mengatur ulang.');
        }
        if (m['active'] != true) {
          throw const _Http(403, 'Akun Anda sudah dinonaktifkan. Hubungi Tim HR bila ini keliru.');
        }
        await tx.execute(Sql.named('DELETE FROM login_attempts WHERE username=@u'),
            parameters: {'u': name});
        final jti = newJti();
        final now = DateTime.now().toUtc();
        await tx.execute(Sql.named(
          'INSERT INTO sessions(jti, user_id, expires_at) VALUES(@j::uuid, @u::uuid, @e)',
        ), parameters: {'j': jti, 'u': (m['id'] as Object).toString(), 'e': now.add(_sessionTtl).toIso8601String()});
        final token = issueJwt(secret: cfg.jwtSecret, userId: (m['id'] as Object).toString(),
            username: m['username'] as String, role: m['role'] as String, jti: jti);
        return {'token': token, 'user': userJson(m.map((k, v) => MapEntry(k.toString(), v)))};
      });
      return json(out);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  Future<Map<String, dynamic>?> authed(Request req) async {
    final h = req.headers['authorization'] ?? '';
    if (!h.toLowerCase().startsWith('bearer ')) return null;
    final jwt = verifyJwt(h.substring(7).trim(), cfg.jwtSecret);
    if (jwt == null) return null;
    final jti = jwt.jwtId;
    final sub = jwt.subject;
    if (jti == null || sub == null) return null;
    final row = await db.pool.runTx((tx) async {
      final s = await tx.execute(Sql.named(
        'SELECT revoked_at, expires_at FROM sessions WHERE jti=@j::uuid',
      ), parameters: {'j': jti});
      if (s.isEmpty) return null;
      final m = s.first.toColumnMap();
      if (m['revoked_at'] != null) return null;
      if (DateTime.now().toUtc().isAfter((m['expires_at'] as DateTime).toUtc())) return null;
      final u = await tx.execute(Sql.named('SELECT * FROM users WHERE id=@i::uuid'),
          parameters: {'i': sub});
      if (u.isEmpty) return null;
      final um = u.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
      if (um['active'] != true) return null;
      return {'jti': jti, ...um};
    });
    return row;
  }

  r.get('/auth/me', (Request req) async {
    final u = await authed(req);
    if (u == null) return json({'message': 'Sesi berakhir. Silakan masuk kembali.'}, status: 401);
    return json({'user': {'username': u['username'], 'fullName': u['full_name'], 'role': u['role']}});
  });

  r.post('/auth/logout', (Request req) async {
    final u = await authed(req);
    if (u != null) {
      await db.pool.runTx((tx) => tx.execute(
        Sql.named('UPDATE sessions SET revoked_at=now() WHERE jti=@j::uuid'),
        parameters: {'j': u['jti']},
      ));
    }
    return json({'ok': true});
  });

  r.post('/auth/logout-others', (Request req) async {
    final u = await authed(req);
    if (u == null) return json({'message': 'Sesi berakhir. Silakan masuk kembali.'}, status: 401);
    await db.pool.runTx((tx) => tx.execute(Sql.named(
      'UPDATE sessions SET revoked_at=now() WHERE user_id=@i::uuid AND jti<>@j::uuid AND revoked_at IS NULL',
    ), parameters: {'i': (u['id'] as Object).toString(), 'j': u['jti']}));
    return json({'ok': true});
  });

  // ---- lupa password: verify-username / verify-nik / reset ----
  r.post('/auth/recovery/verify-username', (Request req) async {
    final b = await readJson(req);
    final name = ((b['username'] ?? '') as String).trim().toLowerCase();
    final n = await db.pool.runTx((tx) async {
      final rs = await tx.execute(Sql.named(
        'SELECT active FROM users WHERE username=@u',
      ), parameters: {'u': name});
      return rs.isEmpty ? null : rs.first.toColumnMap();
    });
    if (n == null) return json({'message': 'Username tidak ditemukan.'}, status: 404);
    if (n['active'] != true) return json({'message': 'Akun ini sudah dinonaktifkan. Hubungi Tim HR.'}, status: 403);
    return json({'ok': true});
  });

  r.post('/auth/recovery/verify-nik', (Request req) async {
    final b = await readJson(req);
    final name = ((b['username'] ?? '') as String).trim().toLowerCase();
    final nik = ((b['nik'] ?? '') as String).trim();
    final uid = await db.pool.runTx((tx) async {
      final rs = await tx.execute(Sql.named(
        'SELECT id, nik FROM users WHERE username=@u',
      ), parameters: {'u': name});
      if (rs.isEmpty) return null;
      final m = rs.first.toColumnMap();
      if (m['nik'] != nik) return 'mismatch';
      final token = newJti().replaceAll('-', '');
      await tx.execute(Sql.named('''
        INSERT INTO password_resets(token_hash, user_id, expires_at)
        VALUES(@t, @u::uuid, now() + make_interval(mins => 30))
      '''), parameters: {'t': sha256Hex(token), 'u': (m['id'] as Object).toString()});
      return token;
    });
    if (uid == null) return json({'message': 'Sesi verifikasi tidak valid.'}, status: 400);
    if (uid == 'mismatch') {
      return json({'message': 'NIK tidak sesuai dengan data karyawan untuk username ini.'}, status: 400);
    }
    return json({'resetToken': uid});
  });

  r.post('/auth/recovery/reset', (Request req) async {
    final b = await readJson(req);
    final token = ((b['resetToken'] ?? '') as String);
    final pw = ((b['newPassword'] ?? '') as String);
    try {
      await db.pool.runTx((tx) async {
        final rs = await tx.execute(Sql.named(
          'SELECT user_id, expires_at, used_at FROM password_resets WHERE token_hash=@t',
        ), parameters: {'t': sha256Hex(token)});
        if (rs.isEmpty) throw const _Http(400, 'Sesi atur ulang password sudah berakhir. Silakan ulangi dari awal.');
        final m = rs.first.toColumnMap();
        if (m['used_at'] != null ||
            DateTime.now().toUtc().isAfter((m['expires_at'] as DateTime).toUtc())) {
          throw const _Http(400, 'Sesi atur ulang password sudah berakhir. Silakan ulangi dari awal.');
        }
        final u = await tx.execute(Sql.named('SELECT username FROM users WHERE id=@i::uuid'),
            parameters: {'i': (m['user_id'] as Object).toString()});
        final uname = (u.first.toColumnMap()['username'] as String);
        if (!passwordOk(pw, uname)) {
          throw const _Http(422, 'Password terlalu lemah. Buat password yang lebih kuat.');
        }
        await tx.execute(Sql.named('UPDATE users SET password_hash=@p, updated_at=now() WHERE id=@i::uuid'),
            parameters: {'p': BCrypt.hashpw(pw, BCrypt.gensalt()), 'i': (m['user_id'] as Object).toString()});
        await tx.execute(Sql.named('UPDATE password_resets SET used_at=now() WHERE token_hash=@t'),
            parameters: {'t': sha256Hex(token)});
        await tx.execute(Sql.named('UPDATE sessions SET revoked_at=now() WHERE user_id=@i::uuid AND revoked_at IS NULL'),
            parameters: {'i': (m['user_id'] as Object).toString()});
      });
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  return r;
}

class _Http implements Exception {
  const _Http(this.status, this.message);
  final int status;
  final String message;
}
