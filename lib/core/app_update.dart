import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Satu versi Android yang sudah diterbitkan server (`GET /app/version`).
class AppRelease {
  const AppRelease({
    required this.versionCode,
    required this.versionName,
    required this.minVersionCode,
    required this.apkUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.notes,
  });

  final int versionCode;
  final String versionName;
  final int minVersionCode;
  final String apkUrl;
  final String sha256;
  final int sizeBytes;
  final String notes;

  factory AppRelease.fromJson(Map<String, dynamic> m) => AppRelease(
    versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
    versionName: (m['versionName'] ?? '').toString(),
    minVersionCode: (m['minVersionCode'] as num?)?.toInt() ?? 0,
    apkUrl: (m['apkUrl'] ?? '').toString(),
    sha256: (m['sha256'] ?? '').toString().toLowerCase(),
    sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
    notes: (m['notes'] ?? '').toString(),
  );
}

/// Pembaruan yang layak ditawarkan ke pengguna.
class AppUpdate {
  const AppUpdate({required this.release, required this.currentVersionCode});

  final AppRelease release;
  final int currentVersionCode;

  /// Versi terpasang di bawah batas minimum server: dialog tidak boleh
  /// ditutup sebelum pengguna memasang pembaruan.
  bool get forced => currentVersionCode < release.minVersionCode;
}

class AppUpdateException implements Exception {
  const AppUpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AppUpdateCancelled implements Exception {
  const AppUpdateCancelled();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Pemeriksa versi, pengunduh APK, dan pemanggil pemasang sistem Android.
///
/// Android tidak mengizinkan pemasangan tanpa konfirmasi pengguna. Alur ini
/// mengotomatiskan sisanya: cek versi, unduh, verifikasi SHA-256, lalu buka
/// layar pemasangan. Pengguna hanya menekan "Install" sekali.
class AppUpdater {
  AppUpdater({
    required String baseUrl,
    http.Client? client,
    Future<int> Function()? currentVersionCode,
    Future<Directory> Function()? storageDirectory,
    MethodChannel? channel,
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _channel = channel ?? const MethodChannel(_channelName) {
    _currentVersionCode = currentVersionCode;
    _storageDirectory = storageDirectory;
  }

  static const String _channelName = 'com.prasasti.connect/installer';
  static const String _skipKey = 'app.update.skippedVersionCode';

  final String baseUrl;
  final http.Client _client;
  // Diisi dari konstruktor (bukan initializer formal agar nama parameter
  // tetap publik dan enak dibaca di call-site).
  late final Future<int> Function()? _currentVersionCode;
  late final Future<Directory> Function()? _storageDirectory;
  final MethodChannel _channel;
  // Dibuat saat dipakai: konstruktor SharedPreferencesAsync melempar bila
  // platform plugin belum terdaftar (mis. lingkungan tes murni).
  SharedPreferencesAsync? _prefs;

  SharedPreferencesAsync get _prefsInstance =>
      _prefs ??= SharedPreferencesAsync();

  /// Fitur ini hanya untuk Android. iOS/web/desktop tidak punya pemasangan
  /// APK mandiri; pembaruan lewat store masing-masing.
  bool get supported => Platform.isAndroid;

  Future<int> currentVersionCode() async {
    final override = _currentVersionCode;
    if (override != null) return override();
    final info = await PackageInfo.fromPlatform();
    return int.tryParse(info.buildNumber) ?? 0;
  }

  /// null = tidak ada pembaruan / perangkat tidak didukung / server diam.
  Future<AppUpdate?> check() async {
    if (!supported) return null;
    try {
      final res = await _client
          .get(
            Uri.parse('$baseUrl/app/version'),
            headers: {'accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map || decoded['available'] != true) return null;
      final release = AppRelease.fromJson(decoded.cast<String, dynamic>());
      if (release.versionCode <= 0 || release.apkUrl.isEmpty) return null;
      final current = await currentVersionCode();
      if (release.versionCode <= current) return null;
      return AppUpdate(release: release, currentVersionCode: current);
    } catch (_) {
      // Jaringan bermasalah bukan alasan menghalangi pemakaian aplikasi.
      return null;
    }
  }

  Future<Directory> _directory() async {
    final override = _storageDirectory;
    if (override != null) return override();
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}updates');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Unduh ke penyimpanan internal aplikasi. Melempar [AppUpdateCancelled]
  /// bila [isCancelled] menjadi true, dan [AppUpdateException] bila checksum
  /// tidak cocok atau server menolak.
  Future<File> download(
    AppRelease release, {
    required void Function(int received, int total) onProgress,
    required bool Function() isCancelled,
  }) async {
    final dir = await _directory();
    // Bersihkan unduhan lama agar penyimpanan tidak menumpuk.
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.apk')) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
    final file = File(
      '${dir.path}${Platform.pathSeparator}update-${release.versionCode}.apk',
    );

    final request = http.Request('GET', Uri.parse(release.apkUrl));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw AppUpdateException(
        'Server menolak unduhan (${response.statusCode}). Coba lagi nanti.',
      );
    }

    final total = response.contentLength ?? release.sizeBytes;
    var received = 0;
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    final out = file.openWrite();

    try {
      await for (final chunk in response.stream) {
        if (isCancelled()) throw const AppUpdateCancelled();
        out.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await out.flush();
    } catch (_) {
      await out.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
    await out.close();
    hasher.close();

    // Cek ulang: pembatalan bisa datang tepat setelah chunk terakhir.
    if (isCancelled()) {
      if (await file.exists()) await file.delete();
      throw const AppUpdateCancelled();
    }
    final digest = digestSink.value?.toString() ?? '';
    if (digest != release.sha256) {
      if (await file.exists()) await file.delete();
      throw const AppUpdateException(
        'Berkas unduhan rusak (checksum tidak cocok). Coba unduh lagi.',
      );
    }
    return file;
  }

  Future<bool> canInstall() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openInstallSettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('openInstallSettings');
    } on MissingPluginException {
      // Lingkungan uji tanpa implementasi native.
    } on PlatformException {
      // Layar pengaturan tidak tersedia di perangkat ini.
    }
  }

  Future<void> install(File apk) async {
    try {
      await _channel.invokeMethod<void>('installApk', {'path': apk.path});
    } on MissingPluginException {
      throw const AppUpdateException(
        'Pemasang APK tidak tersedia di perangkat ini.',
      );
    } on PlatformException catch (e) {
      throw AppUpdateException(e.message ?? 'Gagal membuka pemasang APK.');
    }
  }

  Future<int?> skippedVersion() async {
    try {
      return await _prefsInstance.getInt(_skipKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> skip(int versionCode) async {
    try {
      await _prefsInstance.setInt(_skipKey, versionCode);
    } catch (_) {
      // Gagal menyimpan preferensi tidak boleh menghalangi aplikasi.
    }
  }
}
