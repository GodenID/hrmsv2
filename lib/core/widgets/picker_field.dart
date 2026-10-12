import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Field baca-saja yang membuka pemilih (tanggal/jam) saat diketuk.
/// Tampil identik dengan TextFormField agar formulir konsisten.
/// Bungkus dengan [LabeledField] untuk label di atasnya.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.valueText,
    required this.hint,
    required this.icon,
    required this.onTap,
    this.errorText,
    this.enabled = true,
  });

  final String? valueText;
  final String hint;
  final IconData icon;
  final VoidCallback onTap;
  final String? errorText;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      enabled: enabled,
      value: valueText ?? hint,
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: InputDecorator(
          isEmpty: valueText == null,
          decoration: InputDecoration(
            hintText: hint,
            hintMaxLines: 1,
            errorText: errorText,
            enabled: enabled,
            prefixIcon: Icon(icon, size: 20),
          ),
          child: Text(
            valueText ?? '',
            style: textTheme.bodyLarge?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
