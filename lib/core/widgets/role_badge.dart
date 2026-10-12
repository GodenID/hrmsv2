import 'package:flutter/material.dart';

import '../theme/theme_colors.dart';
import '../../data/auth_repository.dart';

/// Label role pengguna. Super Admin dibuat paling kontras karena memiliki
/// hak tulis.
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (role) {
      UserRole.staff => (
        context.surfaceMuted,
        context.inkSecondary,
        context.border,
      ),
      UserRole.manager => (
        context.accentSubtle,
        context.accentText,
        const Color(0xFFC6DDDA),
      ),
      UserRole.superadmin => (
        context.ink,
        context.surface,
        context.ink,
      ),
    };

    return Semantics(
      label: 'Role: ${role.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: border),
        ),
        child: Text(
          role.label,
          style: TextStyle(
            color: foreground,
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
