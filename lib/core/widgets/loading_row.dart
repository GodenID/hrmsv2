import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'brand_loading.dart';

/// Indikator memuat sebaris: logo berdenyut + keterangan.
class LoadingRow extends StatelessWidget {
  const LoadingRow({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Row(
          children: [
            const BrandPulseLogo(size: 34),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }
}
