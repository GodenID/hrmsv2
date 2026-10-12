import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';

/// Menampilkan password sementara SEKALI, dengan tombol salin.
Future<void> showTemporaryPasswordDialog(
  BuildContext context, {
  required String title,
  required String fullName,
  required String username,
  required String password,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TemporaryPasswordDialog(
      title: title,
      fullName: fullName,
      username: username,
      password: password,
    ),
  );
}

class _TemporaryPasswordDialog extends StatefulWidget {
  const _TemporaryPasswordDialog({
    required this.title,
    required this.fullName,
    required this.username,
    required this.password,
  });

  final String title;
  final String fullName;
  final String username;
  final String password;

  @override
  State<_TemporaryPasswordDialog> createState() =>
      _TemporaryPasswordDialogState();
}

class _TemporaryPasswordDialogState extends State<_TemporaryPasswordDialog> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.password));
    if (mounted) setState(() => _copied = true);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Password sementara untuk ${widget.fullName} '
              '(@${widget.username}):',
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
              decoration: BoxDecoration(
                color: context.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: context.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      widget.password,
                      style: textTheme.titleMedium?.copyWith(
                        fontFamily: 'monospace',
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _copy,
                    icon: Icon(
                      _copied ? Icons.check : Icons.copy_outlined,
                      size: 18,
                    ),
                    label: Text(_copied ? 'Disalin' : 'Salin'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              liveRegion: true,
              child: Text(
                'Password ini hanya ditampilkan sekali. Serahkan langsung ke '
                'karyawan (jangan lewat grup chat), lalu minta ia segera '
                'menggantinya di Profil › Ganti password.',
                style: textTheme.bodySmall?.copyWith(height: 1.5),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(minimumSize: const Size(96, 44)),
          child: const Text('Selesai'),
        ),
      ],
    );
  }
}
