import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/auth_repository.dart';
import 'widgets/auth_shell.dart';
import 'widgets/password_strength_meter.dart';

/// Wajib ganti password (login pertama / setelah reset admin).
/// Tidak bisa dilewati maupun kembali. Pop `true` bila berhasil.
class ForcePasswordPage extends StatefulWidget {
  const ForcePasswordPage({
    super.key,
    required this.user,
    required this.currentPassword,
  });

  final AuthUser user;

  /// Password sementara saat ini (diisi otomatis, tidak perlu diketik).
  final String currentPassword;

  @override
  State<ForcePasswordPage> createState() => _ForcePasswordPageState();
}

class _ForcePasswordPageState extends State<ForcePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  late final TextEditingController _usernameController;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(text: widget.user.username);
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  String get _username => _usernameController.text;

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.of(context).profile.changePassword(
            widget.user,
            currentPassword: widget.currentPassword,
            newPassword: _passwordController.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal menyimpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: false,
      child: AuthShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Buat password baru',
              style: textTheme.headlineSmall?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              'Halo ${widget.user.firstName}, akunmu baru dibuat. '
              'Buat password pribadimu dulu sebelum masuk.',
              style: textTheme.bodyMedium?.copyWith(height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_error != null) ...[
              FormErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PasswordStrengthMeter(
                    password: _passwordController,
                    username: _usernameController,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    onChanged: (_) => setState(() {}),
                    validator: Validators.registrationPassword(() => _username),
                    decoration: const InputDecoration(
                      labelText: 'Password baru',
                      hintText: 'Minimal 8 karakter + angka',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _confirmController,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    validator: Validators.confirmPassword(
                      () => _passwordController.text,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Ulangi password baru',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Simpan password',
              loadingLabel: 'Menyimpan…',
              isLoading: _saving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
