import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/validators.dart';
import '../../data/auth_repository.dart';
import 'widgets/auth_shell.dart';
import '../../core/widgets/form_widgets.dart';
import 'widgets/password_rules_list.dart';
import 'widgets/step_progress.dart';

enum _ResetStep { username, nik, newPassword, done }

/// Alur lupa password 3 langkah:
/// 1. Username  ->  2. NIK KTP  ->  3. Password baru  ->  selesai.
///
/// Saat selesai, halaman ditutup dengan mengembalikan username agar
/// halaman login bisa mengisinya otomatis.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({
    super.key,
    required this.authRepository,
    this.initialUsername,
  });

  final AuthRepository authRepository;
  final String? initialUsername;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  static const _stepLabels = ['Username', 'Verifikasi KTP', 'Password baru'];

  final _usernameFormKey = GlobalKey<FormState>();
  final _nikFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  late final TextEditingController _usernameController;
  final _nikController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _confirmFocus = FocusNode();

  _ResetStep _step = _ResetStep.username;
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  /// Username yang sudah lolos langkah 1.
  String? _verifiedUsername;

  /// Token dari langkah 2, wajib untuk langkah 3.
  String? _resetToken;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: widget.initialUsername ?? '',
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _nikController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Aksi
  // ---------------------------------------------------------------------------

  Future<void> _run(Future<void> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await action();
    } on AuthException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitUsername() async {
    if (_isSubmitting) return;
    if (!(_usernameFormKey.currentState?.validate() ?? false)) return;
    final username = _usernameController.text.trim();

    await _run(() async {
      await widget.authRepository.verifyUsername(username);
      if (!mounted) return;
      setState(() {
        _verifiedUsername = username;
        _nikController.clear();
        _step = _ResetStep.nik;
      });
    });
  }

  Future<void> _submitNik() async {
    if (_isSubmitting) return;
    if (!(_nikFormKey.currentState?.validate() ?? false)) return;

    await _run(() async {
      final token = await widget.authRepository.verifyNik(
        username: _verifiedUsername!,
        nik: _nikController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _resetToken = token;
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        _step = _ResetStep.newPassword;
      });
    });
  }

  Future<void> _submitNewPassword() async {
    if (_isSubmitting) return;
    if (!(_passwordFormKey.currentState?.validate() ?? false)) return;

    await _run(() async {
      await widget.authRepository.resetPassword(
        resetToken: _resetToken!,
        newPassword: _newPasswordController.text,
      );
      if (!mounted) return;
      setState(() {
        _resetToken = null;
        _nikController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
        _step = _ResetStep.done;
      });
    });
  }

  /// Kembali ke langkah 1 (mis. salah memasukkan username).
  void _restart() {
    setState(() {
      _step = _ResetStep.username;
      _verifiedUsername = null;
      _resetToken = null;
      _errorMessage = null;
      _nikController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    });
  }

  void _backToLogin({bool success = false}) {
    Navigator.of(context).pop(success ? _verifiedUsername : null);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return PopScope(
      // Cegah keluar tidak sengaja saat request sedang berjalan. Di layar
      // sukses, tombol back sistem tetap membawa username ke halaman login.
      canPop: !_isSubmitting && _step != _ResetStep.done,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == _ResetStep.done) _backToLogin(success: true);
      },
      child: AuthShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Di layar sukses, aksi kembali sudah diwakili tombol utama.
            if (_step != _ResetStep.done) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isSubmitting ? null : _backToLogin,
                  style: TextButton.styleFrom(
                    foregroundColor: context.inkSecondary,
                    padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
                  ),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Kembali ke halaman masuk'),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            StepProgress(steps: _stepLabels, currentIndex: _step.index),
            const SizedBox(height: AppSpacing.xxl),
            AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topLeft,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_step),
                child: switch (_step) {
                  _ResetStep.username => _buildUsernameStep(),
                  _ResetStep.nik => _buildNikStep(),
                  _ResetStep.newPassword => _buildPasswordStep(),
                  _ResetStep.done => _buildDoneStep(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _errorBlock() {
    if (_errorMessage == null) return const [];
    return [
      FormErrorBanner(message: _errorMessage!),
      const SizedBox(height: AppSpacing.xl),
    ];
  }

  Widget _buildUsernameStep() {
    return Form(
      key: _usernameFormKey,
      autovalidateMode: AutovalidateMode.onUserInteractionIfError,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const FormHeader(
            title: 'Lupa password',
            description: Text(
              'Masukkan username akun Anda. Setelah itu kami akan meminta '
              'NIK KTP untuk memastikan akun ini benar milik Anda.',
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          ..._errorBlock(),
          LabeledField(
            label: 'Username',
            child: TextFormField(
              controller: _usernameController,
              enabled: !_isSubmitting,
              autofocus: true,
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              validator: Validators.username,
              onFieldSubmitted: (_) => _submitUsername(),
              decoration: const InputDecoration(
                hintText: 'contoh: budi.santoso',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          PrimaryButton(
            label: 'Lanjutkan',
            loadingLabel: 'Memeriksa username…',
            isLoading: _isSubmitting,
            onPressed: _submitUsername,
          ),
        ],
      ),
    );
  }

  Widget _buildNikStep() {
    final textTheme = Theme.of(context).textTheme;

    return Form(
      key: _nikFormKey,
      autovalidateMode: AutovalidateMode.onUserInteractionIfError,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const FormHeader(
            title: 'Verifikasi identitas',
            description: Text(
              'Masukkan 16 digit NIK sesuai KTP yang terdaftar di data '
              'karyawan untuk akun berikut.',
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _AccountRow(
            username: _verifiedUsername ?? '',
            onChange: _isSubmitting ? null : _restart,
          ),
          const SizedBox(height: AppSpacing.xl),
          ..._errorBlock(),
          LabeledField(
            label: 'NIK (Nomor Induk Kependudukan)',
            child: TextFormField(
              controller: _nikController,
              enabled: !_isSubmitting,
              autofocus: true,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              maxLength: 16,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(16),
              ],
              validator: Validators.nik,
              onFieldSubmitted: (_) => _submitNik(),
              style: textTheme.bodyLarge?.copyWith(
                letterSpacing: 1.4,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                hintText: '16 digit sesuai KTP',
                // Hint tidak ikut letterSpacing lebar milik angka NIK.
                hintStyle: TextStyle(
                  color: context.inkTertiary,
                  fontSize: 14,
                  letterSpacing: 0,
                ),
                prefixIcon: Icon(Icons.badge_outlined, size: 20),
                helperText: 'Hanya digunakan untuk verifikasi akun.',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Verifikasi NIK',
            loadingLabel: 'Mencocokkan data…',
            isLoading: _isSubmitting,
            onPressed: _submitNik,
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordStep() {
    return Form(
      key: _passwordFormKey,
      autovalidateMode: AutovalidateMode.onUserInteractionIfError,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const FormHeader(
            title: 'Buat password baru',
            description: Text(
              'Identitas Anda sudah terverifikasi. Buat password baru yang '
              'belum pernah dipakai sebelumnya.',
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _AccountRow(
            username: _verifiedUsername ?? '',
            verified: true,
            onChange: _isSubmitting ? null : _restart,
          ),
          const SizedBox(height: AppSpacing.xl),
          ..._errorBlock(),
          AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                LabeledField(
                  label: 'Password baru',
                  child: TextFormField(
                    controller: _newPasswordController,
                    enabled: !_isSubmitting,
                    autofocus: true,
                    obscureText: _obscureNew,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    enableSuggestions: false,
                    validator: Validators.newPassword(
                      () => _verifiedUsername ?? '',
                    ),
                    onFieldSubmitted: (_) => _confirmFocus.requestFocus(),
                    decoration: InputDecoration(
                      hintText: 'Masukkan password baru',
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: PasswordVisibilityToggle(
                        obscured: _obscureNew,
                        onToggle: () =>
                            setState(() => _obscureNew = !_obscureNew),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                PasswordRulesList(
                  controller: _newPasswordController,
                  username: _verifiedUsername ?? '',
                ),
                const SizedBox(height: AppSpacing.md),
                LabeledField(
                  label: 'Konfirmasi password baru',
                  child: TextFormField(
                    controller: _confirmPasswordController,
                    focusNode: _confirmFocus,
                    enabled: !_isSubmitting,
                    obscureText: _obscureConfirm,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.done,
                    autocorrect: false,
                    enableSuggestions: false,
                    validator: Validators.confirmPassword(
                      () => _newPasswordController.text,
                    ),
                    onFieldSubmitted: (_) => _submitNewPassword(),
                    decoration: InputDecoration(
                      hintText: 'Ulangi password baru',
                      prefixIcon: const Icon(Icons.lock_outline, size: 20),
                      suffixIcon: PasswordVisibilityToggle(
                        obscured: _obscureConfirm,
                        onToggle: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          PrimaryButton(
            label: 'Simpan password',
            loadingLabel: 'Menyimpan…',
            isLoading: _isSubmitting,
            onPressed: _submitNewPassword,
          ),
        ],
      ),
    );
  }

  Widget _buildDoneStep() {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.successSubtle,
              borderRadius: BorderRadius.circular(AppRadius.panel),
            ),
            child: Icon(
              Icons.check_rounded,
              color: context.success,
              size: 26,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Semantics(
          liveRegion: true,
          child: const FormHeader(
            title: 'Password berhasil diperbarui',
            description: Text(
              'Silakan kembali ke halaman masuk dan gunakan password baru '
              'Anda.',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text.rich(
          TextSpan(
            text: 'Akun: ',
            children: [
              TextSpan(
                text: _verifiedUsername ?? '',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          style: textTheme.bodyMedium?.copyWith(color: context.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.xxl),
        PrimaryButton(
          label: 'Masuk sekarang',
          onPressed: () => _backToLogin(success: true),
        ),
      ],
    );
  }
}

/// Baris ringkas yang menunjukkan akun sedang diproses + tombol "Ganti".
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.username,
    required this.onChange,
    this.verified = false,
  });

  final String username;
  final VoidCallback? onChange;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: context.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: context.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_circle_outlined,
            size: 20,
            color: context.inkSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  verified ? 'Akun terverifikasi' : 'Akun',
                  style: textTheme.bodySmall?.copyWith(fontSize: 12),
                ),
                Text(
                  username,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (verified) ...[
            Icon(
              Icons.verified_outlined,
              size: 18,
              color: context.success,
            ),
            const SizedBox(width: 4),
          ],
          TextButton(onPressed: onChange, child: const Text('Ganti')),
        ],
      ),
    );
  }
}
