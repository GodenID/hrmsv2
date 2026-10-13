import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/widgets/animated_check.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/app_exception.dart';
import '../../../data/notification_repository.dart';

/// Siaran Super Admin: judul + isi bebas ke seluruh / sebagian karyawan.
/// Terkirim sebagai notifikasi dalam aplikasi + push FCM (realtime).
class BroadcastPage extends StatefulWidget {
  const BroadcastPage({super.key});

  @override
  State<BroadcastPage> createState() => _BroadcastPageState();
}

class _BroadcastPageState extends State<BroadcastPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  BroadcastAudience _audience = BroadcastAudience.all;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final title = _titleController.text.trim();
      final result = await AppScope.of(context).notifications.broadcast(
            SessionScope.userOf(context),
            title: title,
            body: _bodyController.text.trim(),
            audience: _audience,
          );
      if (!mounted) return;
      unawaited(AppHaptics.confirm());
      await showSuccessSheet(
        context,
        title: 'Siaran terkirim',
        message:
            '${result.sent} karyawan menerima "$title" '
            '(${result.devices} perangkat push). Terkirim realtime.',
      );
      if (!mounted) return;
      setState(() {
        _titleController.clear();
        _bodyController.clear();
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Gagal mengirim. Periksa koneksi lalu coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PageScaffold(
      title: 'Siaran',
      maxWidth: 640,
      busy: _sending,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              FormErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _titleController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 120,
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? 'Judul minimal 3 karakter.'
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Judul',
                      hintText: 'mis. Apel pagi dipindah ke aula',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _bodyController,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 500,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Isi siaran wajib diisi.'
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Isi',
                      hintText: 'Tulis pengumuman bebas di sini…',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<BroadcastAudience>(
                    initialValue: _audience,
                    items: [
                      for (final a in BroadcastAudience.values)
                        DropdownMenuItem(value: a, child: Text(a.label)),
                    ],
                    onChanged: (a) =>
                        setState(() => _audience = a ?? _audience),
                    decoration: const InputDecoration(
                      labelText: 'Sasaran',
                      prefixIcon: Icon(Icons.groups_outlined, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Terkirim sebagai notifikasi + push ke HP yang sedang login. '
              'Penerima dihitung dari karyawan aktif saat dikirim.',
              style: textTheme.bodySmall?.copyWith(height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Kirim siaran',
              loadingLabel: 'Mengirim…',
              isLoading: _sending,
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}
