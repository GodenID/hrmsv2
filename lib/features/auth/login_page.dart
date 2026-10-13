import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_routes.dart';
import '../../core/app_scope.dart';
import '../../core/push_notifications.dart';
import '../../core/session_storage.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/validators.dart';
import '../../data/api/api_auth_repository.dart' show ApiConfig;
import '../../data/api/api_notification_repository.dart';
import '../../data/auth_repository.dart';
import 'complete_profile_page.dart';
import 'force_password_page.dart';
import 'widgets/auth_shell.dart';
import '../../core/widgets/form_widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.authRepository,
    required this.sessionStorage,
  });

  final AuthRepository authRepository;
  final SessionStorage sessionStorage;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _errorMessage = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    final notifications = AppScope.of(context).notifications;

    try {
      final session = await widget.authRepository.login(
        username: _usernameController.text.trim(),
        password: _passwordController.text,
      );
      try {
        // Agar tetap masuk setelah refresh / aplikasi dibuka ulang.
        await widget.sessionStorage.writeToken(session.token);
      } catch (_) {
        // Penyimpanan tidak tersedia (mis. mode privat): tetap lanjut,
        // hanya saja sesi tidak bertahan setelah refresh.
      }
      // Daftarkan token push perangkat (nonblokir, gagal = push mati).
      try {
        if (notifications is ApiNotificationRepository) {
          unawaited(
            PushNotifications.syncSessionToken(
              baseUrl: ApiConfig.baseUrl,
              readToken: widget.sessionStorage.readToken,
              syncToken: notifications.syncPushToken,
            ),
          );
        }
      } catch (_) {}
      if (!mounted) return;
      await _enter(context, session, _passwordController.text);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _isSubmitting = false;
      });
      _passwordController.clear();
      _passwordFocus.requestFocus();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu coba lagi.';
        _isSubmitting = false;
      });
    }
  }

  /// Masuk + onboarding wajib (ganti password & lengkapi profil)
  /// untuk akun bulk / setelah reset admin.
  Future<void> _enter(
    BuildContext context,
    AuthSession session,
    String password,
  ) async {
    var user = session.user;
    final navigator = Navigator.of(context);
    if (user.mustChangePassword) {
      final ok = await navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => ForcePasswordPage(
            user: user,
            currentPassword: password,
          ),
        ),
      );
      if (ok != true || !context.mounted) return;
      user = AuthUser(
        username: user.username,
        fullName: user.fullName,
        role: user.role,
        profileIncomplete: user.profileIncomplete,
      );
    }
    if (user.profileIncomplete) {
      final ok = await navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => CompleteProfilePage(user: user),
        ),
      );
      if (ok != true || !context.mounted) return;
    }
    // Segarkan sesi (nama & flag terbaru) lalu masuk beranda.
    AuthSession fresh = session;
    try {
      final token = await widget.sessionStorage.readToken();
      if (token != null) {
        final me = await widget.authRepository.restoreSession(token);
        fresh = AuthSession(token: token, user: me);
      }
    } catch (_) {
      // Token sesi login tetap dipakai bila pemulihan gagal.
    }
    if (!context.mounted) return;
    navigator.pushReplacementNamed(AppRoutes.home, arguments: fresh);
  }

  Future<void> _openForgotPassword() async {
    final resetUsername = await Navigator.of(context).pushNamed<String>(
      AppRoutes.forgotPassword,
      arguments: _usernameController.text.trim(),
    );
    if (!mounted || resetUsername == null) return;

    // Kembali dari alur reset yang berhasil: isi username, fokus ke password.
    setState(() => _errorMessage = null);
    _usernameController.text = resetUsername;
    _passwordController.clear();
    _passwordFocus.requestFocus();
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        width: isWide ? 420 : null,
        content: const Text(
          'Password berhasil diperbarui. Silakan masuk dengan password baru.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return AuthShell(
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteractionIfError,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const FormHeader(
                title: 'Masuk',
                description: Text(
                  'Gunakan username dan password akun karyawan Anda.',
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              if (_errorMessage != null) ...[
                FormErrorBanner(message: _errorMessage!),
                const SizedBox(height: AppSpacing.xl),
              ],
              LabeledField(
                label: 'Username',
                child: TextFormField(
                  controller: _usernameController,
                  enabled: !_isSubmitting,
                  autofillHints: const [AutofillHints.username],
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: Validators.username,
                  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                  decoration: const InputDecoration(
                    hintText: 'contoh: budi.santoso',
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg + 4),
              LabeledField(
                label: 'Password',
                trailing: TextButton(
                  onPressed: _isSubmitting ? null : _openForgotPassword,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Lupa password?'),
                ),
                child: TextFormField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  enabled: !_isSubmitting,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  validator: Validators.loginPassword,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: 'Masukkan password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: PasswordVisibilityToggle(
                      obscured: _obscurePassword,
                      onToggle: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              PrimaryButton(
                label: 'Masuk',
                loadingLabel: 'Memverifikasi…',
                isLoading: _isSubmitting,
                onPressed: _submit,
              ),
              // Akun dibuat oleh Super Admin (menu Karyawan). Belum punya
              // akun? Hubungi HR / atasan langsung.
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: context.inkSecondary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Akun terkunci atau dinonaktifkan? '
                      'Hubungi administrator HR di kantor Anda.',
                      style: textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
