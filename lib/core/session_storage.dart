import 'package:shared_preferences/shared_preferences.dart';

/// Tempat menyimpan token sesi di perangkat, agar pengguna tetap masuk
/// setelah aplikasi dibuka ulang / web di-refresh.
abstract class SessionStorage {
  Future<String?> readToken();

  Future<void> writeToken(String token);

  Future<void> clear();
}

/// Disimpan lewat shared_preferences (web: localStorage).
///
/// Catatan keamanan untuk backend sungguhan:
/// - Android/iOS: pertimbangkan flutter_secure_storage (Keychain/Keystore).
/// - Web: localStorage bisa dibaca skrip di halaman (risiko XSS); lebih
///   aman memakai cookie HttpOnly + Secure + SameSite dari server.
/// - Token harus berumur pendek dan bisa dicabut di server.
class SharedPrefsSessionStorage implements SessionStorage {
  SharedPrefsSessionStorage();

  static const String _key = 'prasasti_connect.session_token';

  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  @override
  Future<String?> readToken() => _prefs.getString(_key);

  @override
  Future<void> writeToken(String token) => _prefs.setString(_key, token);

  @override
  Future<void> clear() => _prefs.remove(_key);
}

/// Hanya di memori (untuk pengujian; sesi hilang saat aplikasi ditutup).
class MemorySessionStorage implements SessionStorage {
  MemorySessionStorage([this._token]);

  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}
