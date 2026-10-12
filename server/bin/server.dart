import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

import 'package:prasasti_server/announcement_handlers.dart';
import 'package:prasasti_server/attendance_handlers.dart';
import 'package:prasasti_server/auth_handlers.dart';
import 'package:prasasti_server/event_handlers.dart';
import 'package:prasasti_server/leave_handlers.dart';
import 'package:prasasti_server/notify.dart' show PushBus;
import 'package:prasasti_server/upload_handlers.dart';
import 'package:prasasti_server/warning_handlers.dart';
import 'package:prasasti_server/config.dart';
import 'package:prasasti_server/db.dart';
import 'package:prasasti_server/fcm.dart';
import 'package:prasasti_server/employee_handlers.dart';

Future<void> runMigrations(Db db) async {
  final dir = Directory('migrations');
  if (!await dir.exists()) return;
  final files = (await dir.list().toList())
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    var sql = await f.readAsString();
    // Buang baris komentar DULU (sebelum pecah ';') — komentar bisa
    // mengandung ';' (mis. "(dibaca via API; push/FCM)") yang akan
    // memenggal statement bila dipecah lebih dulu.
    sql = sql
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('--'))
        .join('\n');
    // postgres driver menolak multi-statement per query: pecah per ';'.
    // (Migrasi kita hanya DDL sederhana, tanpa fungsi/trigger ber-semicolon.)
    final statements = sql
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    await db.pool.runTx((tx) async {
      for (final s in statements) {
        await tx.execute(s);
      }
    });
    stdout.writeln('migrated: ${f.path} (${statements.length} statements)');
  }
}

Future<void> main() async {
  final cfg = Config.fromEnv(Platform.environment)..validate();
  final db = await Db.open(cfg.databaseUrl);
  PushBus.configure(database: db, sender: FcmSender(cfg));
  if (cfg.runMigrations) await runMigrations(db);

  final auth = authRouter(db, cfg);
  final emp = employeeRouter(db, cfg);
  final att = attendanceRouter(db, cfg);
  final leave = leaveRouter(db, cfg);
  final ot = overtimeRouter(db, cfg);
  final notif = notificationRouter(db, cfg);
  final up = uploadRouter(db, cfg);
  final ann = announcementRouter(db, cfg);
  final ev = eventRouter(db, cfg);
  final warn = warningRouter(db, cfg);
  final app = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler((Request req) {
    final p = req.url.path;
    if (p.startsWith('employees') || p.startsWith('settings/')) {
      return emp.call(req);
    }
    if (p.startsWith('attendance')) return att.call(req);
    if (p.startsWith('leave')) return leave.call(req);
    if (p.startsWith('overtime')) return ot.call(req);
    if (p.startsWith('notifications')) return notif.call(req);
    if (p.startsWith('users/me/')) return notif.call(req);
    if (p.startsWith('uploads/') || p.startsWith('profile')) return up.call(req);
    if (p.startsWith('announcements')) return ann.call(req);
    if (p.startsWith('events')) return ev.call(req);
    if (p.startsWith('warnings')) return warn.call(req);
    return auth.call(req);
  });

  final server = await io.serve(app, InternetAddress.anyIPv4, cfg.port);
  stdout.writeln('prasasti_server on :${server.port}');
}
