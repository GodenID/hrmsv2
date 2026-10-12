import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/brand_mark.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/theme/theme_colors.dart';
import '../../data/auth_repository.dart';
import '../approvals/approvals_page.dart';
import '../attendance/attendance_history_page.dart';
import '../attendance_locations/attendance_locations_page.dart';
import '../dashboard/dashboard_page.dart';
import '../employees/employee_list_page.dart';
import '../events/event_list_page.dart';
import '../leave/leave_page.dart';
import '../reports/reports_page.dart';
import '../warnings/warnings_page.dart';
import '../notifications/widgets/notification_bell.dart';
import '../profile/profile_photo.dart';
import 'shell_controller.dart';
import 'shell_routes.dart';
import 'widgets/account_menu.dart';

enum _Section { personal, manage }

class _Destination {
  const _Destination({
    required this.tab,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
    this.section = _Section.personal,
    this.primaryOnMobile = true,
  });

  final ShellTab tab;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final WidgetBuilder builder;
  final _Section section;

  /// false = di HP masuk ke menu "Lainnya" (menu bawah maksimal 5 item).
  final bool primaryOnMobile;
}

/// Menu per role. Profil & Keluar ada di menu akun (avatar kanan atas).
/// - Staff: Beranda, Absensi, Pengajuan, Event (+ Peringatan di "Lainnya").
/// - Manager & Super Admin: + Persetujuan & Karyawan (bagian "Kelola").
///   Super Admin juga: Lokasi absen.
///   Di HP: Beranda, Absensi, Pengajuan, Persetujuan, lalu "Lainnya".
List<_Destination> _destinationsFor(UserRole role) {
  final manages = role.canReviewRequests || role.canManageEmployees;
  return [
    _Destination(
      tab: ShellTab.dashboard,
      label: 'Beranda',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      builder: (_) => const DashboardPage(),
    ),
    _Destination(
      tab: ShellTab.attendance,
      label: 'Absensi',
      icon: Icons.fingerprint,
      selectedIcon: Icons.fingerprint,
      builder: (_) => const AttendanceHistoryPage(),
    ),
    _Destination(
      tab: ShellTab.leave,
      label: 'Pengajuan',
      icon: Icons.event_available_outlined,
      selectedIcon: Icons.event_available,
      builder: (_) => const LeavePage(),
    ),
    _Destination(
      tab: ShellTab.events,
      label: 'Event',
      icon: Icons.festival_outlined,
      selectedIcon: Icons.festival,
      builder: (_) => const EventListPage(),
      primaryOnMobile: !manages,
    ),
    if (role.canReviewRequests)
      _Destination(
        tab: ShellTab.approvals,
        label: 'Persetujuan',
        icon: Icons.fact_check_outlined,
        selectedIcon: Icons.fact_check,
        builder: (_) => const ApprovalsPage(),
        section: _Section.manage,
      ),
    if (role.canManageEmployees)
      _Destination(
        tab: ShellTab.employees,
        label: 'Karyawan',
        icon: Icons.people_outline,
        selectedIcon: Icons.people,
        builder: (_) => const EmployeeListPage(),
        section: _Section.manage,
        primaryOnMobile: false,
      ),
    if (role.canManageAttendanceLocations)
      _Destination(
        tab: ShellTab.locations,
        label: 'Lokasi absen',
        icon: Icons.location_on_outlined,
        selectedIcon: Icons.location_on,
        builder: (_) => const AttendanceLocationsPage(),
        section: _Section.manage,
        primaryOnMobile: false,
      ),
    if (role == UserRole.superadmin)
      _Destination(
        tab: ShellTab.reports,
        label: 'Laporan',
        icon: Icons.assessment_outlined,
        selectedIcon: Icons.assessment,
        builder: (_) => const ReportsPage(),
        section: _Section.manage,
        primaryOnMobile: false,
      ),
    // Semua role: karyawan melihat miliknya, Manager membaca timnya,
    // Super Admin mengelola. Sengaja di "Lainnya" di HP agar menu bawah
    // tetap ramping.
    _Destination(
      tab: ShellTab.warnings,
      label: 'Peringatan',
      icon: Icons.gavel_outlined,
      selectedIcon: Icons.gavel,
      builder: (_) => const WarningsPage(),
      primaryOnMobile: false,
    ),
  ];
}

/// Kerangka setelah login.
/// - Desktop (≥ 960px): menu samping + bar atas (lonceng & menu akun).
/// - HP/tablet: menu bawah + lonceng & avatar di AppBar halaman utama.
/// Setiap menu punya navigator sendiri, jadi posisi & riwayat halaman di
/// tiap menu tetap tersimpan saat berpindah menu.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.session});

  final AuthSession session;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const List<Widget> _mobileRootActions = [
    NotificationBell(),
    AccountMenuButton(),
  ];

  AuthUser get _user => widget.session.user;

  late final List<_Destination> _destinations = _destinationsFor(_user.role);
  late final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    for (final _ in _destinations) GlobalKey<NavigatorState>(),
  ];
  late final List<bool> _nestedCanPop = [for (final _ in _destinations) false];

  /// Indeks menu yang tampil langsung di menu bawah HP.
  late final List<int> _primary = [
    for (var i = 0; i < _destinations.length; i++)
      if (_destinations[i].primaryOnMobile) i,
  ];
  late final List<int> _overflow = [
    for (var i = 0; i < _destinations.length; i++)
      if (!_destinations[i].primaryOnMobile) i,
  ];

  /// Menu baru dibangun saat pertama dibuka (data tidak dimuat sekaligus).
  final Set<int> _visited = {0};
  int _index = 0;

  ProfilePhotoController? _photo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_photo != null) return;
    _photo = ProfilePhotoController(
      repository: AppScope.of(context).profile,
      user: _user,
    )..load();
  }

  @override
  void dispose() {
    _photo?.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _index) {
      // Ketuk menu yang aktif: kembali ke halaman utamanya.
      _navigatorKeys[index].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  void _openTab(ShellTab tab) {
    final index = _destinations.indexWhere((d) => d.tab == tab);
    if (index < 0) return;
    setState(() {
      _index = index;
      _visited.add(index);
    });
    _navigatorKeys[index].currentState?.popUntil((r) => r.isFirst);
  }

  /// Membuka [routeName] di menu aktif, kecuali sudah tampil paling atas.
  void _pushOnce(String routeName) {
    final navigator = _navigatorKeys[_index].currentState;
    if (navigator == null) return;
    var alreadyOpen = false;
    // Predikat langsung true: hanya mengintip rute teratas, tidak pop.
    navigator.popUntil((route) {
      alreadyOpen = route.settings.name == routeName;
      return true;
    });
    if (!alreadyOpen) navigator.pushNamed(routeName);
  }

  Future<void> _showMore() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final i in _overflow)
                ListTile(
                  selected: i == _index,
                  selectedColor: context.accentText,
                  selectedTileColor: context.accentSubtle,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  leading: Icon(
                    i == _index
                        ? _destinations[i].selectedIcon
                        : _destinations[i].icon,
                  ),
                  title: Text(_destinations[i].label),
                  onTap: () => Navigator.of(context).pop(i),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) _select(selected);
  }

  void _handleBack(bool didPop, Object? _) {
    if (didPop) return;
    final nested = _navigatorKeys[_index].currentState;
    if (nested != null && nested.canPop()) {
      nested.maybePop();
    } else if (_index != 0) {
      _select(0);
    }
  }

  Widget _buildNavigator(int index) {
    return NotificationListener<NavigationNotification>(
      onNotification: (notification) {
        if (_nestedCanPop[index] != notification.canHandlePop) {
          setState(() => _nestedCanPop[index] = notification.canHandlePop);
        }
        return false;
      },
      child: Navigator(
        key: _navigatorKeys[index],
        onGenerateRoute: (settings) =>
            ShellRoutes.generate(settings, root: _destinations[index].builder),
      ),
    );
  }

  Widget _buildBottomBar() {
    final hasMore = _overflow.isNotEmpty;
    final position = _primary.indexOf(_index);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: context.border)),
      ),
      child: NavigationBar(
        selectedIndex: position >= 0 ? position : _primary.length,
        onDestinationSelected: (p) {
          if (p < _primary.length) {
            _select(_primary[p]);
          } else {
            _showMore();
          }
        },
        destinations: [
          for (final i in _primary)
            NavigationDestination(
              icon: Icon(_destinations[i].icon),
              selectedIcon: Icon(_destinations[i].selectedIcon),
              label: _destinations[i].label,
            ),
          if (hasMore)
            const NavigationDestination(
              icon: Icon(Icons.more_horiz),
              selectedIcon: Icon(Icons.more_horiz),
              label: 'Lainnya',
              tooltip: 'Menu lainnya',
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = AppSpacing.isSidebarLayout(MediaQuery.sizeOf(context).width);

    final pages = PageChrome(
      rootActions: isWide ? const [] : _mobileRootActions,
      child: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _destinations.length; i++)
            _visited.contains(i)
                // Menu yang tidak aktif tidak menerima fokus keyboard.
                ? ExcludeFocus(
                    excluding: i != _index,
                    child: _buildNavigator(i),
                  )
                : const SizedBox.shrink(),
        ],
      ),
    );

    return SessionScope(
      session: widget.session,
      child: ProfilePhotoScope(
        controller: _photo!,
        child: ShellController(
          openTab: _openTab,
          openNotifications: () => _pushOnce(ShellRoutes.notifications),
          openProfile: () => _pushOnce(ShellRoutes.profile),
          child: PopScope(
            canPop: _index == 0 && !_nestedCanPop[0],
            onPopInvokedWithResult: _handleBack,
            child: Scaffold(
              backgroundColor: context.surface,
              body: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Sidebar(
                          destinations: _destinations,
                          selectedIndex: _index,
                          onSelect: _select,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const _TopBar(),
                              Expanded(child: pages),
                            ],
                          ),
                        ),
                      ],
                    )
                  : pages,
              bottomNavigationBar: isWide ? null : _buildBottomBar(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tinggi bar atas desktop; header menu samping disamakan agar garisnya
/// sejajar.
const double _topBarHeight = 64;

/// Bar atas desktop: lonceng notifikasi + menu akun di kanan.
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _topBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(bottom: BorderSide(color: context.border)),
      ),
      child: const Row(
        children: [
          Spacer(),
          NotificationBell(),
          SizedBox(width: AppSpacing.sm),
          AccountMenuButton(showName: true),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    List<Widget> section(_Section s, String title) {
      final items = [
        for (var i = 0; i < destinations.length; i++)
          if (destinations[i].section == s) i,
      ];
      if (items.isEmpty) return const [];
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: Semantics(
            header: true,
            child: Text(title, style: textTheme.labelSmall),
          ),
        ),
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: _SidebarItem(
              destination: destinations[i],
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
            ),
          ),
      ];
    }

    final manage = section(_Section.manage, 'KELOLA');

    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: context.surfaceMuted,
        border: Border(right: BorderSide(color: context.border)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: _topBarHeight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: context.border)),
              ),
              child: const BrandMark(size: 30),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 20, 12, 16),
                children: [
                  ...section(_Section.personal, 'MENU'),
                  if (manage.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    ...manage,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? context.accentText : context.ink;

    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? context.accentSubtle : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          hoverColor: context.ink.withValues(alpha: 0.04),
          child: SizedBox(
            height: 42,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 20,
                    color: selected
                        ? context.accentText
                        : context.inkSecondary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    destination.label,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
