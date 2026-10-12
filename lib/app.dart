import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_routes.dart';
import 'core/app_info.dart';
import 'core/app_scope.dart';
import 'core/theme/app_theme.dart';
import 'data/auth_repository.dart';
import 'features/auth/forgot_password_page.dart';
import 'features/auth/login_page.dart';
import 'features/auth/register_page.dart';
import 'features/auth/startup_page.dart';
import 'features/shell/app_shell.dart';

class PrasastiConnectApp extends StatelessWidget {
  const PrasastiConnectApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      dependencies: dependencies,
      child: MaterialApp(
        title: AppInfo.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        // Kalender, pemilih jam, dan teks bawaan Material dalam Bahasa
        // Indonesia.
        locale: const Locale('id', 'ID'),
        supportedLocales: const [Locale('id', 'ID')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        initialRoute: AppRoutes.login,
        // Selalu mulai dari pemulihan sesi (mis. saat web di-refresh):
        // sesi tersimpan yang valid langsung ke Beranda, selain itu login.
        onGenerateInitialRoutes: (_) => [_startupRoute()],
        onGenerateRoute: (settings) {
          final args = settings.arguments;
          switch (settings.name) {
            case AppRoutes.forgotPassword:
              // Mengembalikan username saat reset berhasil (lihat LoginPage).
              return MaterialPageRoute<String>(
                settings: settings,
                builder: (_) => ForgotPasswordPage(
                  authRepository: dependencies.auth,
                  initialUsername: args as String?,
                ),
              );
            case AppRoutes.register:
              // Mengembalikan username saat pendaftaran berhasil.
              return MaterialPageRoute<String>(
                settings: settings,
                builder: (_) => RegisterPage(
                  authRepository: dependencies.auth,
                  platform: dependencies.platform,
                ),
              );
            case AppRoutes.home when args is AuthSession:
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => AppShell(session: args),
              );
            default:
              // Termasuk /beranda tanpa sesi login -> kembali ke login.
              return _loginRoute();
          }
        },
      ),
    );
  }

  Route<void> _startupRoute() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: AppRoutes.startup),
      builder: (_) => StartupPage(
        authRepository: dependencies.auth,
        sessionStorage: dependencies.sessionStorage,
      ),
    );
  }

  Route<void> _loginRoute() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: AppRoutes.login),
      builder: (_) => LoginPage(
        authRepository: dependencies.auth,
        sessionStorage: dependencies.sessionStorage,
      ),
    );
  }
}
