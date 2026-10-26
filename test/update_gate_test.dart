import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/core/app_update.dart';
import 'package:hrms_app/features/update/update_gate.dart';

AppRelease _release({required int versionCode, required int minVersionCode}) {
  return AppRelease(
    versionCode: versionCode,
    versionName: '1.0.6',
    minVersionCode: minVersionCode,
    apkUrl: 'https://example.test/releases/app.apk',
    sha256: '0' * 64,
    sizeBytes: 3,
    notes: 'Catatan rilis.',
  );
}

AppUpdate _update({required int current, required int minVersionCode}) {
  return AppUpdate(
    release: _release(versionCode: 9, minVersionCode: minVersionCode),
    currentVersionCode: current,
  );
}

class _FakeUpdater extends AppUpdater {
  _FakeUpdater({required this.update, required this.current, this.file})
    : super(baseUrl: 'https://example.test');

  final AppUpdate? update;
  final int current;
  final File? file;

  @override
  Future<AppUpdate?> check() async => update;

  @override
  Future<int> currentVersionCode() async => current;

  @override
  Future<int?> skippedVersion() async => null;

  @override
  Future<void> skip(int versionCode) async {}

  @override
  Future<bool> canInstall() async => true;

  @override
  Future<void> openInstallSettings() async {}

  @override
  Future<File> download(
    AppRelease release, {
    required void Function(int received, int total) onProgress,
    required bool Function() isCancelled,
  }) async {
    final apk = file!;
    final size = apk.lengthSync();
    onProgress(size, size);
    return apk;
  }

  @override
  Future<void> install(File apk) async {}
}

Widget _app(
  AppUpdater updater, {
  required GlobalKey<NavigatorState> navigatorKey,
  Widget home = const Scaffold(body: Center(child: Text('SPLASH'))),
}) {
  return MaterialApp(
    navigatorKey: navigatorKey,
    builder: (context, child) => AppUpdateGate(
      updater: updater,
      child: child ?? const SizedBox.shrink(),
    ),
    home: home,
  );
}

void main() {
  testWidgets('pembaruan wajib tetap menutup layar setelah splash selesai', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final updater = _FakeUpdater(
      update: _update(current: 7, minVersionCode: 9),
      current: 7,
    );

    await tester.pumpWidget(_app(updater, navigatorKey: navigatorKey));
    await tester.pumpAndSettle();

    expect(find.text('Pembaruan tersedia'), findsOneWidget);
    expect(find.text('Nanti'), findsNothing);
    expect(find.text('Unduh & pasang'), findsOneWidget);

    // Splash memanggil pushReplacement. Dulu ini mengganti route dialog
    // pembaruan sehingga aplikasi lama bisa dipakai.
    navigatorKey.currentState!.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('BERANDA'))),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BERANDA'), findsOneWidget);
    expect(find.text('Pembaruan tersedia'), findsOneWidget);
    expect(find.text('Nanti'), findsNothing);
    expect(find.text('Unduh & pasang'), findsOneWidget);
  });

  testWidgets('pembaruan opsional masih bisa ditunda', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    final updater = _FakeUpdater(
      update: _update(current: 7, minVersionCode: 0),
      current: 7,
    );

    await tester.pumpWidget(_app(updater, navigatorKey: navigatorKey));
    await tester.pumpAndSettle();

    expect(find.text('Pembaruan tersedia'), findsOneWidget);
    expect(find.text('Nanti'), findsOneWidget);

    await tester.tap(find.text('Nanti'));
    await tester.pumpAndSettle();

    expect(find.text('Pembaruan tersedia'), findsNothing);
    expect(find.text('SPLASH'), findsOneWidget);
  });

  testWidgets('pemasangan batal mengembalikan wajib ke siap pasang', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('prasasti-gate');
    addTearDown(() => dir.deleteSync(recursive: true));
    final apk = File('${dir.path}${Platform.pathSeparator}update-9.apk')
      ..writeAsBytesSync(const [1, 2, 3]);

    final navigatorKey = GlobalKey<NavigatorState>();
    final updater = _FakeUpdater(
      update: _update(current: 7, minVersionCode: 9),
      current: 7,
      file: apk,
    );

    await tester.pumpWidget(_app(updater, navigatorKey: navigatorKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Unduh & pasang'));
    await tester.pumpAndSettle();
    expect(find.text('Siap dipasang'), findsOneWidget);

    await tester.tap(find.text('Pasang sekarang'));
    await tester.pumpAndSettle();
    expect(find.text('Menyelesaikan pembaruan'), findsOneWidget);
    expect(find.text('Tutup'), findsNothing);

    // Pengguna kembali dari pemasang tanpa menyelesaikan pemasangan.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Siap dipasang'), findsOneWidget);
    expect(find.textContaining('Pemasangan belum selesai'), findsOneWidget);
    expect(find.text('Pasang sekarang'), findsOneWidget);
    expect(find.text('Tutup'), findsNothing);
    expect(find.text('Nanti'), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
