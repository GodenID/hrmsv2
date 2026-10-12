import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/platform_services.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/utils/validators.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/picker_field.dart';
import '../../core/widgets/role_badge.dart';
import '../../data/auth_repository.dart';
import '../../data/employee_repository.dart';
import 'widgets/auth_shell.dart';
import 'widgets/emergency_contact_section.dart';
import 'widgets/password_strength_meter.dart';
import 'widgets/registration_widgets.dart';
import 'widgets/step_progress.dart';

enum _Step { account, personal, contact, division, employment, review, done }

/// Pendaftaran akun karyawan 5 langkah:
/// 1. Akun (username + password)  2. Data diri  3. Kontak & kontak darurat
/// 4. Divisi  5. Tinjau  ->  selesai.
///
/// Akun baru selalu ber-role Staff. Saat selesai, halaman ditutup dengan
/// mengembalikan username agar halaman login bisa mengisinya otomatis.
class RegisterPage extends StatefulWidget {
  const RegisterPage({
    super.key,
    required this.authRepository,
    this.platform = const PlatformServices(),
  });

  final AuthRepository authRepository;
  final PlatformServices platform;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  static const _stepLabels = [
    'Akun',
    'Data diri',
    'Kontak',
    'Divisi',
    'Status',
    'Tinjau',
  ];

  static const Map<Division, IconData> _divisionIcons = {
    Division.financeAccounting: Icons.account_balance_outlined,
    Division.hrIt: Icons.groups_outlined,
    Division.businessDevelopment: Icons.trending_up,
    Division.produksiPrasasti: Icons.precision_manufacturing_outlined,
    Division.produksiMutiari: Icons.factory_outlined,
  };

  static const Map<EmploymentStatus, IconData> _statusIcons = {
    EmploymentStatus.permanent: Icons.verified_outlined,
    EmploymentStatus.contract: Icons.description_outlined,
    EmploymentStatus.internship: Icons.school_outlined,
    EmploymentStatus.external: Icons.handshake_outlined,
  };

  /// Kunci baru setiap pindah langkah, agar langkah yang sedang
  /// beranimasi keluar tidak berbagi GlobalKey dengan langkah baru.
  GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final _contentKey = GlobalKey();

  // Akun
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  /// Username terakhir yang dinyatakan tersedia oleh server.
  String? _checkedUsername;

  // Data diri
  final _fullName = TextEditingController();
  final _nik = TextEditingController();
  final _birthPlace = TextEditingController();
  final _address = TextEditingController();
  Gender? _gender;
  DateTime? _birthDate;
  String? _birthDateError;

  // Kontak
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  EmergencyRelation? _relation;

  // Divisi, status & tinjau
  Division? _division;
  EmploymentStatus? _employmentStatus;
  final _months = TextEditingController();
  bool _declared = false;
  bool _showDeclarationError = false;
  bool _privacyConsent = false;
  bool _showPrivacyError = false;

  _Step _step = _Step.account;
  bool _isSubmitting = false;
  String? _error;
  RegisteredAccount? _result;

  List<TextEditingController> get _controllers => [
    _username,
    _password,
    _confirmPassword,
    _fullName,
    _nik,
    _birthPlace,
    _months,
    _address,
    _email,
    _phone,
    _emergencyName,
    _emergencyPhone,
  ];

  bool get _hasInput =>
      _controllers.any((c) => c.text.trim().isNotEmpty) ||
      _gender != null ||
      _birthDate != null ||
      _relation != null ||
      _division != null ||
      _employmentStatus != null ||
      _declared ||
      _privacyConsent;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Navigasi
  // ---------------------------------------------------------------------------

  void _goTo(_Step step, {String? error}) {
    setState(() {
      _step = step;
      _error = error;
      _formKey = GlobalKey<FormState>();
    });
    // Langkah baru selalu dimulai dari atas.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _contentKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      final position = Scrollable.maybeOf(ctx)?.position;
      if (position == null || position.pixels <= 0) return;
      if (reduceMotion) {
        position.jumpTo(0);
      } else {
        position.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _back() {
    if (_isSubmitting || _step == _Step.account || _step == _Step.done) return;
    _goTo(_Step.values[_step.index - 1]);
  }

  Future<void> _leave() async {
    if (_isSubmitting) return;
    if (_hasInput) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Batalkan pendaftaran?'),
          content: const Text(
            'Data yang sudah Anda isi akan hilang dan perlu diisi ulang.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: context.inkSecondary,
              ),
              child: const Text('Lanjut mengisi'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size(96, 44),
                backgroundColor: context.danger,
                foregroundColor: context.isDark ? context.surface : Colors.white,
              ),
              child: const Text('Batalkan'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    Navigator.of(context).pop();
  }

  void _finish() => Navigator.of(context).pop(_result?.username);

  // ---------------------------------------------------------------------------
  // Aksi
  // ---------------------------------------------------------------------------

  static _Step _stepFor(RegistrationField field) => switch (field) {
    RegistrationField.username || RegistrationField.password => _Step.account,
    RegistrationField.fullName ||
    RegistrationField.nik ||
    RegistrationField.birthPlace ||
    RegistrationField.birthDate ||
    RegistrationField.address => _Step.personal,
    RegistrationField.email ||
    RegistrationField.phone ||
    RegistrationField.emergencyContact => _Step.contact,
    RegistrationField.employmentStatus => _Step.employment,
  };

  /// Menjalankan panggilan server. Galat ditampilkan sebagai banner di
  /// langkah yang perlu diperbaiki. Mengembalikan true bila berhasil.
  Future<bool> _run(Future<void> Function() action) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await action();
      return true;
    } on RegistrationException catch (e) {
      if (!mounted) return false;
      final target = e.field == null ? _step : _stepFor(e.field!);
      if (target == _step) {
        setState(() => _error = e.message);
      } else {
        _goTo(target, error: e.message);
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu '
              'coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
    return false;
  }

  Future<void> _next() async {
    if (_isSubmitting) return;
    if (_step == _Step.done) return _finish();
    setState(() => _error = null);
    final valid = _formKey.currentState?.validate() ?? false;

    switch (_step) {
      case _Step.account:
        if (!valid) return;
        final name = _username.text.trim().toLowerCase();
        if (_checkedUsername != name) {
          final ok = await _run(
            () => widget.authRepository.checkUsernameAvailable(name),
          );
          if (!ok || !mounted) return;
          _checkedUsername = name;
        }
        _goTo(_Step.personal);
      case _Step.personal:
        if (!valid) return;
        // Picker tanggal lahir tidak ikut validasi Form: dicek manual.
        final birthError =
            RegistrationRules.validateBirthDate(_birthDate) ??
            (_birthDate == null || _gender == null
                ? null
                : RegistrationRules.birthDateMismatch(
                    _birthDate!,
                    _nik.text.trim(),
                    _gender!,
                  ));
        if (birthError != null) {
          setState(() => _birthDateError = birthError);
          return;
        }
        setState(() => _birthDateError = null);
        _goTo(_Step.contact);
      case _Step.contact:
        if (valid) _goTo(_Step.division);
      case _Step.division:
        if (valid) _goTo(_Step.employment);
      case _Step.employment:
        if (valid) _goTo(_Step.review);
      case _Step.review:
        await _submit();
      case _Step.done:
        break;
    }
  }

  /// Pemilih tanggal lahir. Batas atas = hari ini minus usia minimum agar
  /// tanggal yang tidak memenuhi syarat tidak bisa dipilih sejak awal
  /// (validasi server tetap jadi penegak terakhir).
  Future<void> _pickBirthDate() async {
    if (_isSubmitting) return;
    final today = DateTime.now();
    final latest = DateTime(
      today.year - RegistrationRules.minimumAgeYears,
      today.month,
      today.day,
    );
    final fallback = DateTime(today.year - 25, today.month, today.day);
    final initial = _birthDate ?? (fallback.isAfter(latest) ? latest : fallback);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: latest,
      helpText: 'Pilih tanggal lahir',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _birthDate = DateTime(picked.year, picked.month, picked.day);
      _birthDateError = RegistrationRules.validateBirthDate(_birthDate);
    });
  }

  Future<void> _submit() async {
    if (!_declared || !_privacyConsent) {
      setState(() {
        _showDeclarationError = true;
        _showPrivacyError = true;
      });
      return;
    }
    final draft = RegistrationDraft(
      username: _username.text.trim().toLowerCase(),
      password: _password.text,
      fullName: _fullName.text.trim(),
      nik: _nik.text.trim(),
      birthPlace: _birthPlace.text.trim(),
      // Sudah divalidasi di langkah Data diri.
      birthDate: _birthDate!,
      gender: _gender!,
      address: _address.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
      emergencyContact: EmergencyContact(
        name: _emergencyName.text.trim(),
        relation: _relation!,
        phone: _emergencyPhone.text.trim(),
      ),
      division: _division!,
      employmentStatus: _employmentStatus!,
      // Sudah divalidasi di langkah Status.
      contractMonths: _employmentStatus!.requiresDuration
          ? int.parse(_months.text.trim())
          : null,
      privacyConsent: true,
    );

    RegisteredAccount? result;
    final ok = await _run(() async {
      result = await widget.authRepository.register(draft);
    });
    if (!ok || !mounted) return;
    // Data sensitif tidak perlu disimpan lebih lama di memori formulir.
    _password.clear();
    _confirmPassword.clear();
    _nik.clear();
    _result = result;
    _goTo(_Step.done);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return PopScope(
      // Tombol back sistem: mundur satu langkah, bukan langsung keluar.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _isSubmitting) return;
        if (_step == _Step.done) return _finish();
        if (_step != _Step.account) return _back();
        _leave();
      },
      child: AuthShell(
        child: Column(
          key: _contentKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_step != _Step.done) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isSubmitting ? null : _leave,
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
            StepProgress(
              steps: _stepLabels,
              currentIndex: _step.index,
              showLabels: true,
              onStepTap: _isSubmitting ? null : (i) => _goTo(_Step.values[i]),
            ),
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
                  _Step.account => _buildAccountStep(),
                  _Step.personal => _buildPersonalStep(),
                  _Step.contact => _buildContactStep(),
                  _Step.division => _buildDivisionStep(),
                  _Step.employment => _buildEmploymentStep(),
                  _Step.review => _buildReviewStep(),
                  _Step.done => _buildDoneStep(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const Widget _fieldGap = SizedBox(height: AppSpacing.lg);

  /// Kerangka setiap langkah: judul, banner galat, isi, tombol navigasi.
  Widget _stepForm({
    required String title,
    required String description,
    required List<Widget> children,
  }) {
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteractionIfError,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FormHeader(title: title, description: Text(description)),
          const SizedBox(height: AppSpacing.xl),
          if (_error != null) ...[
            FormErrorBanner(message: _error!),
            const SizedBox(height: AppSpacing.xl),
          ],
          ...children,
          const SizedBox(height: AppSpacing.xxl),
          _buildNavButtons(),
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    final isReview = _step == _Step.review;
    return Row(
      children: [
        if (_step != _Step.account) ...[
          OutlinedButton.icon(
            onPressed: _isSubmitting ? null : _back,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Kembali'),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: PrimaryButton(
            label: isReview ? 'Daftar sekarang' : 'Lanjut',
            loadingLabel: switch (_step) {
              _Step.account => 'Memeriksa username…',
              _ => 'Mendaftarkan akun…',
            },
            isLoading: _isSubmitting,
            onPressed: _next,
          ),
        ),
      ],
    );
  }

  // --- Langkah 1: Akun -------------------------------------------------------

  Widget _buildAccountStep() {
    final enabled = !_isSubmitting;
    return _stepForm(
      title: 'Buat akun',
      description:
          'Username dan password ini Anda pakai untuk masuk ke Prasasti '
          'Connect.',
      children: [
        AutofillGroup(
          // Jangan tawarkan simpan password sebelum akun benar-benar dibuat.
          onDisposeAction: AutofillContextAction.cancel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              LabeledField(
                label: 'Username',
                child: TextFormField(
                  controller: _username,
                  enabled: enabled,
                  autofocus: true,
                  autofillHints: const [AutofillHints.newUsername],
                  autocorrect: false,
                  enableSuggestions: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
                    _LowerCaseFormatter(),
                    LengthLimitingTextInputFormatter(30),
                  ],
                  textInputAction: TextInputAction.next,
                  validator: EmployeeRules.validateUsername,
                  decoration: const InputDecoration(
                    hintText: 'mis. budi.santoso',
                    prefixIcon: Icon(Icons.alternate_email, size: 20),
                    helperText:
                        'Huruf kecil, angka, titik, atau garis bawah. Tidak '
                        'bisa diubah setelah akun dibuat.',
                  ),
                ),
              ),
              _fieldGap,
              LabeledField(
                label: 'Password',
                child: TextFormField(
                  controller: _password,
                  enabled: enabled,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.newPassword],
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.next,
                  validator: Validators.registrationPassword(
                    () => _username.text,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Buat password yang kuat',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: PasswordVisibilityToggle(
                      obscured: _obscurePassword,
                      onToggle: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PasswordStrengthMeter(password: _password, username: _username),
              _fieldGap,
              LabeledField(
                label: 'Konfirmasi password',
                child: TextFormField(
                  controller: _confirmPassword,
                  enabled: enabled,
                  obscureText: _obscureConfirm,
                  autofillHints: const [AutofillHints.newPassword],
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Ulangi password Anda';
                    }
                    if (v != _password.text) {
                      return 'Konfirmasi tidak sama dengan password';
                    }
                    return null;
                  },
                  onFieldSubmitted: (_) => _next(),
                  decoration: InputDecoration(
                    hintText: 'Ketik ulang password',
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
      ],
    );
  }

  // --- Langkah 2: Data diri --------------------------------------------------

  Widget _buildPersonalStep() {
    final enabled = !_isSubmitting;
    final textTheme = Theme.of(context).textTheme;
    return _stepForm(
      title: 'Data diri',
      description:
          'Isi sesuai KTP. Data ini dipakai Tim HR untuk administrasi '
          'kepegawaian.',
      children: [
        LabeledField(
          label: 'Nama lengkap',
          child: TextFormField(
            controller: _fullName,
            enabled: enabled,
            autofocus: true,
            autofillHints: const [AutofillHints.name],
            textCapitalization: TextCapitalization.words,
            inputFormatters: [LengthLimitingTextInputFormatter(80)],
            textInputAction: TextInputAction.next,
            validator: EmployeeRules.validateFullName,
            decoration: const InputDecoration(
              hintText: 'Sesuai KTP',
              prefixIcon: Icon(Icons.person_outline, size: 20),
            ),
          ),
        ),
        _fieldGap,
        LabeledField(
          label: 'NIK (Nomor Induk Kependudukan)',
          child: TextFormField(
            controller: _nik,
            enabled: enabled,
            keyboardType: TextInputType.number,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 16,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(16),
            ],
            textInputAction: TextInputAction.next,
            validator: EmployeeRules.validateNik,
            style: textTheme.bodyLarge?.copyWith(
              letterSpacing: 1.4,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            decoration: InputDecoration(
              hintText: '16 digit sesuai KTP',
              hintStyle: TextStyle(
                color: context.inkTertiary,
                fontSize: 14,
                letterSpacing: 0,
              ),
              prefixIcon: Icon(Icons.badge_outlined, size: 20),
              helperText: 'Juga dipakai untuk verifikasi saat lupa password.',
            ),
          ),
        ),
        _fieldGap,
        LabeledField(
          label: 'Tempat lahir',
          child: TextFormField(
            controller: _birthPlace,
            enabled: enabled,
            textCapitalization: TextCapitalization.words,
            inputFormatters: [
              LengthLimitingTextInputFormatter(
                RegistrationRules.birthPlaceMaxLength,
              ),
            ],
            textInputAction: TextInputAction.next,
            validator: RegistrationRules.validateBirthPlace,
            decoration: const InputDecoration(
              hintText: 'mis. Bandung',
              prefixIcon: Icon(Icons.place_outlined, size: 20),
            ),
          ),
        ),
        _fieldGap,
        LabeledField(
          label: 'Tanggal lahir',
          child: PickerField(
            valueText: _birthDate == null
                ? null
                : DateFormatId.dayMonthYear(_birthDate!),
            hint: 'Pilih tanggal',
            icon: Icons.cake_outlined,
            errorText: _birthDateError,
            enabled: enabled,
            onTap: _pickBirthDate,
          ),
        ),
        _fieldGap,
        LabeledField(
          label: 'Jenis kelamin',
          child: ChoiceFormField<Gender>(
            options: Gender.values,
            columns: 2,
            labelOf: (g) => g.label,
            initialValue: _gender,
            enabled: enabled,
            validator: (v) => v == null ? 'Pilih jenis kelamin' : null,
            onChanged: (g) => setState(() => _gender = g),
          ),
        ),
        _fieldGap,
        LabeledField(
          label: 'Alamat lengkap',
          child: TextFormField(
            controller: _address,
            enabled: enabled,
            autofillHints: const [AutofillHints.fullStreetAddress],
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            minLines: 3,
            maxLines: 5,
            maxLength: RegistrationRules.addressMaxLength,
            validator: RegistrationRules.validateAddress,
            decoration: const InputDecoration(
              hintText:
                  'Jalan, nomor rumah, RT/RW, kelurahan, kecamatan, '
                  'kota/kabupaten',
              hintMaxLines: 2,
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }

  // --- Langkah 3: Kontak -----------------------------------------------------

  Widget _buildContactStep() {
    final enabled = !_isSubmitting;
    return _stepForm(
      title: 'Kontak',
      description:
          'Pastikan email dan nomor HP aktif. Tim HR memakainya untuk '
          'menghubungi Anda.',
      children: [
        LabeledField(
          label: 'Email',
          child: TextFormField(
            controller: _email,
            enabled: enabled,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            autocorrect: false,
            enableSuggestions: false,
            inputFormatters: [LengthLimitingTextInputFormatter(80)],
            textInputAction: TextInputAction.next,
            validator: EmployeeRules.validateEmail,
            decoration: const InputDecoration(
              hintText: 'nama@email.com',
              prefixIcon: Icon(Icons.mail_outline, size: 20),
            ),
          ),
        ),
        _fieldGap,
        LabeledField(
          label: 'Nomor HP',
          child: TextFormField(
            controller: _phone,
            enabled: enabled,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[\d\s+-]')),
              LengthLimitingTextInputFormatter(20),
            ],
            textInputAction: TextInputAction.next,
            validator: EmployeeRules.validatePhone,
            decoration: const InputDecoration(
              hintText: 'mis. 0812-3456-7890',
              prefixIcon: Icon(Icons.phone_iphone, size: 20),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        EmergencyContactSection(
          nameController: _emergencyName,
          phoneController: _emergencyPhone,
          relation: _relation,
          onRelationChanged: (r) => setState(() => _relation = r),
          ownPhone: () => _phone.text,
          platform: widget.platform,
          enabled: enabled,
          onSubmitted: _next,
        ),
      ],
    );
  }

  // --- Langkah 4: Divisi -----------------------------------------------------

  Widget _buildDivisionStep() {
    final textTheme = Theme.of(context).textTheme;
    return _stepForm(
      title: 'Divisi',
      description: 'Pilih divisi tempat Anda bekerja di Prasasti Group.',
      children: [
        Semantics(
          label: 'Divisi',
          child: ChoiceFormField<Division>(
            options: Division.values,
            labelOf: (d) => d.label,
            iconOf: (d) => _divisionIcons[d]!,
            initialValue: _division,
            enabled: !_isSubmitting,
            validator: (v) => v == null ? 'Pilih divisi Anda' : null,
            onChanged: (d) => setState(() => _division = d),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: context.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.panel),
            border: Border.all(color: context.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 20,
                  color: context.inkSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Role awal', style: textTheme.labelMedium),
                        const SizedBox(width: AppSpacing.sm),
                        const RoleBadge(role: UserRole.staff),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Semua akun baru terdaftar sebagai Staff. Super Admin '
                      'dapat menaikkan atau menurunkan role Anda setelah akun '
                      'dibuat.',
                      style: textTheme.bodySmall?.copyWith(height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Langkah 5: Status kepegawaian -----------------------------------------

  Widget _buildEmploymentStep() {
    final monthsRequired = _employmentStatus?.requiresDuration ?? false;
    return _stepForm(
      title: 'Status kepegawaian',
      description:
          'Pilih status kerja Anda di Prasasti Group. Status PKWT dan '
          'magang meminta durasi dalam bulan.',
      children: [
        Semantics(
          label: 'Status kepegawaian',
          child: ChoiceFormField<EmploymentStatus>(
            options: EmploymentStatus.values,
            labelOf: (s) => s.label,
            iconOf: (s) => _statusIcons[s]!,
            initialValue: _employmentStatus,
            enabled: !_isSubmitting,
            validator: (s) => s == null ? 'Pilih status kepegawaian Anda' : null,
            onChanged: (s) => setState(() => _employmentStatus = s),
          ),
        ),
        if (monthsRequired) ...[
          _fieldGap,
          LabeledField(
            label: 'Durasi (bulan)',
            child: TextFormField(
              controller: _months,
              enabled: !_isSubmitting,
              keyboardType: TextInputType.number,
              autocorrect: false,
              enableSuggestions: false,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              textInputAction: TextInputAction.done,
              validator: (v) => RegistrationRules.validateContractMonths(
                v,
                _employmentStatus,
              ),
              decoration: InputDecoration(
                hintText: 'mis. 3',
                prefixIcon: const Icon(
                  Icons.calendar_month_outlined,
                  size: 20,
                ),
                helperText: _employmentStatus?.durationHint,
              ),
              onFieldSubmitted: (_) => _next(),
            ),
          ),
        ],
      ],
    );
  }

  // --- Langkah 6: Tinjau -----------------------------------------------------

  static String _groupNik(String nik) => nik.length == 16
      ? '${nik.substring(0, 4)} ${nik.substring(4, 8)} '
            '${nik.substring(8, 12)} ${nik.substring(12)}'
      : nik;

  Widget _buildReviewStep() {
    final textTheme = Theme.of(context).textTheme;
    final strength = passwordStrength(_password.text, username: _username.text);
    final editable = !_isSubmitting;
    VoidCallback? edit(_Step step) => editable ? () => _goTo(step) : null;
    const gap = SizedBox(height: AppSpacing.md);

    return _stepForm(
      title: 'Tinjau data',
      description:
          'Periksa kembali sebelum mendaftar. Ketuk "Ubah" untuk memperbaiki '
          'bagian tertentu.',
      children: [
        ReviewSection(
          icon: Icons.key_outlined,
          title: 'Akun',
          onEdit: edit(_Step.account),
          children: [
            ReviewRow(label: 'Username', value: _username.text.trim()),
            ReviewRow(
              label: 'Password',
              // Wrap: aman untuk ukuran teks besar di layar sempit.
              valueWidget: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    '••••••••',
                    style: textTheme.bodyMedium?.copyWith(letterSpacing: 1.5),
                  ),
                  StatusChip(
                    label: strength.label,
                    tone: strength == PasswordStrength.strong
                        ? ChipTone.success
                        : ChipTone.warning,
                  ),
                ],
              ),
            ),
          ],
        ),
        gap,
        ReviewSection(
          icon: Icons.person_outline,
          title: 'Data diri',
          onEdit: edit(_Step.personal),
          children: [
            ReviewRow(label: 'Nama lengkap', value: _fullName.text.trim()),
            ReviewRow(
              label: 'NIK',
              valueWidget: Text(
                _groupNik(_nik.text.trim()),
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            ReviewRow(
              label: 'Tempat lahir',
              value: _birthPlace.text.trim(),
            ),
            ReviewRow(
              label: 'Tanggal lahir',
              value: _birthDate == null
                  ? '—'
                  : DateFormatId.dayMonthYear(_birthDate!),
            ),
            ReviewRow(label: 'Jenis kelamin', value: _gender?.label ?? '—'),
            ReviewRow(label: 'Alamat', value: _address.text.trim()),
          ],
        ),
        gap,
        ReviewSection(
          icon: Icons.contact_phone_outlined,
          title: 'Kontak',
          onEdit: edit(_Step.contact),
          children: [
            ReviewRow(label: 'Email', value: _email.text.trim()),
            ReviewRow(label: 'Nomor HP', value: _phone.text.trim()),
            ReviewRow(
              label: 'Kontak darurat',
              valueWidget: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _emergencyName.text.trim(),
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${_relation?.label ?? '—'} · '
                    '${_emergencyPhone.text.trim()}',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        gap,
        ReviewSection(
          icon: Icons.apartment_outlined,
          title: 'Divisi & role',
          onEdit: edit(_Step.division),
          children: [
            ReviewRow(label: 'Divisi', value: _division?.label ?? '—'),
            const ReviewRow(
              label: 'Role',
              valueWidget: RoleBadge(role: UserRole.staff),
            ),
          ],
        ),
        gap,
        ReviewSection(
          icon: Icons.assignment_ind_outlined,
          title: 'Status kepegawaian',
          onEdit: edit(_Step.employment),
          children: [
            ReviewRow(
              label: 'Status',
              value: _employmentStatus?.label ?? '—',
            ),
            if (_employmentStatus?.requiresDuration ?? false)
              ReviewRow(
                label: 'Durasi',
                value: _months.text.trim().isEmpty
                    ? '—'
                    : '${_months.text.trim()} bulan',
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _DeclarationCheck(
          text:
              'Saya menyatakan data di atas benar dan sesuai dengan dokumen '
              'resmi (KTP).',
          value: _declared,
          enabled: editable,
          errorText: _showDeclarationError && !_declared
              ? 'Centang pernyataan ini untuk melanjutkan'
              : null,
          onChanged: (v) => setState(() => _declared = v),
        ),
        const SizedBox(height: AppSpacing.md),
        _DeclarationCheck(
          text:
              'Saya menyetujui pemrosesan data pribadi saya (termasuk NIK, '
              'alamat, dan kontak darurat) untuk keperluan kepegawaian sesuai '
              'UU Pelindungan Data Pribadi.',
          value: _privacyConsent,
          enabled: editable,
          errorText: _showPrivacyError && !_privacyConsent
              ? 'Centang persetujuan ini untuk melanjutkan'
              : null,
          onChanged: (v) => setState(() => _privacyConsent = v),
          action: TextButton(
            onPressed: () => showPrivacyPolicyDialog(context),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Baca Kebijakan Privasi & S&K'),
          ),
        ),
      ],
    );
  }

  // --- Selesai ---------------------------------------------------------------

  Widget _buildDoneStep() {
    final result = _result;
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
            title: 'Pendaftaran berhasil',
            description: Text(
              'Akun Anda sudah aktif. Masuk dengan username dan password '
              'yang baru saja Anda buat.',
            ),
          ),
        ),
        if (result != null) ...[
          const SizedBox(height: AppSpacing.xl),
          ReviewSection(
            icon: Icons.badge_outlined,
            title: 'Akun baru',
            children: [
              ReviewRow(label: 'Nama', value: result.fullName),
              ReviewRow(label: 'Username', value: result.username),
              ReviewRow(label: 'Divisi', value: result.division.label),
              ReviewRow(
                label: 'Status',
                value: result.employmentStatus.displayLabel(
                  result.contractMonths,
                ),
              ),
              ReviewRow(
                label: 'Role',
                valueWidget: RoleBadge(role: result.role),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.xxl),
        PrimaryButton(label: 'Masuk sekarang', onPressed: _finish),
      ],
    );
  }
}

/// Kotak centang pernyataan (kebenaran data & persetujuan privasi).
class _DeclarationCheck extends StatelessWidget {
  const _DeclarationCheck({
    required this.text,
    required this.value,
    required this.enabled,
    required this.errorText,
    required this.onChanged,
    this.action,
  });

  final String text;
  final bool value;
  final bool enabled;
  final String? errorText;
  final ValueChanged<bool> onChanged;

  /// Mis. tombol "Baca Kebijakan Privasi" di bawah teks persetujuan.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasError = errorText != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MergeSemantics(
          child: InkWell(
            onTap: enabled ? () => onChanged(!value) : null,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: value,
                    onChanged: enabled ? (v) => onChanged(v ?? false) : null,
                    isError: hasError,
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 9),
                      child: Text(
                        text,
                        style: textTheme.bodyMedium?.copyWith(height: 1.45),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (action != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 44),
              child: action!,
            ),
          ),
        if (hasError)
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Semantics(
              liveRegion: true,
              child: Text(
                errorText!,
                style: Theme.of(context).inputDecorationTheme.errorStyle,
              ),
            ),
          ),
      ],
    );
  }
}

class _LowerCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toLowerCase());
}
