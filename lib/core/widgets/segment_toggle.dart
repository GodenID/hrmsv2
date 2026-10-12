import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/theme_colors.dart';

/// Pilihan tampilan berbentuk tab kecil, mis. "Mendatang | Selesai".
class SegmentToggle extends StatelessWidget {
  const SegmentToggle({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: context.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.panel),
            border: Border.all(color: context.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < options.length; i++)
                Semantics(
                  inMutuallyExclusiveGroup: true,
                  checked: i == selectedIndex,
                  button: true,
                  child: Material(
                    color: i == selectedIndex
                        ? context.surface
                        : Colors.transparent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      side: i == selectedIndex
                          ? BorderSide(color: context.border)
                          : BorderSide.none,
                    ),
                    child: InkWell(
                      onTap: () => onSelect(i),
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        child: Text(
                          options[i],
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: i == selectedIndex
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: i == selectedIndex
                                ? context.ink
                                : context.inkSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
