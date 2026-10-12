import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../data/app_exception.dart';
import '../auth/widgets/password_rules_list.dart';

/// Ganti password dari dalam aplikasi. Pop dengan `true` bila berhasil.
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  final _newFocus = FocusNode();
  final _confirmFocus = FocusNode();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    _newFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    try {
      await AppScope.of(context).profile.changePassword(
        SessionScope.userOf(context),
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      _currentController.clear();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Widget _toggle(bool obscured, VoidCallback onToggle) =>
      PasswordVisibilityToggle(obscured: obscured, onToggle: onToggle);

  @override
  Widget build(BuildContext context) {
    final username = SessionScope.userOf(context).username;
    return PageScaffold(
      title: 'Ganti password',
      maxWidth: 480,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteractionIfError,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                FormErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
              LabeledField(
                label: 'Password saat ini',
                child: TextFormField(
                  controller: _currentController,
                  enabled: !_isSubmitting,
                  autofocus: true,
                  obscureText: _obscureCurrent,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: Validators.loginPassword,
                  onFieldSubmitted: (_) => _newFocus.requestFocus(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: _toggle(
                      _obscureCurrent,
                      () => setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg + 4),
              LabeledField(
                label: 'Password baru',
                child: TextFormField(
                  controller: _newController,
                  focusNode: _newFocus,
                  enabled: !_isSubmitting,
                  obscureText: _obscureNew,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: (v) {
                    final base = Validators.newPassword(() => username)(v);
                    if (base != null) return base;
                    if (v == _currentController.text) {
                      return 'Harus berbeda dari password saat ini';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_reset, size: 20),
                    suffixIcon: _toggle(
                      _obscureNew,
                      () => setState(() => _obscureNew = !_obscureNew),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PasswordRulesList(
                controller: _newController,
                username: username,
              ),
              const SizedBox(height: AppSpacing.md),
              LabeledField(
                label: 'Konfirmasi password baru',
                child: TextFormField(
                  controller: _confirmController,
                  focusNode: _confirmFocus,
                  enabled: !_isSubmitting,
                  obscureText: _obscureConfirm,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: Validators.confirmPassword(
                    () => _newController.text,
                  ),
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_reset, size: 20),
                    suffixIcon: _toggle(
                      _obscureConfirm,
                      () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Simpan password',
                loadingLabel: 'Menyimpan…',
                isLoading: _isSubmitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
