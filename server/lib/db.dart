import 'package:postgres/postgres.dart';

/// Satu koneksi pool untuk seluruh handler.
class Db {
  Db(this.pool);
  final Pool pool;

  static Future<Db> open(String databaseUrl) async {
    final uri = Uri.parse(databaseUrl);
    final pool = Pool.withEndpoints(
      [
        Endpoint(
          host: uri.host,
          port: uri.hasPort ? uri.port : 5432,
          database: uri.pathSegments.isEmpty ? 'postgres' : uri.pathSegments.first,
          username: uri.userInfo.split(':').first,
          password: uri.userInfo.contains(':')
              ? uri.userInfo.split(':').sublist(1).join(':')
              : null,
        ),
      ],
      settings: const PoolSettings(sslMode: SslMode.disable),
    );
    return Db(pool);
  }

  Future<void> close() => pool.close();
}
