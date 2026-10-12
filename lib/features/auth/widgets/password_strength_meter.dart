import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/validators.dart';

/// Indikator kekuatan password (Lemah / Sedang / Kuat) + daftar kriteria
/// yang tercentang langsung saat mengetik.
///
/// [username] ikut didengarkan karena password tidak boleh memuat username.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({
    super.key,
    required this.password,
    required this.username,
  });

  final TextEditingController password;
  final TextEditingController username;

  Color _color(BuildContext context, PasswordStrength? s) => switch (s) {
    null => context.border,
    PasswordStrength.weak => context.danger,
    PasswordStrength.medium => AppColors.warningIndicator,
    PasswordStrength.strong => context.success,
  };

  Color _textColor(BuildContext context, PasswordStrength? s) => switch (s) {
    null => context.inkTertiary,
    PasswordStrength.weak => context.danger,
    PasswordStrength.medium => context.warning,
    PasswordStrength.strong => context.success,
  };

  static String _hint(PasswordStrength? s) {
    final strongRequired =
        Validators.minimumPasswordStrength == PasswordStrength.strong;
    return switch (s) {
      null => 'Gabungkan huruf besar, huruf kecil, angka, dan simbol.',
      PasswordStrength.weak =>
        'Penuhi semua ketentuan wajib agar password bisa dipakai.',
      PasswordStrength.medium =>
        strongRequired
            ? 'Hampir. Tambahkan simbol & buat 12+ karakter.'
            : 'Sudah bisa dipakai. Tambahkan simbol & buat 12+ karakter '
                  'agar kuat.',
      PasswordStrength.strong => 'Password Anda kuat.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return ListenableBuilder(
      listenable: Listenable.merge([password, username]),
      builder: (context, _) {
        final text = password.text;
        final name = username.text;
        final strength = text.isEmpty
            ? null
            : passwordStrength(text, username: name);
        final filled = strength == null ? 0 : strength.index + 1;
        final color = _color(context, strength);

        return Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: context.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.panel),
            border: Border.all(color: context.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        'Kekuatan password',
                        style: textTheme.bodySmall,
                      ),
                    ),
                  ),
                  Semantics(
                    liveRegion: true,
                    label:
                        'Kekuatan password: '
                        '${strength?.label ?? 'belum diisi'}',
                    excludeSemantics: true,
                    child: Text(
                      strength?.label ?? '—',
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _textColor(context, strength),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ExcludeSemantics(
                child: Row(
                  children: [
                    for (
                      var i = 0;
                      i < PasswordStrength.values.length;
                      i++
                    ) ...[
                      if (i > 0) const SizedBox(width: 4),
                      Expanded(
                        child: AnimatedContainer(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          height: 5,
                          decoration: BoxDecoration(
                            color: i < filled
                                ? color
                                : context.border,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _hint(strength),
                style: textTheme.bodySmall?.copyWith(fontSize: 12.5),
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  final mandatory = _CriteriaGroup(
                    title: 'Wajib',
                    criteria: [
                      for (final c in passwordCriteria)
                        if (c.mandatory) c,
                    ],
                    password: text,
                    username: name,
                  );
                  final bonus = _CriteriaGroup(
                    title: 'Agar kuat',
                    criteria: [
                      for (final c in passwordCriteria)
                        if (!c.mandatory) c,
                    ],
                    password: text,
                    username: name,
                  );
                  if (constraints.maxWidth < 340) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        mandatory,
                        const SizedBox(height: AppSpacing.md),
                        bonus,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 11, child: mandatory),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(flex: 9, child: bonus),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CriteriaGroup extends StatelessWidget {
  const _CriteriaGroup({
    required this.title,
    required this.criteria,
    required this.password,
    required this.username,
  });

  final String title;
  final List<PasswordCriterion> criteria;
  final String password;
  final String username;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(title.toUpperCase(), style: textTheme.labelSmall),
        ),
        const SizedBox(height: 6),
        for (final c in criteria)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: _CriterionRow(
              label: c.label,
              // Kriteria "tidak memuat username" baru berarti setelah
              // ada isian.
              passed: password.isNotEmpty && c.test(password, username),
            ),
          ),
      ],
    );
  }
}

class _CriterionRow extends StatelessWidget {
  const _CriterionRow({required this.label, required this.passed});

  final String label;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Semantics(
      label: '$label, ${passed ? 'terpenuhi' : 'belum terpenuhi'}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              passed ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 16,
              color: passed ? context.success : context.borderStrong,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: style?.copyWith(
                fontSize: 12.5,
                color: passed ? context.ink : context.inkSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
