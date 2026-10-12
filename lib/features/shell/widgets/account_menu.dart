import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/auth_repository.dart';
import '../../profile/profile_photo.dart';
import '../shell_controller.dart';
import '../sign_out.dart';

/// Avatar pengguna di kanan atas. Diketuk -> menu: Profil saya, Keluar.
///
/// [showName] = tampilkan nama & role di samping avatar (layar lebar).
class AccountMenuButton extends StatefulWidget {
  const AccountMenuButton({super.key, this.showName = false});

  final bool showName;

  @override
  State<AccountMenuButton> createState() => _AccountMenuButtonState();
}

class _AccountMenuButtonState extends State<AccountMenuButton> {
  final MenuController _menu = MenuController();

  static ButtonStyle _itemStyle(Color color) => MenuItemButton.styleFrom(
    foregroundColor: color,
    iconColor: color,
    iconSize: 20,
    minimumSize: const Size(0, 44),
    padding: const EdgeInsets.symmetric(horizontal: 16),
    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
  );

  void _toggle() => _menu.isOpen ? _menu.close() : _menu.open();

  @override
  Widget build(BuildContext context) {
    final user = SessionScope.userOf(context);

    return MenuAnchor(
      controller: _menu,
      alignmentOffset: const Offset(0, 6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(context.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: WidgetStatePropertyAll(
          context.ink.withValues(alpha: 0.25),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.panel),
            side: BorderSide(color: context.border),
          ),
        ),
      ),
      menuChildren: [
        _MenuHeader(user: user),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(),
        ),
        MenuItemButton(
          style: _itemStyle(context.ink),
          leadingIcon: const Icon(Icons.person_outline),
          onPressed: () => ShellController.maybeOf(context)?.openProfile(),
          child: const Text('Profil saya'),
        ),
        MenuItemButton(
          style: _itemStyle(context.danger),
          leadingIcon: const Icon(Icons.logout),
          onPressed: () => confirmSignOut(context),
          child: const Text('Keluar'),
        ),
      ],
      builder: (context, menu, _) => _Trigger(
        user: user,
        showName: widget.showName,
        expanded: menu.isOpen,
        onTap: _toggle,
      ),
    );
  }
}

class _Trigger extends StatelessWidget {
  const _Trigger({
    required this.user,
    required this.showName,
    required this.expanded,
    required this.onTap,
  });

  final AuthUser user;
  final bool showName;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final label = 'Menu akun, ${user.fullName}';

    if (!showName) {
      // Area sentuh 48 x 48.
      return Tooltip(
        message: 'Akun',
        child: Semantics(
          button: true,
          expanded: expanded,
          label: label,
          excludeSemantics: true,
          child: InkResponse(
            onTap: onTap,
            radius: 24,
            child: const SizedBox.square(
              dimension: 48,
              child: Center(child: CurrentUserAvatar(size: 32)),
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      expanded: expanded,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: expanded ? context.surfaceMuted : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          hoverColor: context.ink.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CurrentUserAvatar(size: 32),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.fullName,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        user.role.label,
                        style: textTheme.bodySmall?.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: context.inkSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Identitas di bagian atas menu (bukan tombol).
class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.user});

  final AuthUser user;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: 260,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          children: [
            const CurrentUserAvatar(size: 40),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.fullName,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${user.role.label} · @${user.username}',
                    style: textTheme.bodySmall?.copyWith(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
