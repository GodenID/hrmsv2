import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'authz.dart';
import 'config.dart';
import 'db.dart';
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

/// Password sementara: 10 char [A-Z a-z 2-9] + strip, lolos aturan server.
String tempPassword() {
  final r = Random.secure();
  const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  const lower = 'abcdefghijkmnpqrstuvwxyz';
  const digits = '23456789';
  const all = '$upper$lower$digits';
  String pick(String s) => s[r.nextInt(s.length)];
  final chars = [pick(upper), pick(lower), pick(digits), for (var i = 0; i < 7; i++) pick(all)]
    ..shuffle(r);
  return '${chars.sublist(0, 5).join()}-${chars.sublist(5).join()}';
}

Map<String, dynamic> toAccount(Map<String, dynamic> a, Map<String, dynamic> actor) {
  final canEdit = canManageRole(actor['role'] as String, a['role'] as String);
  final canActOn = actor['username'] != a['username'] &&
      canManageRole(actor['role'] as String, a['role'] as String);
  return {
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
    'nikMasked': maskNik((a['nik'] ?? '') as String),
    'nik': canEdit ? a['nik'] : null,
    'managerUsername': a['manager_username'],
    'active': a['active'],
    'gender': a['gender'],
    'birthPlace': canEdit ? a['birth_place'] : null,
    'birthDate': canEdit && a['birth_date'] != null
        ? (a['birth_date'] as DateTime).toIso8601String().substring(0, 10)
        : null,
    'address': canEdit ? a['address'] : null,
    'emergencyContact': canEdit && a['emergency_name'] != null
        ? {
            'name': a['emergency_name'],
            'relation': a['emergency_relation'],
            'phone': a['emergency_phone'],
          }
        : null,
    'canEdit': canEdit,
    'canChangeRole': canEdit && a['username'] != actor['username'],
    'canChangeStatus': canActOn,
    'canResetPassword': canActOn && a['active'] == true,
  };
}

String? validateDraft(Map<String, dynamic> b) {
  String s(String k) => ((b[k] ?? '') as Object).toString();
  return validateFullName(s('fullName')) ??
      validateNik(s('nik')) ??
      (s('employeeId').trim().isEmpty ? 'ID karyawan wajib diisi' : null) ??
      (s('position').trim().length < 2 ? 'Jabatan wajib diisi' : null) ??
      (!divisions.contains(s('division')) ? 'Divisi tidak dikenal.' : null) ??
      (!employmentStatuses.contains(s('employmentStatus')) ? 'Status kepegawaian tidak dikenal.' : null) ??
      validateEmail(s('email')) ??
      validatePhone(s('phone'));
}

Router employeeRouter(Db db, Config cfg) {
  final r = Router();

  Future<Map<String, dynamic>> requireManager(Request req) async {
    final u = await authedUser(req, db, cfg);
    if (u == null) throw const _Http(401, 'Sesi berakhir. Silakan masuk kembali.');
    if (!canManageEmployees(u['role'] as String)) {
      throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat mengelola karyawan.');
    }
    return u;
  }

  r.get('/employees', (Request req) async {
    try {
      final actor = await requireManager(req);
      final rows = await db.pool.runTx((tx) => tx.execute(
            Sql.named('SELECT * FROM users ORDER BY full_name'),
          ));
      final list = [
        for (final row in rows)
          toAccount(row.toColumnMap().map((k, v) => MapEntry(k.toString(), v)), actor),
      ];
      return json({'employees': list});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/employees/<username>', (Request req, String username) async {
    try {
      final actor = await requireManager(req);
      final rows = await db.pool.runTx((tx) => tx.execute(
            Sql.named('SELECT * FROM users WHERE username=@u'),
            parameters: {'u': username.trim().toLowerCase()},
          ));
      if (rows.isEmpty) return json({'message': 'Karyawan tidak ditemukan.'}, status: 404);
      return json(toAccount(
          rows.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v)), actor));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/employees', (Request req) async {
    try {
      final actor = await requireManager(req);
      final b = await readJson(req);
      final name = ((b['username'] ?? '') as String).trim().toLowerCase();
      final uErr = validateUsername(name);
      if (uErr != null) return json({'message': uErr}, status: 422);
      final dErr = validateDraft(b);
      if (dErr != null) return json({'message': dErr}, status: 422);
      final role = ((b['role'] ?? 'staff') as String);
      if (!canManageRole(actor['role'] as String, role)) {
        return json({'message': 'Anda tidak berhak memberikan role $role.'}, status: 403);
      }
      final password = tempPassword();
      final created = await db.pool.runTx((tx) async {
        final exists = await tx.execute(
          Sql.named('SELECT 1 FROM users WHERE username=@u'),
          parameters: {'u': name},
        );
        if (exists.isNotEmpty) {
          throw const _Http(409, 'Username sudah dipakai (termasuk akun nonaktif). Pilih yang lain.');
        }
        String s(String k) => ((b[k] ?? '') as Object).toString();
        final ins = await tx.execute(Sql.named('''
          INSERT INTO users(username, full_name, role, nik, employee_id, position,
            division, employment_status, contract_months, join_date, email, phone,
            password_hash, manager_username, gender, birth_place, birth_date,
            address, emergency_name, emergency_relation, emergency_phone)
          VALUES(@u,@fn,@role,@nik,@eid,@pos,@div,@es,@cm,@jd,@em,@ph,
            @pw,@mgr,@g,@bp,@bd,@ad,@en,@er,@ep)
          RETURNING *
        '''), parameters: {
          'u': name,
          'fn': s('fullName').trim(),
          'role': role,
          'nik': s('nik').trim(),
          'eid': s('employeeId').trim(),
          'pos': s('position').trim(),
          'div': s('division'),
          'es': s('employmentStatus'),
          'cm': b['contractMonths'] is int ? b['contractMonths'] : int.tryParse(s('contractMonths')),
          'jd': s('joinDate').isEmpty
              ? DateTime.now().toUtc().toIso8601String().substring(0, 10)
              : s('joinDate').substring(0, 10),
          'em': s('email').trim().toLowerCase(),
          'ph': s('phone').trim(),
          'pw': BCrypt.hashpw(password, BCrypt.gensalt()),
          'mgr': s('managerUsername').isEmpty ? null : s('managerUsername').trim().toLowerCase(),
          'g': s('gender').isEmpty ? null : s('gender'),
          'bp': s('birthPlace').isEmpty ? null : s('birthPlace').trim(),
          'bd': s('birthDate').isEmpty ? null : s('birthDate').substring(0, 10),
          'ad': s('address').isEmpty ? null : s('address').trim(),
          'en': s('emergencyName').isEmpty ? null : s('emergencyName').trim(),
          'er': s('emergencyRelation').isEmpty ? null : s('emergencyRelation'),
          'ep': s('emergencyPhone').isEmpty ? null : s('emergencyPhone').trim(),
        });
        return ins.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
      });
      return json(
        {'account': toAccount(created, actor), 'temporaryPassword': password},
        status: 201,
      );
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.put('/employees/<username>', (Request req, String username) async {
    try {
      final actor = await requireManager(req);
      final b = await readJson(req);
      final dErr = validateDraft(b);
      if (dErr != null) return json({'message': dErr}, status: 422);
      final updated = await db.pool.runTx((tx) async {
        final cur = await tx.execute(
          Sql.named('SELECT * FROM users WHERE username=@u'),
          parameters: {'u': username.trim().toLowerCase()},
        );
        if (cur.isEmpty) throw const _Http(404, 'Karyawan tidak ditemukan.');
        final old = cur.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if (!canManageRole(actor['role'] as String, old['role'] as String)) {
          throw _Http(403, '${actor['role']} tidak dapat mengubah data akun ${old['role']}.');
        }
        String s(String k) => ((b[k] ?? '') as Object).toString();
        final role = s('role').isEmpty ? (old['role'] as String) : s('role');
        if (!canManageRole(actor['role'] as String, role)) {
          throw _Http(403, 'Anda tidak berhak memberikan role $role.');
        }
        if ((old['username'] as String) == actor['username'] && role != old['role']) {
          throw const _Http(403, 'Anda tidak dapat mengganti role akun Anda sendiri.');
        }
        final upd = await tx.execute(Sql.named('''
          UPDATE users SET full_name=@fn, role=@role, nik=@nik, employee_id=@eid,
            position=@pos, division=@div, employment_status=@es, contract_months=@cm,
            join_date=@jd, email=@em, phone=@ph, manager_username=@mgr, gender=@g,
            birth_place=@bp, birth_date=@bd, address=@ad, emergency_name=@en,
            emergency_relation=@er, emergency_phone=@ep, updated_at=now()
          WHERE username=@u RETURNING *
        '''), parameters: {
          'u': (old['username'] as String),
          'fn': s('fullName').trim(),
          'role': role,
          'nik': s('nik').trim(),
          'eid': s('employeeId').trim(),
          'pos': s('position').trim(),
          'div': s('division'),
          'es': s('employmentStatus'),
          'cm': b['contractMonths'] is int ? b['contractMonths'] : int.tryParse(s('contractMonths')),
          'jd': s('joinDate').isEmpty
              ? (old['join_date'] as DateTime).toIso8601String().substring(0, 10)
              : s('joinDate').substring(0, 10),
          'em': s('email').trim().toLowerCase(),
          'ph': s('phone').trim(),
          'mgr': s('managerUsername').isEmpty ? null : s('managerUsername').trim().toLowerCase(),
          'g': s('gender').isEmpty ? null : s('gender'),
          'bp': s('birthPlace').isEmpty ? null : s('birthPlace').trim(),
          'bd': s('birthDate').isEmpty ? null : s('birthDate').substring(0, 10),
          'ad': s('address').isEmpty ? null : s('address').trim(),
          'en': s('emergencyName').isEmpty ? null : s('emergencyName').trim(),
          'er': s('emergencyRelation').isEmpty ? null : s('emergencyRelation'),
          'ep': s('emergencyPhone').isEmpty ? null : s('emergencyPhone').trim(),
        });
        return upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
      });
      return json(toAccount(updated, actor));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.patch('/employees/<username>/active', (Request req, String username) async {
    try {
      final actor = await requireManager(req);
      final b = await readJson(req);
      final active = b['active'] == true;
      final updated = await db.pool.runTx((tx) async {
        final cur = await tx.execute(
          Sql.named('SELECT * FROM users WHERE username=@u'),
          parameters: {'u': username.trim().toLowerCase()},
        );
        if (cur.isEmpty) throw const _Http(404, 'Karyawan tidak ditemukan.');
        final old = cur.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if ((old['username'] as String) == actor['username']) {
          throw const _Http(403, 'Anda tidak dapat menonaktifkan akun Anda sendiri.');
        }
        if (!canManageRole(actor['role'] as String, old['role'] as String)) {
          throw _Http(403, '${actor['role']} tidak dapat mengubah status akun ${old['role']}.');
        }
        final upd = await tx.execute(
          Sql.named('UPDATE users SET active=@a, updated_at=now() WHERE username=@u RETURNING *'),
          parameters: {'a': active, 'u': (old['username'] as String)},
        );
        if (!active) {
          await tx.execute(Sql.named(
            'UPDATE sessions SET revoked_at=now() WHERE user_id=@i::uuid AND revoked_at IS NULL',
          ), parameters: {'i': (old['id'] as Object).toString()});
        }
        return upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
      });
      return json(toAccount(updated, actor));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/employees/<username>/reset-password', (Request req, String username) async {
    try {
      final actor = await requireManager(req);
      final password = await db.pool.runTx((tx) async {
        final cur = await tx.execute(
          Sql.named('SELECT * FROM users WHERE username=@u'),
          parameters: {'u': username.trim().toLowerCase()},
        );
        if (cur.isEmpty) throw const _Http(404, 'Karyawan tidak ditemukan.');
        final old = cur.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if ((old['username'] as String) == actor['username']) {
          throw const _Http(403, 'Untuk akun Anda sendiri, gunakan Profil > Ganti password.');
        }
        if (!canManageRole(actor['role'] as String, old['role'] as String)) {
          throw _Http(403, '${actor['role']} tidak dapat mereset password akun ${old['role']}.');
        }
        if (old['active'] != true) {
          throw const _Http(400, 'Akun nonaktif. Aktifkan akun terlebih dahulu.');
        }
        final pw = tempPassword();
        await tx.execute(
          Sql.named('UPDATE users SET password_hash=@p, updated_at=now() WHERE username=@u'),
          parameters: {'p': BCrypt.hashpw(pw, BCrypt.gensalt()), 'u': (old['username'] as String)},
        );
        await tx.execute(Sql.named(
          'UPDATE sessions SET revoked_at=now() WHERE user_id=@i::uuid AND revoked_at IS NULL',
        ), parameters: {'i': (old['id'] as Object).toString()});
        return pw;
      });
      return json({'temporaryPassword': password});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.put('/settings/registration', (Request req) async {
    final u = await authedUser(req, db, cfg);
    if (u == null) return json({'message': 'Sesi berakhir. Silakan masuk kembali.'}, status: 401);
    if (u['role'] != 'superadmin') {
      return json(
          {'message': 'Hanya Super Admin yang dapat membuka atau menutup pendaftaran.'},
          status: 403);
    }
    final b = await readJson(req);
    final open = b['open'] == true;
    await db.pool.runTx((tx) => tx.execute(
          Sql.named(
              'INSERT INTO settings(key,value) VALUES(\'registration_open\',@v) ON CONFLICT (key) DO UPDATE SET value=@v'),
          parameters: {'v': open ? 'true' : 'false'},
        ));
    return json({'open': open});
  });

  return r;
}
