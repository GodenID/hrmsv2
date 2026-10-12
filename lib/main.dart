import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_scope.dart';
import 'core/session_storage.dart';
import 'data/api/api_auth_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Tanpa --dart-define=API_BASE_URL: mode mock (pengembangan).
  // Dengan API_BASE_URL: auth ke server PostgreSQL, fitur lain masih mock
  // sampai endpointnya menyusul.
  final baseUrl = ApiConfig.baseUrl;
  runApp(
    PrasastiConnectApp(
      dependencies: baseUrl.isEmpty
          ? AppDependencies.mock(
              sessionStorage: SharedPrefsSessionStorage(),
            )
          : AppDependencies.api(
              baseUrl: baseUrl,
              sessionStorage: SharedPrefsSessionStorage(),
            ),
    ),
  );
}
