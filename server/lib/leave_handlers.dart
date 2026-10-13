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

// ---------- kalender kerja: lihat dates.dart ----------

const annualQuota = 12;

Future<({int used, int pending})> annualUsage(TxSession tx, String userId) async {
  final rs = await tx.execute(Sql.named('''
    SELECT status, COALESCE(SUM(working_days),0) AS d FROM leave_requests
    WHERE user_id=@i::uuid AND type='annual' AND status IN ('approved','pending')
    GROUP BY status
  '''), parameters: {'i': userId});
  var used = 0, pending = 0;
  for (final row in rs) {
    final m = row.toColumnMap();
    if (m['status'] == 'approved') {
      used = (m['d'] as num).toInt();
    } else {
      pending = (m['d'] as num).toInt();
    }
  }
  return (used: used, pending: pending);
}

Map<String, dynamic> leaveJson(Map<String, dynamic> r) => {
      'id': (r['id'] as Object).toString(),
      'type': r['type'],
      'start': (r['start_date'] as DateTime).toIso8601String().substring(0, 10),
      'end': (r['end_date'] as DateTime).toIso8601String().substring(0, 10),
      'workingDays': r['working_days'],
      'reason': r['reason'],
      'status': r['status'],
      'submittedAt': isoUtc(r['submitted_at'] as DateTime),
      'attachment': r['attachment_name'] == null
          ? null
          : {
              'name': r['attachment_name'],
              'sizeBytes': r['attachment_size'],
              'key': r['attachment_key'],
            },
      'reviewedBy': r['reviewed_by'],
      'reviewedAt': isoUtcOpt(r['reviewed_at'] as DateTime?),
      'reviewerNote': r['reviewer_note'],
    };

Map<String, dynamic> overtimeJson(Map<String, dynamic> r) => {
      'id': (r['id'] as Object).toString(),
      'date': (r['date'] as DateTime).toIso8601String().substring(0, 10),
      'start': isoUtc(r['start_time'] as DateTime),
      'end': isoUtc(r['end_time'] as DateTime),
      'reason': r['reason'],
      'status': r['status'],
      'submittedAt': isoUtc(r['submitted_at'] as DateTime),
      'reviewedBy': r['reviewed_by'],
      'reviewedAt': isoUtcOpt(r['reviewed_at'] as DateTime?),
      'reviewerNote': r['reviewer_note'],
    };

const typeLabels = {
  'annual': 'Cuti tahunan',
  'permission': 'Izin',
  'sick': 'Sakit',
  'maternity': 'Cuti melahirkan',
};

Router leaveRouter(Db db, Config cfg) {
  final r = Router();

  Future<Map<String, dynamic>> me(Request req) async {
    final u = await authedUser(req, db, cfg);
    if (u == null) throw const _Http(401, 'Sesi berakhir. Silakan masuk kembali.');
    return u;
  }

  // ---------- saldo & riwayat ----------
  r.get('/leave/balance', (Request req) async {
    try {
      final u = await me(req);
      final use = await db.pool.runTx(
          (tx) => annualUsage(tx, (u['id'] as Object).toString()));
      final remaining = (annualQuota - use.used).clamp(0, annualQuota);
      final available = (remaining - use.pending).clamp(0, annualQuota);
      return json({
        'year': nowWib().year,
        'quota': annualQuota,
        'used': use.used,
        'pending': use.pending,
        'remaining': remaining,
        'available': available,
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/leave/requests', (Request req) async {
    try {
      final u = await me(req);
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named(
            'SELECT * FROM leave_requests WHERE user_id=@i::uuid ORDER BY submitted_at DESC',
          ), parameters: {'i': (u['id'] as Object).toString()}));
      return json({
        'requests': [
          for (final row in rows)
            leaveJson(row.toColumnMap().map((k, v) => MapEntry(k.toString(), v)))
        ]
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  // ---------- ajukan ----------
  r.post('/leave/requests', (Request req) async {
    try {
      final u = await me(req);
      final b = await readJson(req);
      final type = ((b['type'] ?? '') as String);
      if (!typeLabels.containsKey(type)) {
        throw const _Http(422, 'Jenis pengajuan tidak dikenal.');
      }
      final reason = ((b['reason'] ?? '') as String).trim();
      if (reason.length < 5) throw const _Http(422, 'Alasan minimal 5 karakter.');
      final today = dateOnly(nowWib());

      var s = DateTime.tryParse(((b['start'] ?? '') as String));
      var e = DateTime.tryParse(((b['end'] ?? '') as String));
      if (type == 'maternity') {
        // tanggal otomatis 3 bulan sejak hari pengajuan
        s = today;
        e = addMonths(today, 3);
      }
      if (s == null || e == null) throw const _Http(422, 'Tanggal tidak valid.');
      final ss = dateOnly(s);
      final ee = dateOnly(e);
      if (ee.isBefore(ss)) {
        throw const _Http(422, 'Tanggal selesai tidak boleh sebelum tanggal mulai.');
      }
      final maxBack = type == 'sick' ? 7 : 0;
      if (ss.isBefore(today.subtract(Duration(days: maxBack)))) {
        throw _Http(
            422,
            maxBack == 0
                ? '${typeLabels[type]} tidak bisa diajukan untuk tanggal yang sudah lewat.'
                : '${typeLabels[type]} paling lambat diajukan $maxBack hari setelah tanggal mulai.');
      }
      if (ee.isAfter(today.add(const Duration(days: 180)))) {
        throw const _Http(422, 'Pengajuan paling jauh 180 hari ke depan.');
      }
      final days = workingDaysBetween(ss, ee);
      if (days == 0) {
        throw const _Http(422, 'Rentang tanggal hanya berisi hari libur akhir pekan.');
      }
      var attName = ((b['attachmentName'] ?? '') as String).trim();
      final attSize = (b['attachmentSize'] as num?)?.toInt();
      if (attName.length > 120) attName = attName.substring(0, 120);
      if (type == 'sick' && days >= 2 && attName.isEmpty) {
        throw const _Http(422, 'Sakit 2 hari atau lebih wajib melampirkan surat dokter.');
      }
      String? attOut;
      if (attName.isNotEmpty) {
        if ((attSize ?? 0) > 2 * 1024 * 1024) {
          throw const _Http(422, 'Ukuran lampiran maksimal 2 MB.');
        }
        final ext = attName.split('.').last.toLowerCase();
        if (!{'pdf', 'jpg', 'jpeg', 'png'}.contains(ext)) {
          throw const _Http(422, 'Lampiran harus PDF / JPG / PNG.');
        }
        attOut = attName;
      }
      // key S3 (bila klien upload via /uploads/presign): wajib milik sendiri
      var attKey = ((b['attachmentKey'] ?? '') as String).trim();
      if (attKey.isEmpty) attKey = '';
      if (attKey.isNotEmpty) {
        final uname = (u['username'] as String).toLowerCase();
        if (!attKey.startsWith('leave/$uname/')) {
          throw const _Http(422, 'Key lampiran tidak valid.');
        }
        final ext = attKey.split('.').last.toLowerCase();
        if (!{'pdf', 'jpg', 'jpeg', 'png'}.contains(ext)) {
          throw const _Http(422, 'Lampiran harus PDF / JPG / PNG.');
        }
        final s3 = storeOf(cfg);
        if (s3 != null && !await s3.exists(attKey)) {
          throw const _Http(422, 'Upload lampiran tidak ditemukan. Unggah ulang.');
        }
      }

      final created = await db.pool.runTx((tx) async {
        if (type == 'annual') {
          final use = await annualUsage(tx, (u['id'] as Object).toString());
          final avail = ((annualQuota - use.used).clamp(0, annualQuota) - use.pending)
              .clamp(0, annualQuota);
          if (days > avail) {
            throw _Http(422, 'Sisa cuti tahunan yang bisa diajukan $avail hari.');
          }
        }
        final clash = await tx.execute(Sql.named('''
          SELECT type, start_date, end_date, status FROM leave_requests
          WHERE user_id=@i::uuid AND status IN ('pending','approved')
            AND start_date<=@e AND end_date>=@s LIMIT 1
        '''), parameters: {
          'i': (u['id'] as Object).toString(),
          's': ss.toIso8601String().substring(0, 10),
          'e': ee.toIso8601String().substring(0, 10),
        });
        if (clash.isNotEmpty) {
          final m = clash.first.toColumnMap();
          final t = (typeLabels[m['type']] ?? '').toString().toLowerCase();
          throw _Http(400, 'Bertabrakan dengan pengajuan $t yang ${m['status']}.');
        }
        final ins = await tx.execute(Sql.named('''
          INSERT INTO leave_requests(user_id, type, start_date, end_date,
            working_days, reason, attachment_name, attachment_size, attachment_key)
          VALUES(@i::uuid, @t, @s, @e, @d, @r, @an, @as, @ak) RETURNING *
        '''), parameters: {
          'i': (u['id'] as Object).toString(),
          't': type,
          's': ss.toIso8601String().substring(0, 10),
          'e': ee.toIso8601String().substring(0, 10),
          'd': days,
          'r': reason,
          'an': attOut,
          'as': attOut == null ? null : attSize,
          'ak': attKey.isEmpty ? null : attKey,
        });
        final row = ins.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        for (final rev in await reviewersFor(
            tx, u['username'] as String, u['role'] as String)) {
          await notifyTx(tx, rev['username'] as String,
              kind: 'reviewRequested',
              title: 'Pengajuan ${typeLabels[type]!.toLowerCase()} baru',
              body: '${u['full_name']} mengajukan ${typeLabels[type]!.toLowerCase()} '
                  '($days hari).');
        }
        return row;
      });
      return json(leaveJson(created), status: 201);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/leave/requests/<id>/cancel', (Request req, String id) async {
    try {
      final u = await me(req);
      final row = await db.pool.runTx((tx) async {
        final upd = await tx.execute(Sql.named('''
          UPDATE leave_requests SET status='cancelled'
          WHERE id=@i::uuid AND user_id=@u::uuid AND status='pending' RETURNING *
        '''), parameters: {'i': id, 'u': (u['id'] as Object).toString()});
        if (upd.isEmpty) {
          throw const _Http(404, 'Pengajuan tidak ditemukan atau sudah diproses.');
        }
        return upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
      });
      return json(leaveJson(row));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  // ---------- antrean persetujuan ----------
  r.get('/leave/queue', (Request req) async {
    try {
      final actor = await me(req);
      if (actor['role'] != 'manager' && actor['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat memproses pengajuan.');
      }
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT l.*, u.username, u.full_name AS efn, u.role AS urel
        FROM leave_requests l JOIN users u ON u.id=l.user_id
        WHERE l.status<>'cancelled' AND u.username<>@me AND u.active
        ORDER BY l.submitted_at
      '''), parameters: {'me': actor['username']}));
      final pending = <Map<String, dynamic>>[];
      final done = <Map<String, dynamic>>[];
      for (final row in rows) {
        final m = row.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if (!canManageRole(actor['role'] as String, (m['urel'] ?? 'staff') as String)) {
          continue;
        }
        final use = await db.pool.runTx(
            (tx) => annualUsage(tx, (m['user_id'] as Object).toString()));
        final item = {
          'employee': {'username': m['username'], 'fullName': m['efn']},
          'request': leaveJson(m),
          'balance': {
            'year': nowWib().year,
            'quota': annualQuota,
            'used': use.used,
            'pending': use.pending,
          },
        };
        ((m['status'] == 'pending' ? pending : done)).add(item);
      }
      return json({
        'queue': [...pending, ...done.reversed]
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/leave/requests/<id>/review', (Request req, String id) async {
    try {
      final actor = await me(req);
      if (actor['role'] != 'manager' && actor['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat memproses pengajuan.');
      }
      final b = await readJson(req);
      final approve = b['approve'] == true;
      final note = ((b['note'] ?? '') as String).trim();
      if (!approve && note.length < 5) {
        throw const _Http(422, 'Tulis alasan penolakan minimal 5 karakter.');
      }
      if (note.length > 300) {
        throw const _Http(422, 'Catatan maksimal 300 karakter.');
      }
      final done = await db.pool.runTx((tx) async {
        final cur = await tx.execute(Sql.named('''
          SELECT l.*, u.username, u.full_name AS efn, u.role AS urel
          FROM leave_requests l JOIN users u ON u.id=l.user_id
          WHERE l.id=@i::uuid'''), parameters: {'i': id});
        if (cur.isEmpty) throw const _Http(404, 'Pengajuan tidak ditemukan.');
        final m = cur.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if (m['status'] != 'pending') {
          throw _Http(400, 'Pengajuan ini sudah ${m['status']}. Muat ulang untuk melihat status terbaru.');
        }
        if (m['username'] == actor['username']) {
          throw const _Http(403, 'Anda tidak dapat memproses pengajuan Anda sendiri.');
        }
        if (!canManageRole(actor['role'] as String, (m['urel'] ?? 'staff') as String)) {
          throw const _Http(403, 'Anda tidak berhak memproses pengajuan karyawan ini.');
        }
        if (approve && m['type'] == 'annual') {
          final use = await annualUsage(tx, (m['user_id'] as Object).toString());
          final remain = (annualQuota - use.used).clamp(0, annualQuota);
          if ((m['working_days'] as int) > remain) {
            throw _Http(400,
                'Sisa cuti tahunan ${m['efn']} tinggal $remain hari, tidak cukup untuk ${m['working_days']} hari.');
          }
        }
        final upd = await tx.execute(Sql.named('''
          UPDATE leave_requests SET status=@s, reviewed_by=@b, reviewed_at=now(), reviewer_note=@n
          WHERE id=@i::uuid RETURNING *
        '''), parameters: {
          's': approve ? 'approved' : 'rejected',
          'b': actor['full_name'],
          'n': note.isEmpty ? null : note,
          'i': id,
        });
        final rm = upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        await notifyTx(tx, m['username'] as String,
            kind: approve ? 'leaveApproved' : 'leaveRejected',
            title: approve ? 'Cuti disetujui' : 'Cuti ditolak',
            body: approve
                ? '${typeLabels[m['type']]} disetujui oleh ${actor['full_name']}.'
                : '${typeLabels[m['type']]} ditolak oleh ${actor['full_name']}'
                    '${note.isEmpty ? '.' : ': "$note"'}');
        final use = await annualUsage(tx, (m['user_id'] as Object).toString());
        return {
          'employee': {'username': m['username'], 'fullName': m['efn']},
          'request': leaveJson(rm),
          'balance': {
            'year': nowWib().year,
            'quota': annualQuota,
            'used': use.used,
            'pending': use.pending,
          },
        };
      });
      return json(done);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  // ---------- cuti bersama ----------
  r.post('/leave/collective', (Request req) async {
    try {
      final actor = await me(req);
      if (actor['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Super Admin yang dapat memotong cuti bersama.');
      }
      final b = await readJson(req);
      final s = DateTime.tryParse(((b['start'] ?? '') as String));
      final e = DateTime.tryParse(((b['end'] ?? '') as String));
      final reason = ((b['reason'] ?? '') as String).trim();
      if (s == null || e == null || e.isBefore(s)) {
        throw const _Http(422, 'Tanggal selesai tidak boleh sebelum tanggal mulai.');
      }
      if (workingDaysBetween(s, e) == 0) {
        throw const _Http(422, 'Rentang tanggal hanya berisi hari libur akhir pekan.');
      }
      if (reason.length < 5) throw const _Http(422, 'Alasan minimal 5 karakter.');
      final names = [
        for (final v in ((b['usernames'] as List?) ?? []))
          (v as String).trim().toLowerCase()
      ].where((v) => v.isNotEmpty).toSet().toList();
      if (names.isEmpty) throw const _Http(422, 'Pilih minimal satu karyawan.');

      final results = <Map<String, dynamic>>[];
      for (final name in names) {
        final item = await db.pool.runTx((tx) async {
          final acc = await tx.execute(
              Sql.named('SELECT * FROM users WHERE username=@u'),
              parameters: {'u': name});
          if (acc.isEmpty || acc.first.toColumnMap()['active'] != true) {
            return {
              'employee': {'username': name, 'fullName': name},
              'days': 0,
              'skipped': 'Akun tidak ditemukan atau nonaktif.',
            };
          }
          final a = acc.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
          // tanggal yg sudah tercakup cuti tahunan yg disetujui -> lewati
          final covered = await tx.execute(Sql.named('''
            SELECT start_date, end_date FROM leave_requests
            WHERE user_id=@i::uuid AND type='annual' AND status='approved'
              AND start_date<=@e AND end_date>=@s
          '''), parameters: {
            'i': (a['id'] as Object).toString(),
            's': dateOnly(s).toIso8601String().substring(0, 10),
            'e': dateOnly(e).toIso8601String().substring(0, 10),
          });
          var day = dateOnly(s);
          final last = dateOnly(e);
          var effective = 0;
          while (!day.isAfter(last)) {
            if (!isWeekend(day)) {
              var hit = false;
              for (final row in covered) {
                final m = row.toColumnMap();
                if (!day.isBefore(dateOnly(m['start_date'] as DateTime)) &&
                    !day.isAfter(dateOnly(m['end_date'] as DateTime))) {
                  hit = true;
                  break;
                }
              }
              if (!hit) effective++;
            }
            day = DateTime(day.year, day.month, day.day + 1);
          }
          if (effective == 0) {
            return {
              'employee': {'username': a['username'], 'fullName': a['full_name']},
              'days': 0,
              'skipped': 'Sudah tercakup cuti yang disetujui.',
            };
          }
          await tx.execute(Sql.named('''
            INSERT INTO leave_requests(user_id, type, start_date, end_date,
              working_days, reason, status, reviewed_by, reviewed_at)
            VALUES(@i::uuid, 'annual', @s, @e, @d, @r, 'approved', @b, now())
          '''), parameters: {
            'i': (a['id'] as Object).toString(),
            's': dateOnly(s).toIso8601String().substring(0, 10),
            'e': dateOnly(e).toIso8601String().substring(0, 10),
            'd': effective,
            'r': reason,
            'b': actor['full_name'],
          });
          final use = await annualUsage(tx, (a['id'] as Object).toString());
          final remain = (annualQuota - use.used).clamp(0, annualQuota);
          await notifyTx(tx, a['username'] as String,
              kind: 'collectiveLeaveApplied',
              title: 'Cuti bersama: $effective hari terpotong',
              body: '$reason memotong $effective hari cuti tahunan Anda. Sisa $remain hari.');
          return {
            'employee': {'username': a['username'], 'fullName': a['full_name']},
            'days': effective,
            'skipped': null,
          };
        });
        results.add(item);
      }
      return json({'results': results});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  return r;
}

Router overtimeRouter(Db db, Config cfg) {
  final r = Router();

  Future<Map<String, dynamic>> me(Request req) async {
    final u = await authedUser(req, db, cfg);
    if (u == null) throw const _Http(401, 'Sesi berakhir. Silakan masuk kembali.');
    return u;
  }

  r.get('/overtime/requests', (Request req) async {
    try {
      final u = await me(req);
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named(
            'SELECT * FROM overtime_requests WHERE user_id=@i::uuid ORDER BY submitted_at DESC',
          ), parameters: {'i': (u['id'] as Object).toString()}));
      return json({
        'requests': [
          for (final row in rows)
            overtimeJson(row.toColumnMap().map((k, v) => MapEntry(k.toString(), v)))
        ]
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/overtime/requests', (Request req) async {
    try {
      final u = await me(req);
      final b = await readJson(req);
      final day = dateOnly(DateTime.tryParse(((b['date'] ?? '') as String)) ?? DateTime(1970));
      final s = DateTime.tryParse(((b['start'] ?? '') as String));
      final e = DateTime.tryParse(((b['end'] ?? '') as String));
      final reason = ((b['reason'] ?? '') as String).trim();
      final today = dateOnly(nowWib());
      if (day.isAfter(today)) {
        throw const _Http(422, 'Lembur diajukan setelah dikerjakan, bukan sebelumnya.');
      }
      if (today.difference(day).inDays > 30) {
        throw const _Http(422, 'Lembur hanya bisa diajukan untuk 30 hari terakhir.');
      }
      if (s == null || e == null || !e.isAfter(s)) {
        throw const _Http(422, 'Jam selesai harus setelah jam mulai pada tanggal yang sama.');
      }
      final ss = DateTime(day.year, day.month, day.day, s.hour, s.minute);
      final ee = DateTime(day.year, day.month, day.day, e.hour, e.minute);
      if (ee.difference(ss).inMinutes < 60) {
        throw const _Http(422, 'Durasi lembur minimal 60 menit (1 jam).');
      }
      if (reason.length < 10) {
        throw const _Http(422, 'Keterangan minimal 10 karakter.');
      }
      final created = await db.pool.runTx((tx) async {
        final clash = await tx.execute(Sql.named('''
          SELECT type FROM leave_requests WHERE user_id=@i::uuid
            AND status IN ('pending','approved') AND start_date<=@d AND end_date>=@d LIMIT 1
        '''), parameters: {
          'i': (u['id'] as Object).toString(),
          'd': day.toIso8601String().substring(0, 10),
        });
        if (clash.isNotEmpty) {
          final t = (typeLabels[clash.first.toColumnMap()['type']] ?? '').toString().toLowerCase();
          throw _Http(400, 'Tanggal ini tercakup pengajuan $t. Lembur tidak bisa diajukan.');
        }
        final dup = await tx.execute(Sql.named('''
          SELECT 1 FROM overtime_requests WHERE user_id=@i::uuid AND date=@d
            AND status IN ('pending','approved') LIMIT 1
        '''), parameters: {
          'i': (u['id'] as Object).toString(),
          'd': day.toIso8601String().substring(0, 10),
        });
        if (dup.isNotEmpty) {
          throw const _Http(400, 'Sudah ada pengajuan lembur untuk tanggal ini.');
        }
        final ins = await tx.execute(Sql.named('''
          INSERT INTO overtime_requests(user_id, date, start_time, end_time, reason)
          VALUES(@i::uuid, @d, @s, @e, @r) RETURNING *
        '''), parameters: {
          'i': (u['id'] as Object).toString(),
          'd': day.toIso8601String().substring(0, 10),
          's': ss.toUtc().toIso8601String(),
          'e': ee.toUtc().toIso8601String(),
          'r': reason,
        });
        final row = ins.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        for (final rev in await reviewersFor(
            tx, u['username'] as String, u['role'] as String)) {
          await notifyTx(tx, rev['username'] as String,
              kind: 'reviewRequested',
              title: 'Pengajuan lembur baru',
              body: '${u['full_name']} mengajukan lembur.');
        }
        return row;
      });
      return json(overtimeJson(created), status: 201);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/overtime/requests/<id>/cancel', (Request req, String id) async {
    try {
      final u = await me(req);
      final row = await db.pool.runTx((tx) async {
        final upd = await tx.execute(Sql.named('''
          UPDATE overtime_requests SET status='cancelled'
          WHERE id=@i::uuid AND user_id=@u::uuid AND status='pending' RETURNING *
        '''), parameters: {'i': id, 'u': (u['id'] as Object).toString()});
        if (upd.isEmpty) {
          throw const _Http(404, 'Pengajuan lembur tidak ditemukan atau sudah diproses.');
        }
        return upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
      });
      return json(overtimeJson(row));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/overtime/queue', (Request req) async {
    try {
      final actor = await me(req);
      if (actor['role'] != 'manager' && actor['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat memproses pengajuan.');
      }
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT o.*, u.username, u.full_name AS efn, u.role AS urel
        FROM overtime_requests o JOIN users u ON u.id=o.user_id
        WHERE o.status<>'cancelled' AND u.username<>@me AND u.active
        ORDER BY o.submitted_at
      '''), parameters: {'me': actor['username']}));
      final pending = <Map<String, dynamic>>[];
      final done = <Map<String, dynamic>>[];
      for (final row in rows) {
        final m = row.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if (!canManageRole(actor['role'] as String, (m['urel'] ?? 'staff') as String)) continue;
        final item = {
          'employee': {'username': m['username'], 'fullName': m['efn']},
          'request': overtimeJson(m),
        };
        ((m['status'] == 'pending' ? pending : done)).add(item);
      }
      return json({
        'queue': [...pending, ...done.reversed]
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/overtime/requests/<id>/review', (Request req, String id) async {
    try {
      final actor = await me(req);
      if (actor['role'] != 'manager' && actor['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat memproses pengajuan.');
      }
      final b = await readJson(req);
      final approve = b['approve'] == true;
      final note = ((b['note'] ?? '') as String).trim();
      if (!approve && note.length < 5) {
        throw const _Http(422, 'Tulis alasan penolakan minimal 5 karakter.');
      }
      if (note.length > 300) {
        throw const _Http(422, 'Catatan maksimal 300 karakter.');
      }
      final done = await db.pool.runTx((tx) async {
        final cur = await tx.execute(Sql.named('''
          SELECT o.*, u.username, u.full_name AS efn, u.role AS urel
          FROM overtime_requests o JOIN users u ON u.id=o.user_id
          WHERE o.id=@i::uuid'''), parameters: {'i': id});
        if (cur.isEmpty) throw const _Http(404, 'Pengajuan lembur tidak ditemukan.');
        final m = cur.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if (m['status'] != 'pending') {
          throw _Http(400, 'Pengajuan ini sudah ${m['status']}. Muat ulang untuk melihat status terbaru.');
        }
        if (m['username'] == actor['username']) {
          throw const _Http(403, 'Anda tidak dapat memproses pengajuan Anda sendiri.');
        }
        if (!canManageRole(actor['role'] as String, (m['urel'] ?? 'staff') as String)) {
          throw const _Http(403, 'Anda tidak berhak memproses pengajuan ini.');
        }
        final upd = await tx.execute(Sql.named('''
          UPDATE overtime_requests SET status=@s, reviewed_by=@b, reviewed_at=now(), reviewer_note=@n
          WHERE id=@i::uuid RETURNING *
        '''), parameters: {
          's': approve ? 'approved' : 'rejected',
          'b': actor['full_name'],
          'n': note.isEmpty ? null : note,
          'i': id,
        });
        final rm = upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        await notifyTx(tx, m['username'] as String,
            kind: approve ? 'overtimeApproved' : 'overtimeRejected',
            title: approve ? 'Pengajuan lembur disetujui' : 'Pengajuan lembur ditolak',
            body: approve
                ? 'Lembur disetujui oleh ${actor['full_name']}.'
                : 'Lembur ditolak oleh ${actor['full_name']}${note.isEmpty ? '.' : ': "$note"'}');
        return {
          'employee': {'username': m['username'], 'fullName': m['efn']},
          'request': overtimeJson(rm),
        };
      });
      return json(done);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  return r;
}

Router notificationRouter(Db db, Config cfg) {
  final r = Router();

  Future<Map<String, dynamic>> me(Request req) async {
    final u = await authedUser(req, db, cfg);
    if (u == null) throw const _Http(401, 'Sesi berakhir. Silakan masuk kembali.');
    return u;
  }

  Map<String, dynamic> nJson(Map<String, dynamic> m) => {
        'id': (m['id'] as Object).toString(),
        'kind': m['kind'],
        'title': m['title'],
        'body': m['body'],
        'createdAt': isoUtc(m['created_at'] as DateTime),
        'read': m['read'],
        'refType': m['ref_type'],
        'refId': m['ref_id'] == null ? null : (m['ref_id'] as Object).toString(),
      };

  r.get('/notifications', (Request req) async {
    try {
      final u = await me(req);
      final limit =
          (int.tryParse(req.url.queryParameters['limit'] ?? '') ?? 50).clamp(1, 100);
      // pengingat kontrak: id stabil per karyawan+tanggal berakhir, insert
      // idempoten agar bisa ditandai dibaca & muncul lagi bila diperpanjang
      final today = dateOnly(nowWib());
      await db.pool.runTx((tx) async {
        final emps = await tx.execute(Sql.named('''
          SELECT username, full_name, role, contract_months, join_date
          FROM users WHERE active AND employment_status IN ('contract','internship')
            AND contract_months IS NOT NULL AND username<>@me
        '''), parameters: {'me': u['username']});
        for (final row in emps) {
          final m = row.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
          if (!canManageRole(u['role'] as String, (m['role'] ?? 'staff') as String)) {
            continue;
          }
          final end = addMonths(
            dateOnly(m['join_date'] as DateTime),
            (m['contract_months'] as int),
          );
          final left = end.difference(today).inDays;
          final stamp = end.toIso8601String().substring(0, 10).replaceAll('-', '');
          if (left >= 0 && left <= 30) {
            await tx.execute(Sql.named('''
              INSERT INTO notifications(id, username, kind, title, body)
              VALUES(@i,@u,'contractExpiring',@t,@b) ON CONFLICT (id) DO NOTHING
            '''), parameters: {
              'i': 'contract-${m['username']}-$stamp',
              'u': u['username'],
              't': 'Kontrak segera berakhir',
              'b': 'Kontrak ${m['full_name']} tersisa $left hari.',
            });
          } else if (left < 0 && left >= -90) {
            await tx.execute(Sql.named('''
              INSERT INTO notifications(id, username, kind, title, body)
              VALUES(@i,@u,'contractExpired',@t,@b) ON CONFLICT (id) DO NOTHING
            '''), parameters: {
              'i': 'contract-${m['username']}-$stamp',
              'u': u['username'],
              't': 'Kontrak sudah berakhir',
              'b': 'Kontrak ${m['full_name']} sudah lewat ${-left} hari.',
            });
          }
        }
      });
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named(
            'SELECT * FROM notifications WHERE username=@u ORDER BY created_at DESC LIMIT @l',
          ), parameters: {'u': u['username'], 'l': limit}));
      return json({
        'notifications': [
          for (final row in rows)
            nJson(row.toColumnMap().map((k, v) => MapEntry(k.toString(), v)))
        ]
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/notifications/unread-count', (Request req) async {
    try {
      final u = await me(req);
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named(
            'SELECT COUNT(*) AS c FROM notifications WHERE username=@u AND NOT read',
          ), parameters: {'u': u['username']}));
      return json(
          {'unread': int.parse((rows.first.toColumnMap()['c'] as Object).toString())});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/notifications/<id>/read', (Request req, String id) async {
    try {
      final u = await me(req);
      await db.pool.runTx((tx) => tx.execute(Sql.named(
            'UPDATE notifications SET read=TRUE WHERE id=@i AND username=@u',
          ), parameters: {'i': id, 'u': u['username']}));
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/notifications/read-all', (Request req) async {
    try {
      final u = await me(req);
      await db.pool.runTx((tx) => tx.execute(Sql.named(
            'UPDATE notifications SET read=TRUE WHERE username=@u',
          ), parameters: {'u': u['username']}));
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.delete('/notifications', (Request req) async {
    try {
      final u = await me(req);
      await db.pool.runTx((tx) => tx.execute(Sql.named(
            'DELETE FROM notifications WHERE username=@u',
          ), parameters: {'u': u['username']}));
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  // ---------- siaran superadmin: judul + isi bebas ----------
  r.post('/notifications/broadcast', (Request req) async {
    try {
      final actor = await me(req);
      if (actor['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Super Admin yang dapat mengirim siaran.');
      }
      final b = await readJson(req);
      final title = ((b['title'] ?? '') as String).trim();
      final body = ((b['body'] ?? '') as String).trim();
      final audience = ((b['audience'] ?? 'all') as String);
      if (title.length < 3) {
        throw const _Http(422, 'Judul siaran minimal 3 karakter.');
      }
      if (title.length > 120) {
        throw const _Http(422, 'Judul siaran maksimal 120 karakter.');
      }
      if (body.isEmpty) {
        throw const _Http(422, 'Isi siaran wajib diisi.');
      }
      if (body.length > 500) {
        throw const _Http(422, 'Isi siaran maksimal 500 karakter.');
      }
      if (audience != 'all' && audience != 'staff' && audience != 'managers') {
        throw const _Http(422, 'Sasaran siaran tidak dikenal.');
      }
      final sent = await db.pool.runTx((tx) async {
        final rs = await tx.execute(Sql.named('''
          SELECT username, role, id FROM users
          WHERE active ORDER BY full_name
        '''));
        final targets = <String>[];
        for (final row in rs) {
          final m = row.toColumnMap();
          final role = (m['role'] ?? 'staff') as String;
          if (audience == 'staff' && role != 'staff') continue;
          if (audience == 'managers' && role != 'manager' && role != 'superadmin') {
            continue;
          }
          targets.add(m['username'] as String);
        }
        for (final username in targets) {
          await notifyTx(tx, username,
              kind: 'announcement', title: title, body: body);
        }
        var devices = 0;
        if (targets.isNotEmpty) {
          final dc = await tx.execute(Sql.named('''
            SELECT COUNT(DISTINCT f.token) AS c FROM fcm_tokens f
            JOIN users u ON u.id=f.user_id WHERE u.username = ANY(@ns)
          '''), parameters: {
            'ns': targets,
          });
          devices =
              int.tryParse((dc.first.toColumnMap()['c'] as Object).toString()) ?? 0;
        }
        return (sent: targets.length, devices: devices);
      });
      if (sent.sent == 0) {
        return json({'message': 'Tidak ada penerima yang cocok.'}, status: 422);
      }
      return json({'sent': sent.sent, 'devices': sent.devices});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  // ---------- token push per perangkat ----------
  r.post('/users/me/push-tokens', (Request req) async {
    try {
      final u = await me(req);
      final b = await readJson(req);
      final token = ((b['token'] ?? '') as String).trim();
      final platform = ((b['platform'] ?? 'android') as String).trim();
      if (token.length < 10) throw const _Http(422, 'Token push tidak valid.');
      await db.pool.runTx((tx) => tx.execute(Sql.named('''
        INSERT INTO fcm_tokens(token, user_id, platform, updated_at)
        VALUES(@t,@i::uuid,@p,now())
        ON CONFLICT (token) DO UPDATE SET user_id=@i::uuid, updated_at=now()
      '''), parameters: {
        't': token,
        'i': (u['id'] as Object).toString(),
        'p': platform.isEmpty ? 'android' : platform,
      }));
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.delete('/users/me/push-tokens', (Request req) async {
    try {
      final u = await me(req);
      final b = await readJson(req);
      final token = ((b['token'] ?? '') as String).trim();
      await db.pool.runTx((tx) => tx.execute(
            token.isEmpty
                ? Sql.named('DELETE FROM fcm_tokens WHERE user_id=@i::uuid')
                : Sql.named(
                    'DELETE FROM fcm_tokens WHERE user_id=@i::uuid AND token=@t'),
            parameters: {
              'i': (u['id'] as Object).toString(),
              if (token.isNotEmpty) 't': token,
            },
          ));
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  return r;
}
