import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../../core/widgets/panel.dart';
import '../../data/event_repository.dart';

/// Semua hari dalam rentang event, termasuk akhir pekan.
List<DateTime> eventDays(EventItem e) {
  final days = <DateTime>[];
  var d = WorkCalendar.dateOnly(e.startDate);
  final last = WorkCalendar.dateOnly(e.endDate);
  while (!d.isAfter(last)) {
    days.add(d);
    d = DateTime(d.year, d.month, d.day + 1);
  }
  return days;
}

/// Hari yang benar-benar diikuti partisipan. Kosong berarti semua hari.
List<DateTime> crewAttendanceDays(EventItem e, CrewMember m) =>
    m.dates.isEmpty ? eventDays(e) : m.dates;

/// Mis. "3 hari · 26, 27, 28 Okt 2026".
String crewAttendanceLabel(EventItem e, CrewMember m) {
  final days = crewAttendanceDays(e, m);
  final labels = days.map((d) => DateFormatId.shortDate(d)).join(', ');
  return days.length == 1 ? '1 hari · $labels' : '${days.length} hari · $labels';
}

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
    required this.roles,
    required this.selected,
    required this.onSelect,
    this.enabled = true,
  });

  final List<CrewRole> roles;
  final CrewRole? selected;
  final ValueChanged<CrewRole> onSelect;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final role in roles)
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
