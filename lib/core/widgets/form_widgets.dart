import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_colors.dart';

/// Label di atas field + field itu sendiri. Label digabung ke semantik
/// field agar pembaca layar mengumumkannya dengan benar.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;

  /// Widget opsional di kanan label (mis. tautan "Lupa password?").
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelMedium;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Row(
            children: [
              Expanded(
                child: ExcludeSemantics(child: Text(label, style: labelStyle)),
              ),
              ?trailing,
            ],
          ),
        ),
        const SizedBox(height: 2),
        Semantics(label: label, child: child),
      ],
    );
  }
}

/// Judul + deskripsi di bagian atas setiap formulir.
class FormHeader extends StatelessWidget {
  const FormHeader({super.key, required this.title, this.description});

  final String title;
  final Widget? description;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: textTheme.headlineSmall),
        ),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.sm),
          DefaultTextStyle.merge(
            style: textTheme.bodyMedium?.copyWith(
              color: context.inkSecondary,
              height: 1.5,
            ),
            child: description!,
          ),
        ],
      ],
    );
  }
}

/// Banner pesan galat di dalam formulir (bukan snackbar, agar tidak hilang
/// sebelum dibaca).
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: context.dangerSubtle,
          borderRadius: BorderRadius.circular(AppRadius.panel),
          border: Border.all(color: AppColors.dangerBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.error_outline,
                size: 18,
                color: context.danger,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: const Color(0xFF7A271A), fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tombol aksi utama dengan status memuat.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.loadingLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? loadingLabel;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Text(loadingLabel ?? 'Memproses…'),
              ],
            )
          : Text(label),
    );
  }
}

/// Tombol ikon untuk menampilkan/menyembunyikan password.
class PasswordVisibilityToggle extends StatelessWidget {
  const PasswordVisibilityToggle({
    super.key,
    required this.obscured,
    required this.onToggle,
  });

  final bool obscured;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tooltip = obscured ? 'Tampilkan password' : 'Sembunyikan password';
    return IconButton(
      onPressed: onToggle,
      tooltip: tooltip,
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 20,
      ),
    );
  }
}
