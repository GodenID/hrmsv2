import 'dart:io';

class Config {
  Config.fromEnv(Map<String, String> env)
      : port = int.tryParse(env['PORT'] ?? '8080') ?? 8080,
        databaseUrl = env['DATABASE_URL'] ?? '',
        jwtSecret = env['JWT_SECRET'] ?? '',
        runMigrations = (env['RUN_MIGRATIONS'] ?? 'false').toLowerCase() == 'true',
        s3endpoint = env['S3_ENDPOINT'] ?? '',
        s3bucket = env['S3_BUCKET'] ?? '',
        s3region = env['S3_REGION'] ?? 'ap-southeast-1',
        s3accessKey = env['S3_ACCESS_KEY'] ?? '',
        s3secretKey = env['S3_SECRET_KEY'] ?? '',
        s3pathStyle =
            (env['S3_PATH_STYLE'] ?? 'false').toLowerCase() == 'true',
        s3avatarPublic =
            (env['S3_AVATAR_PUBLIC'] ?? 'true').toLowerCase() == 'true';

  final int port;
  final String databaseUrl;
  final String jwtSecret;
  final bool runMigrations;

  // Objek penyimpanan S3-compatible (Onidel). Kosong = upload file mati,
  // lampiran hanya metadata (mode pengembangan).
  final String s3endpoint;
  final String s3bucket;
  final String s3region;
  final String s3accessKey;
  final String s3secretKey;
  final bool s3pathStyle;
  final bool s3avatarPublic;

  bool get s3enabled =>
      s3endpoint.isNotEmpty &&
      s3bucket.isNotEmpty &&
      s3accessKey.isNotEmpty &&
      s3secretKey.isNotEmpty;

  void validate() {
    if (databaseUrl.isEmpty) {
      stderr.writeln('DATABASE_URL wajib diisi.');
      exit(1);
    }
    if (jwtSecret.length < 32) {
      stderr.writeln('JWT_SECRET minimal 32 karakter.');
      exit(1);
    }
  }
}
