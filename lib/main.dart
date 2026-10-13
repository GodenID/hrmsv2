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
  // Build production/web semua via API. Mock hanya dipakai di test doubles.
  final baseUrl = ApiConfig.baseUrl;
  if (baseUrl.isEmpty) {
    // Production build harus selalu terhubung ke server.
    throw StateError(
      'API_BASE_URL wajib diisi untuk build production '
      '(--dart-define=API_BASE_URL=https://apihrms.prasastigroup.id).',
    );
  }
  final dependencies = AppDependencies.api(
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
