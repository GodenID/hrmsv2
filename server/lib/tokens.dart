import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newJti() => _uuid.v4();

String issueJwt({
  required String secret,
  required String userId,
  required String username,
  required String role,
  required String jti,
}) {
  final jwt = JWT(
    {'role': role, 'username': username},
    subject: userId,
    jwtId: jti,
  );
  // Tanpa klaim exp: sesi tidak kedaluwarsa sendiri. Masa berlaku dipegang
  // baris `sessions` di DB, yang dicabut hanya saat logout/reset/admin.
  return jwt.sign(SecretKey(secret));
}

JWT? verifyJwt(String token, String secret) {
  try {
    // Token lama masih punya exp 30 hari. Lewati pengecekan exp agar sesi
    // yang sudah berjalan tidak terputus setelah perbaikan ini.
    return JWT.verify(token, SecretKey(secret), checkExpiresIn: false);
  } catch (_) {
    return null;
  }
}

String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();
