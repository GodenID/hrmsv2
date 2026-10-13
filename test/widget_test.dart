import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/app.dart';
import 'package:hrms_app/core/app_scope.dart';

void main() {
  testWidgets('Halaman login tampil sebagai halaman awal', (tester) async {
    // Tanpa token tersimpan, aplikasi langsung ke halaman login tanpa
    // menghubungi server.
    await tester.pumpWidget(
      PrasastiConnectApp(
        dependencies: AppDependencies.api(baseUrl: 'http://localhost:8080'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Masuk'), findsWidgets);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Lupa password?'), findsOneWidget);
  });
}
