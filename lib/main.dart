import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_scope.dart';
import 'core/push_notifications.dart';
import 'core/session_storage.dart';
import 'data/api/api_auth_repository.dart';
import 'data/api/api_notification_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Tanpa --dart-define=API_BASE_URL: mode mock (pengembangan).
  // Dengan API_BASE_URL: seluruh repository ke server.
  final baseUrl = ApiConfig.baseUrl;
  final dependencies = baseUrl.isEmpty
      ? AppDependencies.mock(
          sessionStorage: SharedPrefsSessionStorage(),
        )
      : AppDependencies.api(
          baseUrl: baseUrl,
          sessionStorage: SharedPrefsSessionStorage(),
        );
  runApp(PrasastiConnectApp(dependencies: dependencies));
  // Push: nonblokir & nonfatal. Tanpa file Firebase, diam-diam nonaktif.
  if (dependencies.notifications is ApiNotificationRepository) {
    final repo = dependencies.notifications as ApiNotificationRepository;
    unawaited(
      PushNotifications.ensureInitialized(
        baseUrl: baseUrl,
        readToken: dependencies.sessionStorage.readToken,
        syncToken: repo.syncPushToken,
      ),
    );
  }
}
