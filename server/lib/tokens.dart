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
  return jwt.sign(SecretKey(secret), expiresIn: const Duration(days: 30));
}

JWT? verifyJwt(String token, String secret) {
  try {
    return JWT.verify(token, SecretKey(secret));
  } catch (_) {
    return null;
  }
}

String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();
