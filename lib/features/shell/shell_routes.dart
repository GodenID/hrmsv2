import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../data/announcement_repository.dart';
import '../../data/attendance_repository.dart';
import '../../data/employee_repository.dart';
import '../../data/leave_repository.dart';
import '../../data/event_repository.dart';
import '../../data/profile_repository.dart';
import '../announcements/announcement_detail_page.dart';
import '../approvals/correction_review_page.dart';
import '../approvals/leave_review_page.dart';
import '../approvals/out_of_area_review_page.dart';
import '../approvals/overtime_review_page.dart';
import '../attendance/correction_form_page.dart';
import '../attendance_locations/location_form_page.dart';
import '../employees/employee_detail_page.dart';
import '../employees/employee_form_page.dart';
import '../leave/leave_detail_page.dart';
import '../leave/leave_form_page.dart';
import '../leave/collective_leave_page.dart';
import '../overtime/overtime_detail_page.dart';
import '../overtime/overtime_form_page.dart';
import '../events/crew_form_page.dart';
import '../events/event_detail_page.dart';
import '../events/event_form_page.dart';
import '../events/event_thresholds_page.dart';
import '../notifications/notifications_page.dart';
import '../profile/change_password_page.dart';
import '../profile/edit_contact_page.dart';
import '../profile/profile_page.dart';
import '../warnings/warning_detail_page.dart';
import '../warnings/warning_form_page.dart';
import '../../data/warning_repository.dart';

/// Rute di dalam shell (dibuka di navigator milik menu yang aktif, sehingga
/// menu samping / bawah tetap terlihat).
abstract final class ShellRoutes {
  static const String root = '/';
  static const String announcementDetail = '/pengumuman';
  static const String attendanceCorrection = '/absensi/koreksi';
  static const String leaveForm = '/cuti/ajukan';
  static const String leaveDetail = '/cuti/detail';
  static const String collectiveLeave = '/cuti/bersama';
  static const String overtimeForm = '/pengajuan/lembur/ajukan';
  static const String overtimeDetail = '/pengajuan/lembur/detail';
  static const String eventDetail = '/event/detail';
  static const String eventForm = '/event/form';
  static const String eventCrewForm = '/event/crew';
  static const String eventThresholds = '/event/ambang';
  static const String profile = '/profil';
  static const String changePassword = '/profil/ganti-password';
  static const String editContact = '/profil/ubah-kontak';
  static const String leaveReview = '/persetujuan/cuti';
  static const String correctionReview = '/persetujuan/koreksi';
  static const String outOfAreaReview = '/persetujuan/luar-area';
  static const String overtimeReview = '/persetujuan/lembur';
  static const String employeeDetail = '/karyawan/detail';
  static const String employeeForm = '/karyawan/form';
  static const String notifications = '/notifikasi';
  static const String locationForm = '/lokasi-absen/form';
  static const String warningDetail = '/peringatan/detail';
  static const String warningForm = '/peringatan/form';

  static Route<dynamic> generate(
    RouteSettings settings, {
    required WidgetBuilder root,
  }) {
    final args = settings.arguments;

    MaterialPageRoute<T> page<T>(WidgetBuilder builder) =>
        MaterialPageRoute<T>(settings: settings, builder: builder);

    switch (settings.name) {
      case announcementDetail when args is Announcement:
        return page<AnnouncementDetailResult>(
          (context) => AnnouncementDetailPage(
            user: SessionScope.userOf(context),
            initial: args,
            repository: AppScope.of(context).announcements,
          ),
        );
      case attendanceCorrection when args is AttendanceDay:
        return page<bool>((_) => CorrectionFormPage(day: args));
      case leaveForm:
        return page<bool>(
          (_) => LeaveFormPage(initialBalance: args as LeaveBalance?),
        );
      case leaveDetail when args is LeaveRequest:
        return page<void>((_) => LeaveDetailPage(request: args));
      case collectiveLeave:
        return page<bool>((_) => const CollectiveLeavePage());
      case overtimeForm:
        return page<bool>((_) => const OvertimeFormPage());
      case overtimeDetail when args is OvertimeRequest:
        return page<void>((_) => OvertimeDetailPage(request: args));
      case eventDetail when args is EventItem:
        // Pop `true` bila event dihapus.
        return page<bool>((_) => EventDetailPage(initial: args));
      case eventForm:
        // Tanpa argumen = buat baru; dengan EventItem = edit.
        return page<bool>(
          (_) => EventFormPage(initial: args is EventItem ? args : null),
        );
      case eventCrewForm when args is EventItem:
        return page<bool>((_) => CrewFormPage(event: args));
      case eventThresholds:
        return page<bool>((_) => const EventSettingsPage());
      case profile:
        return page<void>((_) => const ProfilePage());
      case changePassword:
        return page<bool>((_) => const ChangePasswordPage());
      case editContact when args is EmployeeProfile:
        // Pop dengan profil terbaru bila tersimpan.
        return page<EmployeeProfile>((_) => EditContactPage(initial: args));
      case leaveReview when args is LeaveReviewItem:
        return page<RequestStatus>((_) => LeaveReviewPage(item: args));
      case correctionReview when args is CorrectionReviewItem:
        return page<RequestStatus>((_) => CorrectionReviewPage(item: args));
      case outOfAreaReview when args is OutOfAreaReviewItem:
        return page<RequestStatus>((_) => OutOfAreaReviewPage(item: args));
      case overtimeReview when args is OvertimeReviewItem:
        return page<RequestStatus>((_) => OvertimeReviewPage(item: args));
      case employeeDetail when args is EmployeeAccount:
        return page<void>((_) => EmployeeDetailPage(initial: args));
      case employeeForm:
        // Tanpa argumen = tambah; dengan EmployeeAccount = ubah.
        return page<bool>(
          (_) =>
              EmployeeFormPage(initial: args is EmployeeAccount ? args : null),
        );
      case notifications:
        return page<void>((_) => const NotificationsPage());
      case locationForm:
        // Tanpa argumen = tambah; dengan AttendanceLocation = ubah.
        return page<LocationFormResult>(
          (_) => LocationFormPage(
            initial: args is AttendanceLocation ? args : null,
          ),
        );
      case warningDetail when args is WarningLetterDetail:
        return page<bool>((_) => WarningDetailPage(initial: args));
      case warningForm:
        return page<bool>((_) => const WarningFormPage());
      default:
        return page<void>(root);
    }
  }
}
