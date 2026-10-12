import 'package:flutter/material.dart';

import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/validators.dart';

/// Daftar ketentuan WAJIB password yang tercentang secara langsung saat
/// mengetik — cermin persis mistar yang ditegakkan validator & server
/// (termasuk larangan memuat username).
class PasswordRulesList extends StatelessWidget {
  const PasswordRulesList({
    super.key,
    required this.controller,
    required this.username,
  });

  final TextEditingController controller;

  /// Username yang tidak boleh dimuat password.
  final String username;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final criterion in passwordCriteria.where((c) => c.mandatory))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _RuleRow(
                  label: criterion.label,
                  passed: criterion.test(value.text, username),
                  style: textTheme.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.label,
    required this.passed,
    required this.style,
  });

  final String label;
  final bool passed;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label, ${passed ? 'terpenuhi' : 'belum terpenuhi'}',
      excludeSemantics: true,
      child: Row(
        children: [
          Icon(
            passed ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 16,
            color: passed ? context.success : context.borderStrong,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: style?.copyWith(
              color: passed ? context.ink : context.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
