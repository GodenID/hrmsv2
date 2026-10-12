import 'dart:math';

import '../../core/utils/validators.dart';
import '../../core/utils/work_calendar.dart';
import '../auth_repository.dart';
import '../employee_repository.dart';
import '../notification_repository.dart';
import 'mock_store.dart';

/// Autentikasi palsu. Akun demo (password awal [MockStore.demoPassword]):
///   budi.santoso  | Staff       | NIK 3201123456780001
///   siti.rahma    | Manager       | NIK 3174015507920002
///   andi.pratama  | Super Admin | NIK 3273012304880003
///
/// Token sesi mock berisi username agar tetap bisa dipulihkan setelah web
/// di-refresh (data mock di memori ikut ter-reset). Ini HANYA untuk demo:
/// server sungguhan WAJIB memakai token acak yang tidak bisa ditebak,
/// disimpan & divalidasi di server, punya masa berlaku, dan dicabut saat
/// logout, ganti/reset password, atau akun dinonaktifkan.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository(
    this.store, {
    this.latency = const Duration(milliseconds: 800),
  });

  final MockStore store;
  final Duration latency;

  static const String _sessionPrefix = 'mock-session.';
  static final Random _random = Random.secure();

  /// Kebijakan keamanan (cermin kontrak API agar perilaku mock sama dengan
  /// server sungguhan):
  /// - sesi kedaluwarsa 30 hari sejak login (tidak lagi selamanya),
  /// - token reset password berlaku 30 menit dan sekali pakai,
  /// - 5x gagal login beruntun mengunci username itu selama 15 menit.
  static const Duration sessionTtl = Duration(days: 30);
  static const Duration resetTokenTtl = Duration(minutes: 30);
  static const int maxLoginAttempts = 5;
  static const Duration loginLockout = Duration(minutes: 15);

  /// Token reset -> pemilik + kedaluwarsa.
  final Map<String, _ResetToken> _resetTokens = {};

  /// Kegagalan login beruntun per username yang diketik (dinormalkan),
  /// untuk membatasi brute force. Semua ketikan dihitung agar laju
  /// percobaan tetap dibatasi.
  final Map<String, _LoginAttempts> _loginAttempts = {};

  /// Kegagalan verifikasi lupa-password (langkah 1 & 2) per username.
  /// Aturan sama dengan login: 5x gagal → kunci 15 menit.
  final Map<String, _LoginAttempts> _recoveryAttempts = {};

  /// Token yang sudah logout selama aplikasi berjalan.
  final Set<String> _revoked = {};

  /// Token per username (untuk mencabut sesi perangkat lain).
  final Map<String, Set<String>> _userTokens = {};

  static String _nonce() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  /// Waktu terbit disematkan di token agar kedaluwarsa bisa divalidasi
  /// tanpa penyimpanan sesi di server (token lama tanpa timestamp
  /// ditolak sebagai sesi berakhir).
  String _issueToken(String username, DateTime now) {
    return '$_sessionPrefix$username.${now.microsecondsSinceEpoch}.${_nonce()}';
  }

  /// null = format tidak dikenal → diperlakukan sebagai sesi berakhir.
  static _SessionToken? _parseSessionToken(String token) {
    if (!token.startsWith(_sessionPrefix)) return null;
    // Username boleh mengandung titik: dua segmen terakhir selalu
    // waktu-terbit (digit) + nonce (heksa tanpa titik).
    final parts = token.substring(_sessionPrefix.length).split('.');
    if (parts.length < 3) return null;
    final nonce = parts.removeLast();
    final issuedMicros = int.tryParse(parts.removeLast());
    final username = parts.join('.');
    if (nonce.isEmpty || issuedMicros == null || username.isEmpty) {
      return null;
    }
    return _SessionToken(
      username,
      DateTime.fromMicrosecondsSinceEpoch(issuedMicros),
    );
  }

  /// Mencatat satu kegagalan login lalu selalu melempar: pesan kunci bila
  /// sudah mencapai batas, selain itu [message].
  static Never _failAttempt(
    _LoginAttempts attempts,
    DateTime now,
    String message,
  ) {
    attempts.failures++;
    attempts.lockedUntil = null;
    if (attempts.failures >= maxLoginAttempts) {
      final until = now.add(loginLockout);
      attempts.lockedUntil = until;
      throw AuthException(_lockoutMessage(until, now, 'percobaan masuk'));
    }
    throw AuthException(message);
  }

  static String _lockoutMessage(
    DateTime lockedUntil,
    DateTime now,
    String what,
  ) {
    final minutes = ((lockedUntil.difference(now).inSeconds + 59) ~/ 60)
        .clamp(1, 1 << 30);
    return 'Terlalu banyak $what yang gagal. Silakan mencoba '
        'lagi dalam $minutes menit.';
  }

  /// Mencatat satu kegagalan; melempar pesan kunci bila mencapai batas.
  /// Selain itu kembali normal agar pemanggil melempar pesan spesifiknya.
  static void _countFailure(
    _LoginAttempts attempts,
    DateTime now,
    String what,
  ) {
    attempts.failures++;
    attempts.lockedUntil = null;
    if (attempts.failures >= maxLoginAttempts) {
      final until = now.add(loginLockout);
      attempts.lockedUntil = until;
      throw AuthException(_lockoutMessage(until, now, what));
    }
  }

  static void _throwIfRecoveryLocked(
    Map<String, _LoginAttempts> attempts,
    String name,
    DateTime now,
  ) {
    final lockedUntil = attempts[name]?.lockedUntil;
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      throw AuthException(_lockoutMessage(lockedUntil, now, 'verifikasi'));
    }
  }

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    await Future<void>.delayed(latency);
    final name = username.trim().toLowerCase();
    final now = store.now();
    final attempts = _loginAttempts.putIfAbsent(name, _LoginAttempts.new);
    final lockedUntil = attempts.lockedUntil;
    if (lockedUntil != null && now.isBefore(lockedUntil)) {
      throw AuthException(_lockoutMessage(lockedUntil, now, 'percobaan masuk'));
    }
    final account = store.account(name);
    if (account == null) {
      _failAttempt(
        attempts,
        now,
        'Username tidak ditemukan. Pastikan penulisan sudah benar, atau '
        'daftar akun bila Anda belum memilikinya.',
      );
    }
    if (account.password != password) {
      _failAttempt(
        attempts,
        now,
        'Password salah. Silakan coba lagi atau gunakan "Lupa password?" '
        'untuk mengatur ulang.',
      );
    }
    // Kredensial benar: hitungan gagal dihapus.
    _loginAttempts.remove(name);
    // Status dicek setelah password agar tidak membocorkan status akun.
    if (!account.active) {
      throw const AuthException(
        'Akun Anda sudah dinonaktifkan. Hubungi Tim HR bila ini keliru.',
      );
    }
    final token = _issueToken(account.username, now);
    _userTokens.putIfAbsent(account.username, () => {}).add(token);
    return AuthSession(token: token, user: account.toUser());
  }

  @override
  Future<AuthUser> restoreSession(String token) async {
    await Future<void>.delayed(latency ~/ 2);
    final parsed = _parseSessionToken(token);
    if (parsed == null || _revoked.contains(token)) {
      throw const AuthException('Sesi berakhir. Silakan masuk kembali.');
    }
    final account = store.account(parsed.username);
    if (account == null) {
      throw const AuthException('Sesi berakhir. Silakan masuk kembali.');
    }
    // Sesi tidak abadi: kedaluwarsa 30 hari sejak login.
    if (store.now().difference(parsed.issuedAt) > sessionTtl) {
      throw const AuthException('Sesi berakhir. Silakan masuk kembali.');
    }
    if (!account.active) {
      throw const AuthException(
        'Akun Anda sudah dinonaktifkan. Hubungi Tim HR bila ini keliru.',
      );
    }
    return account.toUser();
  }

  @override
  Future<void> logout(String token) async {
    await Future<void>.delayed(latency ~/ 4);
    _revoked.add(token);
    for (final tokens in _userTokens.values) {
      tokens.remove(token);
    }
  }

  @override
  Future<void> logoutOthers(AuthUser user, {required String currentToken}) async {
    await Future<void>.delayed(latency ~/ 4);
    final tokens = _userTokens[user.username] ?? const <String>{};
    for (final t in tokens) {
      if (t != currentToken) _revoked.add(t);
    }
    _userTokens[user.username] = {currentToken};
  }

  @override
  Future<void> verifyUsername(String username) async {
    await Future<void>.delayed(latency);
    final name = username.trim().toLowerCase();
    final now = store.now();
    _throwIfRecoveryLocked(_recoveryAttempts, name, now);
    final account = store.account(name);
    if (account == null) {
      _countFailure(
        _recoveryAttempts.putIfAbsent(name, _LoginAttempts.new),
        now,
        'verifikasi',
      );
      throw const AuthException(
        'Username tidak ditemukan. Pastikan penulisan sudah benar atau hubungi Tim HR.',
      );
    }
    if (!account.active) {
      _countFailure(
        _recoveryAttempts.putIfAbsent(name, _LoginAttempts.new),
        now,
        'verifikasi',
      );
      throw const AuthException(
        'Akun ini sudah dinonaktifkan. Hubungi Tim HR.',
      );
    }
    _recoveryAttempts.remove(name);
  }

  @override
  Future<String> verifyNik({
    required String username,
    required String nik,
  }) async {
    await Future<void>.delayed(latency);
    final name = username.trim().toLowerCase();
    final now = store.now();
    _throwIfRecoveryLocked(_recoveryAttempts, name, now);
    final account = store.account(name);
    if (account == null || !account.active) {
      throw const AuthException(
        'Sesi verifikasi tidak valid. Silakan ulangi dari langkah pertama.',
      );
    }
    if (account.nik != nik.trim()) {
      _countFailure(
        _recoveryAttempts.putIfAbsent(name, _LoginAttempts.new),
        now,
        'verifikasi',
      );
      throw const AuthException(
        'NIK tidak sesuai dengan data karyawan untuk username ini.',
      );
    }
    _recoveryAttempts.remove(name);
    // Permintaan baru menggugurkan token sebelumnya milik akun ini.
    // Nonce acak (bukan jam dinding) agar dua permintaan berurutan tidak
    // pernah menghasilkan token yang sama.
    _resetTokens.removeWhere((_, t) => t.username == account.username);
    final token = 'mock-reset-${_nonce()}';
    _resetTokens[token] = _ResetToken(
      account.username,
      store.now().add(resetTokenTtl),
    );
    return token;
  }

  @override
  Future<void> resetPassword({
    required String resetToken,
    required String newPassword,
  }) async {
    await Future<void>.delayed(latency);
    final entry = _resetTokens[resetToken];
    // Token tidak dikenal, kedaluwarsa, atau sudah dipakai: alur diulang
    // dari awal. Pesan sengaja sama agar tidak membocorkan status token.
    if (entry == null || !store.now().isBefore(entry.expiresAt)) {
      _resetTokens.remove(resetToken);
      throw const AuthException(
        'Sesi atur ulang password sudah berakhir. Silakan ulangi dari awal.',
      );
    }
    final account = store.account(entry.username);
    if (account == null || !account.active) {
      throw const AuthException(
        'Sesi atur ulang password sudah berakhir. Silakan ulangi dari awal.',
      );
    }
    if (!(passwordStrength(newPassword, username: account.username) >=
        Validators.minimumPasswordStrength)) {
      throw const AuthException(
        'Password terlalu lemah. Buat password yang lebih kuat.',
      );
    }
    if (account.password == newPassword) {
      throw const AuthException(
        'Password baru tidak boleh sama dengan password lama.',
      );
    }
    account.password = newPassword;
    // Token sekali pakai: gugurkan semua token reset milik akun ini.
    _resetTokens.removeWhere((_, t) => t.username == account.username);
  }

  // ---------------------------------------------------------------------------
  // Pendaftaran mandiri
  // ---------------------------------------------------------------------------

  static void _check(String? error, RegistrationField field) {
    if (error != null) throw RegistrationException(error, field: field);
  }

  /// Saran username yang masih kosong, mis. "budi.santoso2".
  String? _suggestUsername(String taken) {
    for (var i = 2; i < 100; i++) {
      final suffix = '$i';
      final base = taken.length + suffix.length > 30
          ? taken.substring(0, 30 - suffix.length)
          : taken;
      final candidate = '$base$suffix';
      if (store.account(candidate) == null) return candidate;
    }
    return null;
  }

  void _requireUsernameAvailable(String name) {
    _requireRegistrationOpen();
    _check(EmployeeRules.validateUsername(name), RegistrationField.username);
    if (store.account(name) != null) {
      final suggestion = _suggestUsername(name);
      throw RegistrationException(
        suggestion == null
            ? 'Username "$name" sudah dipakai. Pilih username lain.'
            : 'Username "$name" sudah dipakai. Coba yang lain, '
                  'mis. $suggestion.',
        field: RegistrationField.username,
      );
    }
  }

  @override
  Future<bool> isRegistrationOpen() async {
    await Future<void>.delayed(latency ~/ 4);
    return store.registrationOpen;
  }

  void _requireRegistrationOpen() {
    if (!store.registrationOpen) {
      throw const RegistrationException(
        'Pendaftaran akun sedang ditutup. Hubungi Tim HR bila Anda belum '
        'memiliki akun.',
      );
    }
  }

  @override
  Future<void> checkUsernameAvailable(String username) async {
    await Future<void>.delayed(latency ~/ 2);
    _requireUsernameAvailable(username.trim().toLowerCase());
  }

  @override
  Future<RegisteredAccount> register(RegistrationDraft d) async {
    await Future<void>.delayed(latency);
    final name = d.username.trim().toLowerCase();

    // Validasi ulang semua data (meniru server).
    _requireUsernameAvailable(name);
    if (!(passwordStrength(d.password, username: name) >=
        Validators.minimumPasswordStrength)) {
      throw const RegistrationException(
        'Password terlalu lemah. Buat password yang lebih kuat.',
        field: RegistrationField.password,
      );
    }
    _check(
      EmployeeRules.validateFullName(d.fullName),
      RegistrationField.fullName,
    );
    _check(EmployeeRules.validateNik(d.nik), RegistrationField.nik);
    _check(
      RegistrationRules.validateBirthPlace(d.birthPlace),
      RegistrationField.birthPlace,
    );
    _check(
      RegistrationRules.validateBirthDate(d.birthDate, now: store.now()),
      RegistrationField.birthDate,
    );
    final birthMismatch = RegistrationRules.birthDateMismatch(
      d.birthDate,
      d.nik.trim(),
      d.gender,
      now: store.now(),
    );
    if (birthMismatch != null) {
      throw RegistrationException(
        birthMismatch,
        field: RegistrationField.birthDate,
      );
    }
    if (!d.privacyConsent) {
      throw const RegistrationException(
        'Centang persetujuan pemrosesan data pribadi untuk melanjutkan '
        'pendaftaran.',
      );
    }
    _check(
      RegistrationRules.validateAddress(d.address),
      RegistrationField.address,
    );
    _check(EmployeeRules.validateEmail(d.email), RegistrationField.email);
    _check(EmployeeRules.validatePhone(d.phone), RegistrationField.phone);
    final ec = d.emergencyContact;
    _check(
      RegistrationRules.validateEmergencyName(ec.name) ??
          EmployeeRules.validatePhone(ec.phone) ??
          RegistrationRules.emergencyPhoneConflict(ec.phone, d.phone),
      RegistrationField.emergencyContact,
    );

    _check(
      RegistrationRules.validateContractMonths(
        d.contractMonths?.toString(),
        d.employmentStatus,
      ),
      RegistrationField.employmentStatus,
    );

    // Pesan sengaja tidak menyebut nama pemilik data (endpoint publik).
    final nik = d.nik.trim();
    final email = d.email.trim().toLowerCase();
    final phoneCanon = PhoneNumbers.canonical(d.phone.trim());
    for (final other in store.accounts.values) {
      if (other.nik == nik) {
        throw const RegistrationException(
          'NIK ini sudah terdaftar. Bila Anda sudah punya akun, gunakan '
          '"Lupa password" di halaman masuk atau hubungi Tim HR.',
          field: RegistrationField.nik,
        );
      }
      if (other.email.toLowerCase() == email) {
        throw const RegistrationException(
          'Email ini sudah dipakai akun lain. Gunakan email lain.',
          field: RegistrationField.email,
        );
      }
      // Nomor dibandingkan setelah dirapikan agar +62/62/0 dianggap sama.
      if (phoneCanon.isNotEmpty &&
          PhoneNumbers.canonical(other.phone) == phoneCanon) {
        throw const RegistrationException(
          'Nomor HP ini sudah dipakai akun lain. Gunakan nomor lain, atau '
          'hubungi Tim HR bila ini nomor Anda.',
          field: RegistrationField.phone,
        );
      }
    }

    final account = MockAccount(
      username: name,
      fullName: d.fullName.trim(),
      // Selalu Staff. Hanya Super Admin yang dapat mengubahnya nanti.
      role: UserRole.staff,
      nik: nik,
      employeeId: store.nextEmployeeId(),
      // Jabatan & tanggal bergabung awal; dilengkapi Tim HR.
      position: 'Staf',
      division: d.division,
      employmentStatus: d.employmentStatus,
      contractMonths: d.contractMonths,
      joinDate: WorkCalendar.dateOnly(store.now()),
      email: email,
      phone: d.phone.trim(),
      password: d.password,
      gender: d.gender,
      birthPlace: d.birthPlace.trim(),
      birthDate: WorkCalendar.dateOnly(d.birthDate),
      address: d.address.trim(),
      privacyConsentedAt: store.now(),
      emergencyContact: EmergencyContact(
        name: ec.name.trim(),
        relation: ec.relation,
        phone: ec.phone.trim(),
      ),
    );
    store.accounts[name] = account;
    store.employeeChanges.ping();

    for (final manager in store.accounts.values) {
      if (manager.active && manager.role.canManageEmployees) {
        store.notify(
          manager.username,
          kind: NotificationKind.accountRegistered,
          title: 'Akun karyawan baru',
          body:
              '${account.fullName} mendaftar sebagai Staff di divisi '
              '${d.division.label}. Periksa & lengkapi datanya di menu '
              'Karyawan.',
        );
      }
    }

    return RegisteredAccount(
      username: account.username,
      fullName: account.fullName,
      role: account.role,
      division: d.division,
      employmentStatus: d.employmentStatus,
      contractMonths: d.contractMonths,
    );
  }
}

/// Token sesi yang berhasil diurai: pemilik + waktu terbit.
class _SessionToken {
  const _SessionToken(this.username, this.issuedAt);

  final String username;
  final DateTime issuedAt;
}

/// Token reset password: pemilik + batas berlaku.
class _ResetToken {
  const _ResetToken(this.username, this.expiresAt);

  final String username;
  final DateTime expiresAt;
}

/// Kegagalan login beruntun + sampai kapan dikunci (null = tidak dikunci).
class _LoginAttempts {
  int failures = 0;
  DateTime? lockedUntil;
}
