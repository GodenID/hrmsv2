import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/widgets/role_badge.dart';
import '../../data/auth_repository.dart';
import '../announcements/widgets/announcement_carousel.dart';
import 'widgets/attendance_panel.dart';
import 'widgets/summary_section.dart';

/// Beranda (semua role):
/// 1. Sapaan + nama + role
/// 2. Absensi hari ini (clock in / clock out)
/// 3. Pengumuman — slider; detail mencatat siapa yang sudah melihat
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = SessionScope.userOf(context);
    final deps = AppScope.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = AppSpacing.isSidebarLayout(screenWidth);

    // Logo mengikuti lebar layar agar proporsional di HP kecil maupun
    // tablet, dijepit 30–40px agar pas di AppBar (60px): tidak kekecilan,
    // tidak menabrak lonceng notifikasi.
    final logoHeight =
        (screenWidth * 0.095).clamp(30.0, 40.0).toDouble();

    return PageScaffold(
      title: 'Beranda',
      showWideHeader: false,
      mobileTitle: AdaptiveBrandLogo(height: logoHeight),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Greeting(user: user),
          SizedBox(height: isWide ? 28 : 20),
          AttendancePanel(user: user, repository: deps.attendance),
          SizedBox(height: isWide ? 28 : 20),
          SummarySection(
            user: user,
            attendance: deps.attendance,
            leave: deps.leave,
            events: deps.events,
          ),
          SizedBox(height: isWide ? 40 : 32),
          AnnouncementCarousel(user: user, repository: deps.announcements),
        ],
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${DateFormatId.greeting(now)},',
          style: textTheme.bodyLarge?.copyWith(color: context.inkSecondary),
        ),
        const SizedBox(height: 2),
        Semantics(
          header: true,
          child: Text(
            user.fullName,
            style: textTheme.headlineSmall?.copyWith(fontSize: 28, height: 1.2),
          ),
        ),
        const SizedBox(height: AppSpacing.sm + 2),
        Wrap(
          spacing: AppSpacing.sm + 2,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            RoleBadge(role: user.role),
            Text('@${user.username}', style: textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}
