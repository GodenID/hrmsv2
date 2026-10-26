import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hrms_app/core/app_update.dart';

AppRelease _release({required String sha256, required int size}) => AppRelease(
  versionCode: 2,
  versionName: '1.0.1',
  minVersionCode: 0,
  apkUrl: 'https://example.test/releases/app.apk',
  sha256: sha256,
  sizeBytes: size,
  notes: 'Perbaikan.',
);

void main() {
  final bytes = List<int>.generate(8192, (i) => i % 256);
  final digest = sha256.convert(bytes).toString();

  test('AppRelease membaca payload server', () {
    final release = AppRelease.fromJson({
      'versionCode': 3,
      'versionName': '1.0.2',
      'minVersionCode': 2,
      'apkUrl': 'https://example.test/a.apk',
      'sha256': digest.toUpperCase(),
      'sizeBytes': 1024,
      'notes': 'Catatan',
    });
    expect(release.versionCode, 3);
    expect(release.minVersionCode, 2);
    expect(release.sha256, digest);
    expect(release.sizeBytes, 1024);
  });

  test('pembaruan wajib saat versi terpasang di bawah minimum', () {
    final release = AppRelease(
      versionCode: 3,
      versionName: '1.0.2',
      minVersionCode: 2,
      apkUrl: 'https://example.test/releases/app.apk',
      sha256: digest,
      sizeBytes: bytes.length,
      notes: '',
    );
    expect(AppUpdate(release: release, currentVersionCode: 1).forced, isTrue);
    expect(AppUpdate(release: release, currentVersionCode: 2).forced, isFalse);
  });

  test('perangkat non-Android tidak memeriksa pembaruan', () async {
    final updater = AppUpdater(baseUrl: 'https://example.test');
    // Tes berjalan di host (bukan Android): tidak boleh menyentuh jaringan.
    expect(await updater.check(), isNull);
  });

  test('unduhan valid lolos verifikasi checksum', () async {
    final dir = await Directory.systemTemp.createTemp('prasasti-update');
    addTearDown(() => dir.delete(recursive: true));

    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.value(bytes),
        200,
        contentLength: bytes.length,
      );
    });
    final updater = AppUpdater(
      baseUrl: 'https://example.test',
      client: client,
      currentVersionCode: () async => 1,
      storageDirectory: () async => dir,
    );

    final progress = <int>[];
    final file = await updater.download(
      _release(sha256: digest, size: bytes.length),
      onProgress: (received, _) => progress.add(received),
      isCancelled: () => false,
    );

    expect(await file.readAsBytes(), bytes);
    expect(progress.last, bytes.length);
  });

  test('checksum salah menghapus berkas dan menolak', () async {
    final dir = await Directory.systemTemp.createTemp('prasasti-update');
    addTearDown(() => dir.delete(recursive: true));

    final client = MockClient.streaming((request, bodyStream) async {
      return http.StreamedResponse(
        Stream.value(bytes),
        200,
        contentLength: bytes.length,
      );
    });
    final updater = AppUpdater(
      baseUrl: 'https://example.test',
      client: client,
      currentVersionCode: () async => 1,
      storageDirectory: () async => dir,
    );

    await expectLater(
      updater.download(
        _release(sha256: '0' * 64, size: bytes.length),
        onProgress: (_, _) {},
        isCancelled: () => false,
      ),
      throwsA(isA<AppUpdateException>()),
    );
    expect(dir.listSync().whereType<File>(), isEmpty);
  });
}
