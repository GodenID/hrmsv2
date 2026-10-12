import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/auth_repository.dart';
import 'package:hrms_app/data/mock/mock_auth_repository.dart';
import 'package:hrms_app/data/mock/mock_profile_repository.dart';
import 'package:hrms_app/data/mock/mock_store.dart';

/// Kebijakan keamanan auth: rate limit login, umur sesi, dan umur token
/// reset password. Jam bisa dimajukan lewat [now] karena MockStore memakai
/// jam injeksi.
void main() {
  late DateTime now;
  late MockStore store;
  late MockAuthRepository auth;

  const username = 'budi.santoso';
  const nik = '3201123456780001';

  setUp(() {
    now = DateTime(2026, 10, 9, 8);
    store = MockStore(clock: () => now);
    auth = MockAuthRepository(store, latency: Duration.zero);
  });

  Matcher authError(String part) => throwsA(
    isA<AuthException>().having((e) => e.message, 'message', contains(part)),
  );

  /// Password salah untuk username yang ada.
  Future<void> wrongPassword() => expectLater(
    auth.login(username: username, password: 'salah'),
    authError('Password salah'),
  );

  /// Username yang tidak terdaftar.
  Future<void> unknownUser() => expectLater(
    auth.login(username: 'tidak.ada', password: 'salah'),
    authError('tidak ditemukan'),
  );

  group('pesan login', () {
    test('username tak dikenal vs password salah dibedakan', () async {
      await unknownUser();
      await wrongPassword();
    });
  });

  group('rate limit login', () {
    test('5x gagal → dikunci 15 menit, lalu pulih sendiri', () async {
      for (var i = 0; i < 4; i++) {
        await wrongPassword();
      }
      // Kegagalan ke-5 langsung mengunci.
      await expectLater(
        auth.login(username: username, password: 'salah'),
        authError('15 menit'),
      );
      // Percobaan ke-6 — bahkan dengan password benar — tetap ditolak.
      await expectLater(
        auth.login(username: username, password: MockStore.demoPassword),
        authError('menit'),
      );
      // Maju 16 menit: kunci terbuka, login berhasil.
      now = now.add(const Duration(minutes: 16));
      final session = await auth.login(
        username: username,
        password: MockStore.demoPassword,
      );
      expect(session.user.username, username);
    });

    test('login berhasil mereset hitungan gagal', () async {
      for (var i = 0; i < 4; i++) {
        await wrongPassword();
      }
      await auth.login(
        username: username,
        password: MockStore.demoPassword,
      );
      // Hitungan mulai dari nol lagi: 4x gagal belum dikunci.
      for (var i = 0; i < 4; i++) {
        await wrongPassword();
      }
      // Kegagalan ke-5 setelah reset → dikunci.
      await expectLater(
        auth.login(username: username, password: 'salah'),
        authError('menit'),
      );
    });

    test('username asing tetap dihitung untuk rate limit', () async {
      for (var i = 0; i < 4; i++) {
        await unknownUser();
      }
      await expectLater(
        auth.login(username: 'tidak.ada', password: 'salah'),
        authError('menit'),
      );
    });
  });

  group('konsistensi kekuatan password', () {
    test('reset menolak password lemah', () async {
      final token = await auth.verifyNik(username: username, nik: nik);
      await expectLater(
        auth.resetPassword(resetToken: token, newPassword: 'lemah123'),
        authError('terlalu lemah'),
      );
    });

    test('ganti password menolak password lemah', () async {
      final profile = MockProfileRepository(store, latency: Duration.zero);
      const user = AuthUser(
        username: username,
        fullName: 'Budi Santoso',
        role: UserRole.staff,
      );
      // changePassword berjenis AppException (sesuai kontrak halamannya).
      await expectLater(
        profile.changePassword(
          user,
          currentPassword: MockStore.demoPassword,
          newPassword: 'lemah123',
        ),
        throwsA(
          isA<AppException>().having(
            (e) => e.message,
            'message',
            contains('terlalu lemah'),
          ),
        ),
      );
      // Password yang memenuhi mistar bisa dipakai dan bisa untuk masuk.
      await profile.changePassword(
        user,
        currentPassword: MockStore.demoPassword,
        newPassword: 'KuatBaru1',
      );
      final session = await auth.login(
        username: username,
        password: 'KuatBaru1',
      );
      expect(session.user.username, username);
    });
  });

  group('rate limit lupa password', () {
    test('5x NIK salah → dikunci 15 menit, lalu pulih', () async {
      for (var i = 0; i < 4; i++) {
        await expectLater(
          auth.verifyNik(username: username, nik: '0000000000000000'),
          authError('tidak sesuai'),
        );
      }
      await expectLater(
        auth.verifyNik(username: username, nik: '0000000000000000'),
        authError('15 menit'),
      );
      now = now.add(const Duration(minutes: 16));
      final token = await auth.verifyNik(username: username, nik: nik);
      expect(token, isNotEmpty);
    });

    test('username asing ikut dihitung', () async {
      for (var i = 0; i < 4; i++) {
        await expectLater(
          auth.verifyUsername('tidak.ada'),
          authError('tidak ditemukan'),
        );
      }
      await expectLater(
        auth.verifyUsername('tidak.ada'),
        authError('menit'),
      );
    });
  });

  group('keluar perangkat lain', () {
    test('mencabut sesi lain, sesi ini tetap hidup', () async {
      final first = await auth.login(
        username: username,
        password: MockStore.demoPassword,
      );
      final second = await auth.login(
        username: username,
        password: MockStore.demoPassword,
      );
      expect(first.token, isNot(equals(second.token)));
      final user = await auth.restoreSession(first.token);
      await auth.logoutOthers(user, currentToken: first.token);
      expect(
        (await auth.restoreSession(first.token)).username,
        username,
      );
      await expectLater(
        auth.restoreSession(second.token),
        authError('Sesi berakhir'),
      );
    });
  });

  group('umur sesi', () {
    test('sesi hidup 30 hari, lewat dari itu wajib login ulang', () async {
      final session = await auth.login(
        username: username,
        password: MockStore.demoPassword,
      );
      now = now.add(const Duration(days: 29));
      expect(
        (await auth.restoreSession(session.token)).username,
        username,
      );
      now = now.add(const Duration(days: 2)); // total 31 hari
      await expectLater(
        auth.restoreSession(session.token),
        authError('Sesi berakhir'),
      );
    });

    test('logout mencabut sesi seketika', () async {
      final session = await auth.login(
        username: username,
        password: MockStore.demoPassword,
      );
      await auth.logout(session.token);
      await expectLater(
        auth.restoreSession(session.token),
        authError('Sesi berakhir'),
      );
    });
  });

  group('token reset password', () {
    test('kedaluwarsa 30 menit', () async {
      final token = await auth.verifyNik(username: username, nik: nik);
      now = now.add(const Duration(minutes: 31));
      await expectLater(
        auth.resetPassword(resetToken: token, newPassword: 'Baru@1234'),
        authError('sudah berakhir'),
      );
    });

    test('sekali pakai; permintaan baru menggugurkan yang lama', () async {
      final first = await auth.verifyNik(username: username, nik: nik);
      final second = await auth.verifyNik(username: username, nik: nik);
      await expectLater(
        auth.resetPassword(resetToken: first, newPassword: 'Baru@1234'),
        authError('sudah berakhir'),
      );
      await auth.resetPassword(resetToken: second, newPassword: 'Baru@1234');
      // Token yang sudah dipakai tidak bisa dipakai lagi.
      await expectLater(
        auth.resetPassword(resetToken: second, newPassword: 'Lain@1234'),
        authError('sudah berakhir'),
      );
      // Password baru bisa dipakai masuk.
      final session = await auth.login(
        username: username,
        password: 'Baru@1234',
      );
      expect(session.user.username, username);
    });
  });
}
