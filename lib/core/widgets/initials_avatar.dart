import 'package:flutter/material.dart';

import '../theme/theme_colors.dart';

/// Avatar bulat berisi inisial nama, mis. "Budi Santoso" -> "BS".
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({
    super.key,
    required this.name,
    this.size = 34,
    this.muted = false,
  });

  final String name;
  final double size;

  /// Versi abu-abu (mis. untuk karyawan yang belum melihat).
  final bool muted;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    final first = parts.first[0];
    final last = parts.length > 1 ? parts.last[0] : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: muted ? context.surfaceMuted : context.accentSubtle,
          shape: BoxShape.circle,
          border: muted ? Border.all(color: context.border) : null,
        ),
        child: Text(
          initialsOf(name),
          style: TextStyle(
            color: muted ? context.inkSecondary : context.accentText,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
