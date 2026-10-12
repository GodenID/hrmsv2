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
import '../data/mock/mock_announcement_repository.dart';
import '../data/mock/mock_attendance_repository.dart';
import '../data/mock/mock_auth_repository.dart';
import '../data/mock/mock_employee_repository.dart';
import '../data/mock/mock_event_repository.dart';
import '../data/mock/mock_leave_repository.dart';
import '../data/mock/mock_notification_repository.dart';
import '../data/mock/mock_overtime_repository.dart';
import '../data/mock/mock_profile_repository.dart';
import '../data/mock/mock_store.dart';
import '../data/notification_repository.dart';
import '../data/overtime_repository.dart';
import '../data/profile_repository.dart';
import '../data/warning_repository.dart';
import '../data/mock/mock_warning_repository.dart';
import 'platform_services.dart';
import 'session_storage.dart';

/// Semua dependency aplikasi di satu tempat.
/// Ganti implementasi mock dengan implementasi API saat backend siap.
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
    required this.sessionStorage,
    this.platform = const PlatformServices(),
  });

  /// Semua repository mock berbagi satu [MockStore].
  /// [latency] = null memakai jeda bawaan tiap repository.
  /// [sessionStorage] bawaan: di memori (cocok untuk pengujian).
  factory AppDependencies.mock({
    Duration? latency,
    MockStore? store,
    SessionStorage? sessionStorage,
    PlatformServices platform = const PlatformServices(),
  }) {
    final s = store ?? MockStore();
    return AppDependencies(
      auth: latency == null
          ? MockAuthRepository(s)
          : MockAuthRepository(s, latency: latency),
      attendance: latency == null
          ? MockAttendanceRepository(s)
          : MockAttendanceRepository(s, latency: latency),
      announcements: latency == null
          ? MockAnnouncementRepository(s)
          : MockAnnouncementRepository(s, latency: latency),
      leave: latency == null
          ? MockLeaveRepository(s)
          : MockLeaveRepository(s, latency: latency),
      overtime: latency == null
          ? MockOvertimeRepository(s)
          : MockOvertimeRepository(s, latency: latency),
      events: latency == null
          ? MockEventRepository(s)
          : MockEventRepository(s, latency: latency),
      profile: latency == null
          ? MockProfileRepository(s)
          : MockProfileRepository(s, latency: latency),
      employees: latency == null
          ? MockEmployeeRepository(s)
          : MockEmployeeRepository(s, latency: latency),
      notifications: latency == null
          ? MockNotificationRepository(s)
          : MockNotificationRepository(s, latency: latency),
      warnings: latency == null
          ? MockWarningRepository(s)
          : MockWarningRepository(s, latency: latency),
      sessionStorage: sessionStorage ?? MemorySessionStorage(),
      platform: platform,
    );
  }

  /// Mode API: seluruh repository ke server PostgreSQL + S3.
  /// Dipakai saat `API_BASE_URL` diisi via --dart-define. DB produksi mulai
  /// kosong (tanpa seed demo) — akun pertama yang daftar jadi superadmin.
  /// [AppDependencies.mock] tersisa untuk pengujian saja.
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
      employees: ApiEmployeeRepository(
        baseUrl: baseUrl,
        sessionStorage: store,
      ),
      notifications: ApiNotificationRepository(
        baseUrl: baseUrl,
        sessionStorage: store,
      ),
      warnings: ApiWarningRepository(baseUrl: baseUrl, sessionStorage: store),
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
