import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'authz.dart';
import 'config.dart';
import 'db.dart';
import 's3.dart';
import 'upload_handlers.dart' show json, readJson;

class _Http implements Exception {
  const _Http(this.status, this.message);
  final int status;
  final String message;
}

/// Rilis aplikasi Android.
///
/// - `GET /app/version` publik: dipanggil aplikasi saat dibuka untuk
///   memutuskan perlu unduh atau tidak. Tanpa auth karena pembaruan harus
///   tetap bisa jalan sebelum pengguna berhasil masuk.
/// - `GET/POST /app/releases` superadmin: riwayat + terbitkan versi baru.
Router appRouter(Db db, Config cfg) {
  final r = Router();

  Future<Map<String, dynamic>> me(Request req) async {
    final u = await authedUser(req, db, cfg);
    if (u == null) {
      throw const _Http(401, 'Sesi berakhir. Silakan masuk kembali.');
    }
    if (u['role'] != 'superadmin') {
      throw const _Http(403, 'Hanya Super Admin yang dapat mengelola rilis.');
    }
    return u;
  }

  Map<String, dynamic> releaseJson(Map<String, dynamic> m) => {
    'versionCode': (m['version_code'] as num).toInt(),
    'versionName': (m['version_name'] ?? '').toString(),
    'minVersionCode': (m['min_version_code'] as num).toInt(),
    'sha256': (m['sha256'] ?? '').toString(),
    'sizeBytes': (m['size_bytes'] as num).toInt(),
    'notes': (m['notes'] ?? '').toString(),
    'publishedBy': m['published_by']?.toString(),
    'publishedAt': (m['published_at'] as DateTime?)?.toUtc().toIso8601String(),
  };

  // ---------- dibaca aplikasi (tanpa auth) ----------
  r.get('/app/version', (Request req) async {
    final s3 = storeOf(cfg);
    if (s3 == null) {
      // Tanpa penyimpanan objek tidak ada APK yang bisa diunduh. Aplikasi
      // memperlakukan ini sebagai "tidak ada pembaruan".
      return json({'available': false});
    }
    try {
      final rows = await db.pool.runTx(
        (tx) => tx.execute(
          Sql.named('''
        SELECT version_code, version_name, min_version_code, apk_key, sha256,
               size_bytes, notes, published_at
        FROM app_releases
        ORDER BY version_code DESC
        LIMIT 1
      '''),
        ),
      );
      if (rows.isEmpty) return json({'available': false});
      final m = rows.first.toColumnMap().map(
        (k, v) => MapEntry(k.toString(), v),
      );
      final key = (m['apk_key'] ?? '').toString();
      if (key.isEmpty) return json({'available': false});
      return json({
        'available': true,
        ...releaseJson(m),
        // 1 jam cukup untuk unduhan ±100 MB; URL baru dibuat tiap cek.
        'apkUrl': s3.presignGet(key, expiresSeconds: 3600),
        'expiresIn': 3600,
      });
    } catch (_) {
      return json({'available': false});
    }
  });

  // ---------- kelola rilis ----------
  r.get('/app/releases', (Request req) async {
    try {
      await me(req);
      final rows = await db.pool.runTx(
        (tx) => tx.execute(
          Sql.named('''
        SELECT version_code, version_name, min_version_code, sha256,
               size_bytes, notes, published_by, published_at
        FROM app_releases
        ORDER BY version_code DESC
      '''),
        ),
      );
      return json({
        'releases': [
          for (final row in rows)
            releaseJson(
              row.toColumnMap().map((k, v) => MapEntry(k.toString(), v)),
            ),
        ],
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  r.post('/app/releases', (Request req) async {
    try {
      final u = await me(req);
      final s3 = storeOf(cfg);
      if (s3 == null) {
        throw const _Http(503, 'Penyimpanan file belum dikonfigurasi.');
      }
      final b = await readJson(req);
      final versionCode = (b['versionCode'] as num?)?.toInt() ?? 0;
      final versionName = ((b['versionName'] ?? '') as Object)
          .toString()
          .trim();
      final minVersionCode = (b['minVersionCode'] as num?)?.toInt() ?? 0;
      final apkKey = ((b['apkKey'] ?? '') as Object).toString().trim();
      final sha256 = ((b['sha256'] ?? '') as Object)
          .toString()
          .trim()
          .toLowerCase();
      final notes = ((b['notes'] ?? '') as Object).toString().trim();

      if (versionCode <= 0) {
        throw const _Http(422, 'versionCode harus bilangan bulat positif.');
      }
      if (versionName.isEmpty || versionName.length > 20) {
        throw const _Http(
          422,
          'versionName wajib diisi (maksimal 20 karakter).',
        );
      }
      if (minVersionCode < 0 || minVersionCode > versionCode) {
        throw const _Http(
          422,
          'minVersionCode harus antara 0 dan versionCode.',
        );
      }
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
        throw const _Http(422, 'sha256 harus 64 karakter heksadesimal.');
      }
      if (notes.length > 1000) {
        throw const _Http(422, 'Catatan rilis maksimal 1000 karakter.');
      }
      if (!apkKey.startsWith('releases/') || !apkKey.endsWith('.apk')) {
        throw const _Http(422, 'Key APK tidak valid.');
      }

      final size = await s3.sizeOf(apkKey);
      if (size == null) {
        throw const _Http(
          422,
          'APK tidak ditemukan di penyimpanan. Unggah ulang.',
        );
      }

      final maxRows = await db.pool.runTx(
        (tx) => tx.execute(
          Sql.named(
            'SELECT COALESCE(MAX(version_code), 0) AS v FROM app_releases',
          ),
        ),
      );
      final highest = ((maxRows.first.toColumnMap()['v'] as num?) ?? 0).toInt();
      if (versionCode <= highest) {
        throw _Http(
          409,
          'versionCode harus lebih besar dari versi terbit ($highest).',
        );
      }

      await db.pool.runTx(
        (tx) => tx.execute(
          Sql.named('''
        INSERT INTO app_releases(
          version_code, version_name, min_version_code, apk_key, sha256,
          size_bytes, notes, published_by
        ) VALUES (
          @vc, @vn, @mv, @k, @sh, @sz, @n, @by
        )
      '''),
          parameters: {
            'vc': versionCode,
            'vn': versionName,
            'mv': minVersionCode,
            'k': apkKey,
            'sh': sha256,
            'sz': size,
            'n': notes,
            'by': (u['username'] ?? '').toString(),
          },
        ),
      );

      return json({
        'ok': true,
        'versionCode': versionCode,
        'versionName': versionName,
        'sizeBytes': size,
      });
    } on _Http catch (h) {
      return json({'message': h.message}, status: h.status);
    }
  });

  return r;
}
