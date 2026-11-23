import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:prasasti_server/tokens.dart';
import 'package:test/test.dart';

void main() {
  const secret = 'rahasia-panjang-untuk-pengujian-token-1234567890';

  group('verifyJwt', () {
    test('menerima token yang diterbitkan aplikasi', () {
      final token = issueJwt(
        secret: secret,
        userId: 'user-1',
        username: 'goden',
        role: 'superadmin',
        jti: 'jti-1',
      );
      expect(verifyJwt(token, secret), isNotNull);
    });

    test('menerima token lama yang klaim exp-nya sudah lewat', () {
      final expired = JWT(
        {'role': 'staff', 'username': 'lama'},
        subject: 'user-2',
        jwtId: 'jti-2',
      ).sign(SecretKey(secret), expiresIn: const Duration(seconds: -10));
      expect(verifyJwt(expired, secret), isNotNull);
    });

    test('tetap menolak tanda tangan palsu', () {
      final token = issueJwt(
        secret: secret,
        userId: 'user-3',
        username: 'goden',
        role: 'superadmin',
        jti: 'jti-3',
      );
      expect(verifyJwt('${token}x', secret), isNull);
    });
  });
}
