import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/widgets/panel.dart';
import '../../data/event_repository.dart';

/// Chip kategori event. Bobot visual naik sesuai ukuran event.
class EventSizeChip extends StatelessWidget {
  const EventSizeChip({super.key, required this.size, this.long = false});

  final EventSize size;

  /// true: "Event besar"; false: "Besar".
  final bool long;

  @override
  Widget build(BuildContext context) {
    final label = switch (size) {
      EventSize.overLimit => 'Melebihi batas',
      _ => long ? 'Event ${size.label.toLowerCase()}' : size.label,
    };
    final tone = switch (size) {
      EventSize.small => ChipTone.neutral,
      EventSize.medium => ChipTone.accent,
      EventSize.large => ChipTone.strong,
      EventSize.overLimit => ChipTone.warning,
    };
    return Semantics(
      label: 'Kategori: $label',
      excludeSemantics: true,
      child: StatusChip(label: label, tone: tone),
    );
  }
}

/// Pilihan bagian crew berbentuk chip (satu pilihan).
class CrewRolePicker extends StatelessWidget {
  const CrewRolePicker({
    super.key,
    required this.selected,
    required this.onSelect,
    this.enabled = true,
  });

  final CrewRole? selected;
  final ValueChanged<CrewRole> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final role in CrewRole.values)
          _RoleChip(
            label: role.label,
            selected: role == selected,
            onTap: enabled ? () => onSelect(role) : null,
          ),
      ],
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: 'Bagian $label',
      excludeSemantics: true,
      child: Material(
        color: selected ? context.accentSubtle : context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(
            color: selected ? context.accentText : context.borderStrong,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 64, minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (selected) ...[
                    Icon(
                      Icons.check,
                      size: 16,
                      color: context.accentText,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? context.accentText : context.ink,
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
