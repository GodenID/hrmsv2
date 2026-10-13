import 'dart:convert';
import 'dart:math' as math;

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

double haversine(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return 2 * 6371000 * math.asin(math.min(1, math.sqrt(a)));
}

String fmtDist(double m) {
  if (m < 1000) return '${m.round()} m';
  final km = m / 1000;
  final t = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
  return '${t.replaceAll('.', ',')} km';
}

Map<String, dynamic> locJson(Map<String, dynamic> r) => {
      'id': r['id'],
      'name': r['name'],
      'latitude': r['latitude'],
      'longitude': r['longitude'],
      'radiusMeters': r['radius_meters'],
    };

Map<String, dynamic> recordJson(Map<String, dynamic>? r, DateTime date) => {
      'date': date.toIso8601String().substring(0, 10),
      'clockIn': isoUtcOpt(r?['clock_in'] as DateTime?),
      'clockOut': isoUtcOpt(r?['clock_out'] as DateTime?),
      'clockInLocation': r?['clock_in_location'],
      'clockOutLocation': r?['clock_out_location'],
    };

Map<String, dynamic> correctionJson(Map<String, dynamic> r) => {
      'id': (r['id'] as Object).toString(),
      'date': (r['date'] as DateTime).toIso8601String().substring(0, 10),
      'clockIn': isoUtc(r['clock_in'] as DateTime),
      'clockOut': isoUtc(r['clock_out'] as DateTime),
      'reason': r['reason'],
      'status': r['status'],
      'submittedAt': isoUtc(r['submitted_at'] as DateTime),
      'reviewedBy': r['reviewed_by'],
      'reviewedAt': isoUtcOpt(r['reviewed_at'] as DateTime?),
      'reviewerNote': r['reviewer_note'],
    };

Map<String, dynamic> ooaJson(Map<String, dynamic> r) => {
      'id': (r['id'] as Object).toString(),
      'date': (r['date'] as DateTime).toIso8601String().substring(0, 10),
      'kind': r['kind'],
      'requestedAt': isoUtc(r['requested_at'] as DateTime),
      'latitude': r['latitude'],
      'longitude': r['longitude'],
      'accuracyMeters': r['accuracy_meters'],
      'nearestLocationName': r['nearest_location'],
      'distanceMeters': r['distance_meters'],
      'reason': r['reason'],
      'status': r['status'],
      'submittedAt': isoUtc(r['submitted_at'] as DateTime),
      'reviewedBy': r['reviewed_by'],
      'reviewedAt': isoUtcOpt(r['reviewed_at'] as DateTime?),
      'reviewerNote': r['reviewer_note'],
    };

Map<String, dynamic> overtimeOut(Map<String, dynamic> r) => {
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

Router attendanceRouter(Db db, Config cfg) {
  final r = Router();

  Future<Map<String, dynamic>> me(Request req) async {
    final u = await authedUser(req, db, cfg);
    if (u == null) throw const _Http(401, 'Sesi berakhir. Silakan masuk kembali.');
    return u;
  }

  // ---------- lokasi ----------
  r.get('/attendance/locations', (Request req) async {
    await me(req);
    final rows = await db.pool.runTx(
        (tx) => tx.execute(Sql.named('SELECT * FROM attendance_locations ORDER BY name')));
    return json({'locations': [for (final row in rows) locJson(row.toColumnMap().map((k, v) => MapEntry(k.toString(), v)))]});
  });

  r.post('/attendance/locations', (Request req) async {
    try {
      final actor = await me(req);
      if (actor['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Super Admin yang dapat mengatur lokasi absen.');
      }
      final b = await readJson(req);
      final name = ((b['name'] ?? '') as String).trim();
      final lat = (b['latitude'] as num?)?.toDouble();
      final lng = (b['longitude'] as num?)?.toDouble();
      final rad = (b['radiusMeters'] as num?)?.toInt() ?? 100;
      if (name.length < 3) throw const _Http(422, 'Nama lokasi minimal 3 karakter.');
      if (lat == null || lat < -90 || lat > 90) throw const _Http(422, 'Latitude antara -90 dan 90.');
      if (lng == null || lng < -180 || lng > 180) throw const _Http(422, 'Longitude antara -180 dan 180.');
      if (rad < 25 || rad > 1000) throw const _Http(422, 'Radius 25–1000 meter.');
      final saved = await db.pool.runTx((tx) async {
        final id = 'LOC-${DateTime.now().millisecondsSinceEpoch}';
        await tx.execute(Sql.named(
          'INSERT INTO attendance_locations(id,name,latitude,longitude,radius_meters) VALUES(@i,@n,@la,@lo,@r)',
        ), parameters: {'i': id, 'n': name, 'la': lat, 'lo': lng, 'r': rad});
        return {'id': id, 'name': name, 'latitude': lat, 'longitude': lng, 'radiusMeters': rad};
      });
      return json(saved, status: 201);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.put('/attendance/locations/<id>', (Request req, String id) async {
    try {
      final actor = await me(req);
      if (actor['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Super Admin yang dapat mengatur lokasi absen.');
      }
      final b = await readJson(req);
      final name = ((b['name'] ?? '') as String).trim();
      final lat = (b['latitude'] as num?)?.toDouble();
      final lng = (b['longitude'] as num?)?.toDouble();
      final rad = (b['radiusMeters'] as num?)?.toInt() ?? 100;
      if (name.length < 3) throw const _Http(422, 'Nama lokasi minimal 3 karakter.');
      if (lat == null || lat < -90 || lat > 90) throw const _Http(422, 'Latitude antara -90 dan 90.');
      if (lng == null || lng < -180 || lng > 180) throw const _Http(422, 'Longitude antara -180 dan 180.');
      if (rad < 25 || rad > 1000) throw const _Http(422, 'Radius 25–1000 meter.');
      final n = await db.pool.runTx((tx) => tx.execute(Sql.named(
            'UPDATE attendance_locations SET name=@n, latitude=@la, longitude=@lo, radius_meters=@r WHERE id=@i',
          ), parameters: {'i': id, 'n': name, 'la': lat, 'lo': lng, 'r': rad}));
      if (n.affectedRows == 0) return json({'message': 'Lokasi tidak ditemukan. Muat ulang daftar.'}, status: 404);
      return json({'id': id, 'name': name, 'latitude': lat, 'longitude': lng, 'radiusMeters': rad});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.delete('/attendance/locations/<id>', (Request req, String id) async {
    try {
      final actor = await me(req);
      if (actor['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Super Admin yang dapat mengatur lokasi absen.');
      }
      final left = await db.pool.runTx((tx) async {
        final c = await tx.execute(Sql.named('SELECT COUNT(*) AS c FROM attendance_locations'));
        final total = int.parse((c.first.toColumnMap()['c'] as Object).toString());
        if (total <= 1) throw const _Http(400, 'Minimal harus ada satu lokasi absen. Ubah lokasi ini bila perlu.');
        final del = await tx.execute(
            Sql.named('DELETE FROM attendance_locations WHERE id=@i'), parameters: {'i': id});
        return del.affectedRows;
      });
      if (left == 0) return json({'message': 'Lokasi tidak ditemukan. Muat ulang daftar.'}, status: 404);
      return json({'ok': true});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  Future<(Map<String, dynamic> loc, double dist)> requireInside(
    double lat, double lng, bool mocked, double? accuracy) async {
    if (mocked) {
      throw const _Http(400, 'Lokasi palsu terdeteksi. Matikan aplikasi pemalsu lokasi (mock location) lalu coba lagi.');
    }
    final rows = await db.pool.runTx(
        (tx) => tx.execute(Sql.named('SELECT * FROM attendance_locations')));
    if (rows.isEmpty) {
      throw const _Http(400, 'Belum ada lokasi absen yang diatur. Hubungi Super Admin.');
    }
    Map<String, dynamic>? nearest;
    var best = double.infinity;
    var bestDist = 0.0;
    for (final row in rows) {
      final m = row.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
      final d = haversine((m['latitude'] as num).toDouble(), (m['longitude'] as num).toDouble(), lat, lng);
      if (d <= (m['radius_meters'] as int)) return (m, d);
      if (d - (m['radius_meters'] as int) < best) {
        best = d - (m['radius_meters'] as int);
        nearest = m;
        bestDist = d;
      }
    }
    var msg =
        'Anda berada di luar area absen. Lokasi terdekat: ${nearest!['name']}, ${fmtDist(bestDist)} dari posisi Anda (radius ${nearest['radius_meters']} m).';
    if (accuracy != null && accuracy > 100) {
      msg += ' Akurasi lokasi perangkat ±${fmtDist(accuracy)}; aktifkan GPS / lokasi akurat lalu coba lagi.';
    }
    throw _Http(400, msg);
  }

  // ---------- clock ----------
  r.get('/attendance/today', (Request req) async {
    try {
      final u = await me(req);
      final today = dateOnly(DateTime.now().toUtc().add(const Duration(hours: 7)));
      final day = today.toIso8601String().substring(0, 10);
      final rec = await db.pool.runTx((tx) async {
        final rows = await tx.execute(Sql.named(
          'SELECT * FROM attendance_records WHERE user_id=@i::uuid AND date=@d',
        ), parameters: {'i': (u['id'] as Object).toString(), 'd': day});
        Map<String, dynamic>? m = rows.isEmpty
            ? null
            : rows.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        // Yang disetujui hari ini menimpa catatan (jam input pemohon).
        final ooa = await tx.execute(Sql.named('''
          SELECT kind, requested_at FROM out_of_area_requests
          WHERE user_id=@i::uuid AND date=@d AND status='approved'
        '''), parameters: {'i': (u['id'] as Object).toString(), 'd': day});
        DateTime? ci = m?['clock_in'] as DateTime?;
        DateTime? co = m?['clock_out'] as DateTime?;
        String? cil = m?['clock_in_location'] as String?;
        String? col = m?['clock_out_location'] as String?;
        for (final row in ooa) {
          final om = row.toColumnMap();
          if (om['kind'] == 'clockIn') {
            ci = om['requested_at'] as DateTime;
            cil = cil ?? 'Luar area';
          } else {
            co = om['requested_at'] as DateTime;
            col = col ?? 'Luar area';
          }
        }
        final corr = await tx.execute(Sql.named('''
          SELECT clock_in, clock_out FROM attendance_corrections
          WHERE user_id=@i::uuid AND date=@d AND status='approved'
          ORDER BY submitted_at DESC LIMIT 1
        '''), parameters: {'i': (u['id'] as Object).toString(), 'd': day});
        if (corr.isNotEmpty) {
          final cm = corr.first.toColumnMap();
          ci = cm['clock_in'] as DateTime;
          co = cm['clock_out'] as DateTime;
        }
        return {'ci': ci, 'co': co, 'cil': cil, 'col': col};
      });
      return json({
        'date': day,
        'clockIn': isoUtcOpt(rec['ci'] as DateTime?),
        'clockOut': isoUtcOpt(rec['co'] as DateTime?),
        'clockInLocation': rec['cil'],
        'clockOutLocation': rec['col'],
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  Future<Response> doClock(Request req, bool isIn) async {
    try {
      final u = await me(req);
      final b = await readJson(req);
      final lat = (b['latitude'] as num?)?.toDouble();
      final lng = (b['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) throw const _Http(422, 'Koordinat tidak valid.');
      final acc = (b['accuracyMeters'] as num?)?.toDouble();
      final mocked = b['isMocked'] == true;
      final nowWib = DateTime.now().toUtc().add(const Duration(hours: 7));
      final today = dateOnly(nowWib);
      final rec = await db.pool.runTx((tx) async {
        final cur = await tx.execute(Sql.named(
          'SELECT * FROM attendance_records WHERE user_id=@i::uuid AND date=@d',
        ), parameters: {'i': (u['id'] as Object).toString(), 'd': today.toIso8601String().substring(0, 10)});
        Map<String, dynamic>? m = cur.isEmpty
            ? null
            : cur.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if (isIn && m?['clock_in'] != null) throw const _Http(400, 'Anda sudah clock in hari ini.');
        if (!isIn && m?['clock_in'] == null) {
          throw const _Http(400, 'Silakan clock in terlebih dahulu.');
        }
        if (!isIn && m?['clock_out'] != null) {
          throw const _Http(400, 'Anda sudah clock out hari ini.');
        }
        final (loc, _) = await requireInside(lat, lng, mocked, acc);
        Map<String, dynamic> saved;
        if (isIn) {
          final ins = await tx.execute(Sql.named('''
            INSERT INTO attendance_records(user_id, date, clock_in, clock_in_location)
            VALUES(@i::uuid, @d, now(), @l)
            ON CONFLICT (user_id, date) DO UPDATE SET clock_in=now(), clock_in_location=@l
            RETURNING *
          '''), parameters: {
            'i': (u['id'] as Object).toString(),
            'd': today.toIso8601String().substring(0, 10),
            'l': loc['name'],
          });
          saved = ins.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        } else {
          final upd = await tx.execute(Sql.named('''
            UPDATE attendance_records SET clock_out=now(), clock_out_location=@l
            WHERE user_id=@i::uuid AND date=@d RETURNING *
          '''), parameters: {
            'i': (u['id'] as Object).toString(),
            'd': today.toIso8601String().substring(0, 10),
            'l': loc['name'],
          });
          saved = upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        }
        // Clock biasa tercatat → pengajuan luar-area menunggu sisi sama
        // batal otomatis (sudah tidak relevan).
        await tx.execute(Sql.named('''
          UPDATE out_of_area_requests SET status='cancelled',
            reviewed_by='Sistem', reviewed_at=now(),
            reviewer_note='Batal otomatis: clock biasa sudah tercatat.'
          WHERE user_id=@i::uuid AND date=@d AND kind=@k AND status='pending'
        '''), parameters: {
          'i': (u['id'] as Object).toString(),
          'd': today.toIso8601String().substring(0, 10),
          'k': isIn ? 'clockIn' : 'clockOut',
        });
        return saved;
      });
      return json(recordJson(rec, today));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  }

  r.post('/attendance/clock-in', (Request req) => doClock(req, true));
  r.post('/attendance/clock-out', (Request req) => doClock(req, false));

  r.get('/attendance/first-month', (Request req) async {
    try {
      final u = await me(req);
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named(
            'SELECT join_date FROM users WHERE id=@i::uuid',
          ), parameters: {'i': (u['id'] as Object).toString()}));
      final jd = (rows.first.toColumnMap()['join_date'] as DateTime);
      return json({'year': jd.year, 'month': jd.month});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/attendance/month', (Request req) async {
    try {
      final u = await me(req);
      final year = int.tryParse(req.url.queryParameters['year'] ?? '');
      final month = int.tryParse(req.url.queryParameters['month'] ?? '');
      if (year == null || month == null || month < 1 || month > 12) {
        throw const _Http(422, 'Bulan tidak valid.');
      }
      final nowWib = DateTime.now().toUtc().add(const Duration(hours: 7));
      final today = dateOnly(nowWib);
      final joinRows = await db.pool.runTx((tx) => tx.execute(Sql.named(
            'SELECT join_date FROM users WHERE id=@i::uuid',
          ), parameters: {'i': (u['id'] as Object).toString()}));
      final join = dateOnly((joinRows.first.toColumnMap()['join_date'] as DateTime));
      final lastDay = DateTime(year, month + 1, 0).day;
      // cuti menunggu/disetujui yg menyentuh bulan ini (untuk overlay)
      final monthStart = DateTime(year, month, 1).toIso8601String().substring(0, 10);
      final monthEnd = DateTime(year, month, lastDay).toIso8601String().substring(0, 10);
      final leaveRows = await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT * FROM leave_requests WHERE user_id=@i::uuid
          AND status IN ('pending','approved')
          AND start_date<=@e AND end_date>=@s
      '''), parameters: {
        'i': (u['id'] as Object).toString(),
        's': monthStart,
        'e': monthEnd,
      }));
      Map<String, dynamic>? leaveOn(DateTime date) {
        for (final row in leaveRows) {
          final m = row.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
          if (!date.isBefore(dateOnly(m['start_date'] as DateTime)) &&
              !date.isAfter(dateOnly(m['end_date'] as DateTime))) {
            return m;
          }
        }
        return null;
      }

      Map<String, dynamic> leaveOut(Map<String, dynamic> m) => {
            'id': (m['id'] as Object).toString(),
            'type': m['type'],
            'start': (m['start_date'] as DateTime).toIso8601String().substring(0, 10),
            'end': (m['end_date'] as DateTime).toIso8601String().substring(0, 10),
            'workingDays': m['working_days'],
            'reason': m['reason'],
            'status': m['status'],
            'submittedAt': isoUtc(m['submitted_at'] as DateTime),
            'attachment': m['attachment_name'] == null
                ? null
                : {'name': m['attachment_name'], 'sizeBytes': m['attachment_size']},
            'reviewedBy': m['reviewed_by'],
            'reviewedAt': isoUtcOpt(m['reviewed_at'] as DateTime?),
            'reviewerNote': m['reviewer_note'],
          };

      // Overlay pengajuan milik sendiri sebulan penuh (1 query per jenis):
      // koreksi / lembur / luar-area terbaru per tanggal.
      // Catatan: JANGAN pakai .map() di atas hasil toColumnMap() bila
      // sumbernya dynamic — inferensi generic bisa menghasilkan
      // Map<dynamic,dynamic> dan meledak saat dikembalikan (pernah 500
      // untuk bulan berjalan). Bangun map bertipe eksplisit.
      Map<String, dynamic> norm(Map m) {
        final out = <String, dynamic>{};
        m.forEach((k, v) => out[k.toString()] = v);
        return out;
      }

      List<Map<String, dynamic>> rowsOf(dynamic rs) => [
            for (final row in rs) norm(row.toColumnMap()),
          ];
      final corrRows = rowsOf(await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT * FROM attendance_corrections WHERE user_id=@i::uuid
          AND date>=@s AND date<=@e ORDER BY submitted_at DESC
      '''), parameters: {
        'i': (u['id'] as Object).toString(),
        's': monthStart,
        'e': monthEnd,
      })));
      final otRows = rowsOf(await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT * FROM overtime_requests WHERE user_id=@i::uuid
          AND status IN ('pending','approved')
          AND date>=@s AND date<=@e ORDER BY submitted_at DESC
      '''), parameters: {
        'i': (u['id'] as Object).toString(),
        's': monthStart,
        'e': monthEnd,
      })));
      final ooaRows = rowsOf(await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT * FROM out_of_area_requests WHERE user_id=@i::uuid
          AND date>=@s AND date<=@e ORDER BY submitted_at DESC
      '''), parameters: {
        'i': (u['id'] as Object).toString(),
        's': monthStart,
        'e': monthEnd,
      })));

      String dayKey(DateTime d) => d.toIso8601String().substring(0, 10);

      Map<String, dynamic>? latestOn(
          List<Map<String, dynamic>> rows, DateTime date) {
        final k = dayKey(date);
        for (final m in rows) {
          if ((m['date'] as DateTime).toIso8601String().substring(0, 10) == k) {
            return m;
          }
        }
        return null;
      }

      final out = <Map<String, dynamic>>[];
      for (var d = 1; d <= lastDay; d++) {
        final date = DateTime(year, month, d);
        if (date.isBefore(join)) continue;
        if (date.isAfter(today)) {
          // tanggal akan datang: hanya tampil bila tercakup cuti
          final lv = leaveOn(date);
          if (lv != null && !isWeekend(date)) {
            out.add({
              'date': date.toIso8601String().substring(0, 10),
              'status': lv['status'] == 'approved' ? 'leave' : 'upcoming',
              'leave': leaveOut(lv),
            });
          }
          continue;
        }
        if (isWeekend(date)) continue;
        final lv = leaveOn(date);
        final corrLatest = latestOn(corrRows, date);
        final otLatest = latestOn(otRows, date);
        final ooaLatest = latestOn(ooaRows, date);
        final rows = await db.pool.runTx((tx) => tx.execute(Sql.named(
              'SELECT * FROM attendance_records WHERE user_id=@i::uuid AND date=@d',
            ), parameters: {'i': (u['id'] as Object).toString(), 'd': date.toIso8601String().substring(0, 10)}));
        // koreksi disetujui menimpa
        final corr = await db.pool.runTx((tx) => tx.execute(Sql.named(
              '''SELECT * FROM attendance_corrections WHERE user_id=@i::uuid AND date=@d
                 AND status='approved' ORDER BY submitted_at DESC LIMIT 1''',
            ), parameters: {'i': (u['id'] as Object).toString(), 'd': date.toIso8601String().substring(0, 10)}));
        DateTime? ci, co;
        String? cil, col;
        if (rows.isNotEmpty) {
          final m = rows.first.toColumnMap();
          ci = m['clock_in'] as DateTime?;
          co = m['clock_out'] as DateTime?;
          cil = m['clock_in_location'] as String?;
          col = m['clock_out_location'] as String?;
        }
        // luar-area disetujui menimpa
        final ooa = await db.pool.runTx((tx) => tx.execute(Sql.named(
              '''SELECT * FROM out_of_area_requests WHERE user_id=@i::uuid AND date=@d
                 AND status='approved' ORDER BY submitted_at DESC''',
            ), parameters: {'i': (u['id'] as Object).toString(), 'd': date.toIso8601String().substring(0, 10)}));
        for (final row in ooa) {
          final m = row.toColumnMap();
          if (m['kind'] == 'clockIn') {
            ci = m['requested_at'] as DateTime;
          } else {
            co = m['requested_at'] as DateTime;
          }
        }
        if (corr.isNotEmpty) {
          final m = corr.first.toColumnMap();
          ci = m['clock_in'] as DateTime;
          co = m['clock_out'] as DateTime;
        }
        final isToday = date == today;
        final approvedLeave = lv != null && lv['status'] == 'approved';
        String status;
        if (approvedLeave) {
          status = 'leave';
        } else if (isToday && ci == null) {
          status = 'notYet';
        } else if (ci == null) {
          status = 'absent';
        } else if (co == null) {
          status = isToday ? 'inProgress' : 'incomplete';
        } else {
          status = isLate(ci) ? 'late' : 'onTime';
        }
        out.add({
          'date': date.toIso8601String().substring(0, 10),
          'status': status,
          'clockIn': ci == null ? null : isoUtc(ci),
          'clockOut': co == null ? null : isoUtc(co),
          'clockInLocation': cil,
          'clockOutLocation': col,
          'leave': lv == null ? null : leaveOut(lv),
          'correction': corrLatest == null ? null : correctionJson(corrLatest),
          'overtime': otLatest == null ? null : overtimeOut(otLatest),
          'outOfArea': ooaLatest == null ? null : ooaJson(ooaLatest),
        });
      }
      return json({'days': out.reversed.toList()});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  // ---------- koreksi ----------
  r.post('/attendance/corrections', (Request req) async {
    try {
      final u = await me(req);
      final b = await readJson(req);
      final date = DateTime.tryParse(((b['date'] ?? '') as String));
      final ci = DateTime.tryParse(((b['clockIn'] ?? '') as String));
      final co = DateTime.tryParse(((b['clockOut'] ?? '') as String));
      final reason = ((b['reason'] ?? '') as String).trim();
      if (date == null || ci == null || co == null) {
        throw const _Http(422, 'Tanggal & jam tidak valid.');
      }
      if (reason.length < 10) throw const _Http(422, 'Alasan minimal 10 karakter.');
      if (!co.isAfter(ci)) throw const _Http(422, 'Jam pulang harus setelah jam masuk.');
      final nowWib = DateTime.now().toUtc().add(const Duration(hours: 7));
      final today = dateOnly(nowWib);
      final d = dateOnly(date);
      if (!d.isBefore(today)) throw const _Http(422, 'Koreksi hanya untuk hari yang sudah lewat.');
      if (today.difference(d).inDays > 30) {
        throw const _Http(422, 'Koreksi maksimal 30 hari ke belakang.');
      }
      if (isWeekend(d)) throw const _Http(422, 'Akhir pekan tidak perlu dikoreksi.');
      final created = await db.pool.runTx((tx) async {
        final dup = await tx.execute(Sql.named(
          '''SELECT 1 FROM attendance_corrections WHERE user_id=@i::uuid AND date=@d AND status='pending''',
        ), parameters: {'i': (u['id'] as Object).toString(), 'd': d.toIso8601String().substring(0, 10)});
        if (dup.isNotEmpty) throw const _Http(400, 'Sudah ada koreksi menunggu untuk tanggal ini.');
        final ins = await tx.execute(Sql.named('''
          INSERT INTO attendance_corrections(user_id, date, clock_in, clock_out, reason)
          VALUES(@i::uuid, @d, @ci, @co, @r) RETURNING *
        '''), parameters: {
          'i': (u['id'] as Object).toString(),
          'd': d.toIso8601String().substring(0, 10),
          'ci': ci.toUtc().toIso8601String(),
          'co': co.toUtc().toIso8601String(),
          'r': reason,
        });
        final row = ins.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        for (final rev in await reviewersFor(
            tx, u['username'] as String, u['role'] as String)) {
          await notifyTx(tx, rev['username'] as String,
              kind: 'reviewRequested',
              title: 'Koreksi absensi baru',
              body: '${u['full_name']} mengajukan koreksi absensi.');
        }
        return row;
      });
      return json(correctionJson(created), status: 201);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/attendance/corrections/queue', (Request req) async {
    try {
      final actor = await me(req);
      if (actor['role'] != 'manager' && actor['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat memproses koreksi.');
      }
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT c.*, u.username, u.full_name, u.role AS urel
        FROM attendance_corrections c JOIN users u ON u.id=c.user_id
        WHERE c.status='pending' AND u.username<>@me ORDER BY c.submitted_at
      '''), parameters: {'me': actor['username']}));
      final items = <Map<String, dynamic>>[];
      for (final row in rows) {
        final m = row.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if (!canManageRole(actor['role'] as String, (m['urel'] ?? 'staff') as String)) continue;
        items.add({
          'employee': {'username': m['username'], 'fullName': m['full_name']},
          'correction': correctionJson(m),
        });
      }
      return json({'queue': items});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/attendance/corrections/<id>/review', (Request req, String id) async {
    try {
      final actor = await me(req);
      final b = await readJson(req);
      final approve = b['approve'] == true;
      final note = ((b['note'] ?? '') as String).trim();
      if (!approve && note.length < 5) {
        throw const _Http(422, 'Catatan penolakan minimal 5 karakter.');
      }
      final done = await db.pool.runTx((tx) async {
        final cur = await tx.execute(Sql.named(
          '''SELECT c.*, u.username, u.full_name AS efn, u.role AS urel FROM attendance_corrections c
             JOIN users u ON u.id=c.user_id WHERE c.id=@i::uuid''',
        ), parameters: {'i': id});
        if (cur.isEmpty) throw const _Http(404, 'Koreksi tidak ditemukan.');
        final m = cur.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if (m['status'] != 'pending') throw const _Http(400, 'Koreksi sudah diproses.');
        if (m['username'] == actor['username']) {
          throw const _Http(403, 'Anda tidak dapat memproses koreksi Anda sendiri.');
        }
        if (!canManageRole(actor['role'] as String, (m['urel'] ?? 'staff') as String)) {
          throw const _Http(403, 'Anda tidak berhak memproses koreksi ini.');
        }
        final upd = await tx.execute(Sql.named('''
          UPDATE attendance_corrections SET status=@s, reviewed_by=@b, reviewed_at=now(), reviewer_note=@n
          WHERE id=@i::uuid RETURNING *
        '''), parameters: {
          's': approve ? 'approved' : 'rejected',
          'b': actor['full_name'],
          'n': note.isEmpty ? null : note,
          'i': id,
        });
        final cm = upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        await notifyTx(tx, m['username'] as String,
            kind: approve ? 'correctionApproved' : 'correctionRejected',
            title: approve ? 'Koreksi absensi disetujui' : 'Koreksi absensi ditolak',
            body: approve
                ? 'Koreksi absensi disetujui oleh ${actor['full_name']}.'
                : 'Koreksi absensi ditolak oleh ${actor['full_name']}'
                    '${note.isEmpty ? '.' : ': "$note"'}');
        return {
          'employee': {'username': m['username'], 'fullName': m['efn']},
          'correction': correctionJson(cm),
        };
      });
      return json(done);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/attendance/corrections/<id>/cancel', (Request req, String id) async {
    try {
      final u = await me(req);
      final row = await db.pool.runTx((tx) async {
        final upd = await tx.execute(Sql.named('''
          UPDATE attendance_corrections SET status='cancelled'
          WHERE id=@i::uuid AND user_id=@u::uuid AND status='pending' RETURNING *
        '''), parameters: {'i': id, 'u': (u['id'] as Object).toString()});
        if (upd.isEmpty) throw const _Http(404, 'Koreksi tidak ditemukan atau sudah diproses.');
        return upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
      });
      return json(correctionJson(row));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  // ---------- luar area ----------
  r.post('/attendance/out-of-area', (Request req) async {
    try {
      final u = await me(req);
      final b = await readJson(req);
      final kind = ((b['kind'] ?? '') as String);
      if (kind != 'clockIn' && kind != 'clockOut') {
        throw const _Http(422, 'Jenis pengajuan tidak valid.');
      }
      final lat = (b['latitude'] as num?)?.toDouble();
      final lng = (b['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) throw const _Http(422, 'Koordinat tidak valid.');
      final acc = (b['accuracyMeters'] as num?)?.toDouble();
      final mocked = b['isMocked'] == true;
      final reason = ((b['reason'] ?? '') as String).trim();
      if (reason.length < 10) throw const _Http(422, 'Alasan minimal 10 karakter.');
      if (mocked) {
        throw const _Http(400, 'Lokasi palsu terdeteksi. Matikan aplikasi pemalsu lokasi lalu coba lagi.');
      }
      final nowWib = DateTime.now().toUtc().add(const Duration(hours: 7));
      final today = dateOnly(nowWib);
      // bila ternyata di dalam radius -> tolak, pakai clock biasa
      final rows = await db.pool.runTx(
          (tx) => tx.execute(Sql.named('SELECT * FROM attendance_locations')));
      String? insideName;
      for (final row in rows) {
        final m = row.toColumnMap();
        final d = haversine((m['latitude'] as num).toDouble(), (m['longitude'] as num).toDouble(), lat, lng);
        if (d <= (m['radius_meters'] as int)) {
          insideName = m['name'] as String;
          break;
        }
      }
      if (insideName != null) {
        throw _Http(400, 'Anda berada di dalam area $insideName. Silakan pakai clock biasa.');
      }
      // nearest untuk bukti
      String nearest = '-';
      var best = double.infinity;
      for (final row in rows) {
        final m = row.toColumnMap();
        final d = haversine((m['latitude'] as num).toDouble(), (m['longitude'] as num).toDouble(), lat, lng);
        if (d < best) {
          best = d;
          nearest = m['name'] as String;
        }
      }
      final result = await db.pool.runTx((tx) async {
        final rec = await tx.execute(Sql.named(
          'SELECT * FROM attendance_records WHERE user_id=@i::uuid AND date=@d',
        ), parameters: {'i': (u['id'] as Object).toString(), 'd': today.toIso8601String().substring(0, 10)});
        if (rec.isNotEmpty) {
          final m = rec.first.toColumnMap();
          if (kind == 'clockIn' && m['clock_in'] != null) {
            throw const _Http(400, 'Jam masuk hari ini sudah tercatat.');
          }
          if (kind == 'clockOut' && m['clock_out'] != null) {
            throw const _Http(400, 'Jam pulang hari ini sudah tercatat.');
          }
          if (kind == 'clockOut' && m['clock_in'] == null) {
            throw const _Http(400, 'Silakan clock in terlebih dahulu.');
          }
        } else if (kind == 'clockOut') {
          throw const _Http(400, 'Silakan clock in terlebih dahulu.');
        }
        final dup = await tx.execute(Sql.named('''
          SELECT id FROM out_of_area_requests
          WHERE user_id=@i::uuid AND date=@d AND kind=@k AND status='pending'
        '''), parameters: {
          'i': (u['id'] as Object).toString(),
          'd': today.toIso8601String().substring(0, 10),
          'k': kind,
        });
        // Sudah ada yang menunggu: perbarui (jam & posisi ikut sekarang)
        // agar tidak terkunci menunggu.
        if (dup.isNotEmpty) {
          final upd = await tx.execute(Sql.named('''
            UPDATE out_of_area_requests SET requested_at=now(), latitude=@la,
              longitude=@lo, accuracy_meters=@ac, nearest_location=@nl,
              distance_meters=@di, reason=@r, submitted_at=now()
            WHERE id=@i::uuid RETURNING *
          '''), parameters: {
            'i': (dup.first.toColumnMap()['id'] as Object).toString(),
            'la': lat,
            'lo': lng,
            'ac': acc,
            'nl': nearest,
            'di': best.isFinite ? best : 0,
            'r': reason,
          });
          return (
            row: upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v)),
            updated: true,
          );
        }
        final ins = await tx.execute(Sql.named('''
          INSERT INTO out_of_area_requests(user_id, date, kind, latitude, longitude,
            accuracy_meters, nearest_location, distance_meters, reason)
          VALUES(@i::uuid, @d, @k, @la, @lo, @ac, @nl, @di, @r) RETURNING *
        '''), parameters: {
          'i': (u['id'] as Object).toString(),
          'd': today.toIso8601String().substring(0, 10),
          'k': kind,
          'la': lat,
          'lo': lng,
          'ac': acc,
          'nl': nearest,
          'di': best.isFinite ? best : 0,
          'r': reason,
        });
        final row = ins.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        for (final rev in await reviewersFor(
            tx, u['username'] as String, u['role'] as String)) {
          await notifyTx(tx, rev['username'] as String,
              kind: 'reviewRequested',
              title: 'Pengajuan luar area baru',
              body: '${u['full_name']} mengajukan clock dari luar area.');
        }
        return (row: row, updated: false);
      });
      return json(ooaJson(result.row), status: result.updated ? 200 : 201);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/attendance/out-of-area/mine', (Request req) async {
    try {
      final u = await me(req);
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT * FROM out_of_area_requests WHERE user_id=@i::uuid ORDER BY submitted_at DESC LIMIT 20
      '''), parameters: {'i': (u['id'] as Object).toString()}));
      return json({
        'requests': [for (final row in rows) ooaJson(row.toColumnMap().map((k, v) => MapEntry(k.toString(), v)))]
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.get('/attendance/out-of-area/queue', (Request req) async {
    try {
      final actor = await me(req);
      if (actor['role'] != 'manager' && actor['role'] != 'superadmin') {
        throw const _Http(403, 'Hanya Manager dan Super Admin yang dapat memproses pengajuan.');
      }
      final rows = await db.pool.runTx((tx) => tx.execute(Sql.named('''
        SELECT o.*, u.username, u.full_name, u.role AS urel
        FROM out_of_area_requests o JOIN users u ON u.id=o.user_id
        WHERE o.status='pending' ORDER BY o.submitted_at
      ''')));
      final items = <Map<String, dynamic>>[];
      final selfApprove =
          actor['role'] == 'manager' || actor['role'] == 'superadmin';
      for (final row in rows) {
        final m = row.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        final isSelf =
            (m['username'] as String).toLowerCase() ==
            (actor['username'] as String).toLowerCase();
        // Manager/Super Admin melihat miliknya sendiri untuk disetujui
        // sendiri; staff tidak.
        if (isSelf && !selfApprove) continue;
        if (!isSelf &&
            !canManageRole(actor['role'] as String, (m['urel'] ?? 'staff') as String)) {
          continue;
        }
        items.add({
          'employee': {'username': m['username'], 'fullName': m['full_name']},
          'request': ooaJson(m),
        });
      }
      return json({'queue': items});
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/attendance/out-of-area/<id>/review', (Request req, String id) async {
    try {
      final actor = await me(req);
      final b = await readJson(req);
      final approve = b['approve'] == true;
      final note = ((b['note'] ?? '') as String).trim();
      if (!approve && note.length < 5) {
        throw const _Http(422, 'Catatan penolakan minimal 5 karakter.');
      }
      final done = await db.pool.runTx((tx) async {
        final cur = await tx.execute(Sql.named('''
          SELECT o.*, u.username, u.full_name AS efn, u.role AS urel FROM out_of_area_requests o
          JOIN users u ON u.id=o.user_id WHERE o.id=@i::uuid'''), parameters: {'i': id});
        if (cur.isEmpty) throw const _Http(404, 'Pengajuan tidak ditemukan.');
        final m = cur.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        if (m['status'] != 'pending') throw const _Http(400, 'Pengajuan sudah diproses.');
        final isSelf = (m['username'] as String).toLowerCase() ==
            (actor['username'] as String).toLowerCase();
        // Manager & Super Admin boleh menyetujui pengajuannya sendiri
        // (dinas luar); role lain tidak.
        if (isSelf &&
            actor['role'] != 'manager' &&
            actor['role'] != 'superadmin') {
          throw const _Http(403, 'Anda tidak dapat memproses pengajuan Anda sendiri.');
        }
        if (!isSelf &&
            !canManageRole(actor['role'] as String, (m['urel'] ?? 'staff') as String)) {
          throw const _Http(403, 'Anda tidak berhak memproses pengajuan ini.');
        }
        final upd = await tx.execute(Sql.named('''
          UPDATE out_of_area_requests SET status=@s, reviewed_by=@b, reviewed_at=now(), reviewer_note=@n
          WHERE id=@i::uuid RETURNING *
        '''), parameters: {
          's': approve ? 'approved' : 'rejected',
          'b': actor['full_name'],
          'n': note.isEmpty ? null : note,
          'i': id,
        });
        final rm = upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
        await notifyTx(tx, m['username'] as String,
            kind: approve ? 'outOfAreaApproved' : 'outOfAreaRejected',
            title: approve ? 'Pengajuan luar area disetujui' : 'Pengajuan luar area ditolak',
            body: approve
                ? 'Pengajuan luar area disetujui oleh ${actor['full_name']}.'
                : 'Pengajuan luar area ditolak oleh ${actor['full_name']}'
                    '${note.isEmpty ? '.' : ': "$note"'}');
        return {
          'employee': {'username': m['username'], 'fullName': m['efn']},
          'request': ooaJson(rm),
        };
      });
      return json(done);
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/attendance/out-of-area/<id>/cancel', (Request req, String id) async {
    try {
      final u = await me(req);
      final row = await db.pool.runTx((tx) async {
        final upd = await tx.execute(Sql.named('''
          UPDATE out_of_area_requests SET status='cancelled'
          WHERE id=@i::uuid AND user_id=@u::uuid AND status='pending' RETURNING *
        '''), parameters: {'i': id, 'u': (u['id'] as Object).toString()});
        if (upd.isEmpty) throw const _Http(404, 'Pengajuan tidak ditemukan atau sudah diproses.');
        return upd.first.toColumnMap().map((k, v) => MapEntry(k.toString(), v));
      });
      return json(ooaJson(row));
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  return r;
}
