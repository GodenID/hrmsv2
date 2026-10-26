import 'package:flutter/widgets.dart';

import '../data/announcement_repository.dart';
import '../data/api/api_announcement_repository.dart';
import '../data/api/api_attendance_repository.dart';
import '../data/api/api_auth_repository.dart';
import '../data/api/api_employee_repository.dart';
import '../data/api/api_event_repository.dart';
import '../data/api/api_leave_repository.dart';
import '../data/api/api_notification_repository.dart';
import '../data/api/api_overtime_repository.dart';
import '../data/api/api_profile_repository.dart';
import '../data/api/api_warning_repository.dart';
import '../data/attendance_repository.dart';
import '../data/auth_repository.dart';
import '../data/employee_repository.dart';
import '../data/event_repository.dart';
import '../data/leave_repository.dart';
import '../data/notification_repository.dart';
import '../data/overtime_repository.dart';
import '../data/profile_repository.dart';
import '../data/warning_repository.dart';
import 'app_update.dart';
import 'platform_services.dart';
import 'session_storage.dart';

/// Semua dependency aplikasi di satu tempat.
class AppDependencies {
  const AppDependencies({
    required this.auth,
    required this.attendance,
    required this.announcements,
    required this.leave,
    required this.overtime,
    required this.events,
    required this.profile,
    required this.employees,
    required this.notifications,
    required this.warnings,
    required this.updater,
    required this.sessionStorage,
    this.platform = const PlatformServices(),
  });

  /// Seluruh repository ke server PostgreSQL + S3.
  /// `API_BASE_URL` diisi via --dart-define. DB produksi mulai kosong
  /// (tanpa seed demo) — akun pertama yang daftar jadi superadmin.
  factory AppDependencies.api({
    required String baseUrl,
    SessionStorage? sessionStorage,
    PlatformServices platform = const PlatformServices(),
  }) {
    final store = sessionStorage ?? MemorySessionStorage();
    return AppDependencies(
      auth: ApiAuthRepository(baseUrl: baseUrl),
      attendance: ApiAttendanceRepository(
        baseUrl: baseUrl,
        sessionStorage: store,
      ),
      announcements: ApiAnnouncementRepository(
        baseUrl: baseUrl,
        sessionStorage: store,
      ),
      leave: ApiLeaveRepository(baseUrl: baseUrl, sessionStorage: store),
      overtime: ApiOvertimeRepository(baseUrl: baseUrl, sessionStorage: store),
      events: ApiEventRepository(baseUrl: baseUrl, sessionStorage: store),
      profile: ApiProfileRepository(baseUrl: baseUrl, sessionStorage: store),
      employees: ApiEmployeeRepository(baseUrl: baseUrl, sessionStorage: store),
      notifications: ApiNotificationRepository(
        baseUrl: baseUrl,
        sessionStorage: store,
      ),
      warnings: ApiWarningRepository(baseUrl: baseUrl, sessionStorage: store),
      updater: AppUpdater(baseUrl: baseUrl),
      sessionStorage: store,
      platform: platform,
    );
  }

  final AuthRepository auth;
  final AttendanceRepository attendance;
  final AnnouncementRepository announcements;
  final LeaveRepository leave;
  final OvertimeRepository overtime;
  final EventRepository events;
  final ProfileRepository profile;
  final EmployeeRepository employees;
  final NotificationRepository notifications;
  final WarningRepository warnings;
  final AppUpdater updater;
  final SessionStorage sessionStorage;
  final PlatformServices platform;
}

/// Menyediakan [AppDependencies] untuk seluruh aplikasi.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.dependencies, required super.child});

  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope tidak ditemukan di atas widget ini.');
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      dependencies != oldWidget.dependencies;
}

/// Sesi pengguna yang sedang login, tersedia di dalam shell.
class SessionScope extends InheritedWidget {
  const SessionScope({super.key, required this.session, required super.child});

  final AuthSession session;

  static AuthUser userOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'SessionScope tidak ditemukan di atas widget ini.');
    return scope!.session.user;
  }

  /// Tanpa mendaftarkan dependensi (aman dipanggil dari callback).
  static AuthSession? maybeSessionOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SessionScope>()?.session;

  @override
  bool updateShouldNotify(SessionScope oldWidget) =>
      session != oldWidget.session;
}
