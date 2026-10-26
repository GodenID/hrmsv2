import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_info.dart';
import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/picker_field.dart';
import '../../data/auth_repository.dart';
import '../../data/employee_repository.dart';
import '../../data/master_data.dart';
import 'widgets/temporary_password_dialog.dart';

/// Tambah (tanpa [initial]) / ubah karyawan. Pop `true` bila tersimpan.
/// Saat menambah, password sementara ditampilkan sekali sebelum kembali.
class EmployeeFormPage extends StatefulWidget {
  const EmployeeFormPage({super.key, this.initial});

  final EmployeeAccount? initial;

  @override
  State<EmployeeFormPage> createState() => _EmployeeFormPageState();
}

class _EmployeeFormPageState extends State<EmployeeFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _fullName;
  late final TextEditingController _nik;
  late final TextEditingController _employeeId;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _ecName;
  late final TextEditingController _ecPhone;
  Gender? _gender;
  Division? _division;
  String? _position;
  EmergencyRelation? _ecRelation;
  bool _initialized = false;

  /// Kontak darurat bersifat semua-atau-tidak-sama-sekali.
  bool get _ecEmpty =>
      _ecName.text.trim().isEmpty &&
      _ecPhone.text.trim().isEmpty &&
      _ecRelation == null;

  late UserRole _role;
  EmploymentStatus? _employmentStatus;
  late final TextEditingController _contractMonths;
  DateTime? _joinDate;
  String? _joinDateError;

  /// Master data untuk pilihan divisi & jabatan. null selama dimuat.
  List<MasterDivision>? _divisions;
  List<MasterPosition>? _positions;
  String? _masterError;

  /// Email diisi otomatis dari username sampai pengguna mengetik sendiri.
  bool _emailTouched = false;
  String? _error;
  bool _isSubmitting = false;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _username = TextEditingController(text: e?.username);
    _fullName = TextEditingController(text: e?.fullName);
    _nik = TextEditingController(text: e?.nik);
    _employeeId = TextEditingController(text: e?.employeeId);
    _position = e?.position;
    _division = e?.division;
    _email = TextEditingController(text: e?.email);
    _phone = TextEditingController(text: e?.phone);
    _address = TextEditingController(text: e?.address);
    _ecName = TextEditingController(text: e?.emergencyContact?.name);
    _ecPhone = TextEditingController(text: e?.emergencyContact?.phone);
    _gender = e?.gender;
    _ecRelation = e?.emergencyContact?.relation;
    _employmentStatus = e?.employmentStatus;
    _contractMonths = TextEditingController(
      text: e?.contractMonths?.toString(),
    );
    _joinDate = e?.joinDate;
    _emailTouched = _isEdit;
    if (!_isEdit) {
      _username.addListener(() {
        if (_emailTouched) return;
        final u = _username.text.trim().toLowerCase();
        _email.text = u.isEmpty ? '' : '$u@${AppInfo.emailDomain}';
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final me = SessionScope.userOf(context);
    _role = widget.initial?.role ?? UserRole.staff;
    if (!_isEdit && !me.role.canManageRole(_role)) {
      _role = me.role.assignableRoles.first;
    }
    _loadMaster();
  }

  @override
  void dispose() {
    for (final c in [
      _username,
      _fullName,
      _nik,
      _employeeId,
      _contractMonths,
      _email,
      _phone,
      _address,
      _ecName,
      _ecPhone,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMaster() async {
    setState(() => _masterError = null);
    try {
      final master = AppScope.of(context).master;
      final me = SessionScope.userOf(context);
      final divisions = await master.fetchDivisions(me);
      final positions = await master.fetchPositions(me);
      if (!mounted) return;
      setState(() {
        _divisions = divisions;
        _positions = positions;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _masterError = 'Divisi & jabatan gagal dimuat.',
        );
      }
    }
  }

  /// Pilihan divisi: yang aktif, ditambah divisi karyawan saat ini walau
  /// sudah dinonaktifkan (agar data lama tetap bisa disimpan).
  List<Division> get _divisionOptions {
    final out = <Division>[];
    for (final d in _divisions ?? const <MasterDivision>[]) {
      if (!d.active && d.code != _division?.code) continue;
      out.add(d.division);
    }
    final current = _division;
    if (current != null && !out.any((d) => d.code == current.code)) {
      out.add(current);
    }
    return out;
  }

  /// Pilihan jabatan: sama seperti divisi, jabatan lama tetap tersedia.
  List<String> get _positionOptions {
    final out = <String>[];
    for (final p in _positions ?? const <MasterPosition>[]) {
      if (!p.active && p.name != _position) continue;
      out.add(p.name);
    }
    final current = _position;
    if (current != null && current.isNotEmpty && !out.contains(current)) {
      out.add(current);
    }
    return out;
  }

  Future<void> _pickJoinDate() async {
    final today = WorkCalendar.dateOnly(DateTime.now());
    final first = DateTime(1970);
    final last = today.add(const Duration(days: 90));
    var initial = _joinDate ?? today;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Tanggal bergabung',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _joinDate = picked;
      _joinDateError = null;
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() {
      _error = null;
      _joinDateError = _joinDate == null ? 'Pilih tanggal bergabung' : null;
    });
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk || _joinDate == null) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    final repo = AppScope.of(context).employees;
    final me = SessionScope.userOf(context);
    final draft = EmployeeDraft(
      fullName: _fullName.text,
      role: _role,
      nik: _nik.text,
      employeeId: _employeeId.text,
      position: _position!,
      division: _division!,
      employmentStatus: _employmentStatus!,
      contractMonths: _employmentStatus!.requiresDuration
          ? int.tryParse(_contractMonths.text.trim())
          : null,
      joinDate: _joinDate!,
      email: _email.text,
      phone: _phone.text,
      gender: _gender,
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      emergencyContact: _ecEmpty
          ? null
          : EmergencyContact(
              name: _ecName.text.trim(),
              relation: _ecRelation!,
              phone: _ecPhone.text.trim(),
            ),
    );
    try {
      if (_isEdit) {
        await repo.updateEmployee(
          me,
          username: widget.initial!.username,
          draft: draft,
        );
        if (mounted) Navigator.of(context).pop(true);
      } else {
        final created = await repo.createEmployee(
          me,
          username: _username.text,
          draft: draft,
        );
        if (!mounted) return;
        await showTemporaryPasswordDialog(
          context,
          title: 'Akun dibuat',
          fullName: created.account.fullName,
          username: created.account.username,
          password: created.temporaryPassword,
        );
        if (mounted) Navigator.of(context).pop(true);
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
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

  Widget _gap() => const SizedBox(height: AppSpacing.sm);

  @override
  Widget build(BuildContext context) {
    final me = SessionScope.userOf(context);
    final textTheme = Theme.of(context).textTheme;
    final initial = widget.initial;
    final canChangeRole = !_isEdit || (initial?.canChangeRole ?? false);
    final roles = {...me.role.assignableRoles, _role}.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    final enabled = !_isSubmitting;

    return PopScope(
      canPop: !_isSubmitting,
      child: PageScaffold(
        title: _isEdit ? 'Ubah data karyawan' : 'Tambah karyawan',
        maxWidth: 600,
        busy: _isSubmitting,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteractionIfError,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                FormErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
              _SectionTitle('Akun'),
              LabeledField(
                label: 'Username',
                child: TextFormField(
                  controller: _username,
                  enabled: enabled && !_isEdit,
                  readOnly: _isEdit,
                  autofocus: !_isEdit,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: _isEdit ? null : 30,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._]')),
                    _LowerCaseFormatter(),
                  ],
                  textInputAction: TextInputAction.next,
                  validator: _isEdit ? null : EmployeeRules.validateUsername,
                  decoration: InputDecoration(
                    hintText: 'mis. nama.belakang',
                    prefixIcon: const Icon(Icons.alternate_email, size: 20),
                    helperText: _isEdit ? 'Username tidak bisa diubah.' : 'Dipakai untuk login. Tidak bisa diubah setelah dibuat.',
                  ),
                ),
              ),
              _gap(),
              LabeledField(
                label: 'Role',
                child: DropdownButtonFormField<UserRole>(
                  initialValue: _role,
                  items: [
                    for (final r in roles)
                      DropdownMenuItem(value: r, child: Text(r.label)),
                  ],
                  onChanged: enabled && canChangeRole && roles.length > 1
                      ? (r) => setState(() => _role = r ?? _role)
                      : null,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 20,
                    ),
                    helperText: !canChangeRole
                        ? 'Role akun Anda sendiri tidak bisa diubah.'
                        : me.role == UserRole.manager
                        ? 'Manager hanya dapat membuat akun Staff.'
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _SectionTitle('Identitas'),
              LabeledField(
                label: 'Nama lengkap',
                child: TextFormField(
                  controller: _fullName,
                  enabled: enabled,
                  maxLength: 80,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  validator: EmployeeRules.validateFullName,
                  decoration: const InputDecoration(
                    hintText: 'Sesuai KTP',
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                  ),
                ),
              ),
              _gap(),
              LabeledField(
                label: 'NIK KTP',
                child: TextFormField(
                  controller: _nik,
                  enabled: enabled,
                  keyboardType: TextInputType.number,
                  maxLength: 16,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  validator: EmployeeRules.validateNik,
                  style: textTheme.bodyLarge?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: const InputDecoration(
                    hintText: '16 digit',
                    prefixIcon: Icon(Icons.badge_outlined, size: 20),
                    helperText:
                        'Dipakai karyawan untuk verifikasi lupa password.',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _SectionTitle('Kepegawaian'),
              LabeledField(
                label: 'ID karyawan',
                child: TextFormField(
                  controller: _employeeId,
                  enabled: enabled,
                  maxLength: 20,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.next,
                  validator: EmployeeRules.validateEmployeeId,
                  decoration: const InputDecoration(
                    hintText: 'mis. PG-0201',
                    prefixIcon: Icon(Icons.tag, size: 20),
                  ),
                ),
              ),
              _gap(),
              LabeledField(
                label: 'Jabatan',
                child: DropdownButtonFormField<String>(
                  initialValue: _position,
                  isExpanded: true,
                  hint: Text(
                    _positions == null ? 'Memuat jabatan…' : 'Pilih jabatan',
                  ),
                  items: [
                    for (final p in _positionOptions)
                      DropdownMenuItem(value: p, child: Text(p)),
                  ],
                  onChanged: enabled && _positions != null
                      ? (v) => setState(() => _position = v)
                      : null,
                  validator: (v) => v == null ? 'Pilih jabatan' : null,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.work_outline, size: 20),
                    helperText:
                        'Daftar jabatan dikelola Super Admin di Master data.',
                  ),
                ),
              ),
              _gap(),
              LabeledField(
                label: 'Divisi',
                child: DropdownButtonFormField<Division>(
                  initialValue: _division,
                  isExpanded: true,
                  hint: Text(
                    _divisions == null ? 'Memuat divisi…' : 'Pilih divisi',
                  ),
                  items: [
                    for (final d in _divisionOptions)
                      DropdownMenuItem(value: d, child: Text(d.label)),
                  ],
                  onChanged: enabled && _divisions != null
                      ? (d) => setState(() => _division = d)
                      : null,
                  validator: (d) => d == null ? 'Pilih divisi' : null,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.apartment_outlined, size: 20),
                  ),
                ),
              ),
              if (_masterError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _isSubmitting ? null : _loadMaster,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: Text('$_masterError Ketuk untuk coba lagi.'),
                  ),
                ),
              ],
              _gap(),
              LabeledField(
                label: 'Status kepegawaian',
                child: DropdownButtonFormField<EmploymentStatus>(
                  initialValue: _employmentStatus,
                  items: [
                    for (final s in EmploymentStatus.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: enabled
                      ? (s) => setState(() => _employmentStatus = s)
                      : null,
                  validator: (s) => s == null ? 'Pilih status kepegawaian' : null,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.assignment_ind_outlined, size: 20),
                  ),
                ),
              ),
              if (_employmentStatus?.requiresDuration ?? false) ...[
                const SizedBox(height: AppSpacing.lg + 4),
                LabeledField(
                  label: 'Durasi (bulan)',
                  child: TextFormField(
                    controller: _contractMonths,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    autocorrect: false,
                    enableSuggestions: false,
                    maxLength: 2,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    textInputAction: TextInputAction.next,
                    validator: (v) =>
                        RegistrationRules.validateContractMonths(
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
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg + 4),
              LabeledField(
                label: 'Tanggal bergabung',
                child: PickerField(
                  valueText: _joinDate == null
                      ? null
                      : DateFormatId.longDate(_joinDate!),
                  hint: 'Pilih tanggal',
                  icon: Icons.event_outlined,
                  errorText: _joinDateError,
                  enabled: enabled,
                  onTap: _pickJoinDate,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _SectionTitle('Kontak'),
              LabeledField(
                label: 'Email',
                child: TextFormField(
                  controller: _email,
                  enabled: enabled,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLength: 80,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _emailTouched = true,
                  validator: EmployeeRules.validateEmail,
                  decoration: const InputDecoration(
                    hintText: 'nama@${AppInfo.emailDomain}',
                    prefixIcon: Icon(Icons.mail_outline, size: 20),
                  ),
                ),
              ),
              _gap(),
              LabeledField(
                label: 'Telepon',
                child: TextFormField(
                  controller: _phone,
                  enabled: enabled,
                  keyboardType: TextInputType.phone,
                  maxLength: 20,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d\s+-]')),
                  ],
                  textInputAction: TextInputAction.next,
                  validator: EmployeeRules.validatePhone,
                  decoration: const InputDecoration(
                    hintText: 'mis. 0812-3456-7890',
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _SectionTitle('Data pribadi'),
              LabeledField(
                label: 'Jenis kelamin',
                child: DropdownButtonFormField<Gender?>(
                  initialValue: _gender,
                  items: [
                    const DropdownMenuItem<Gender?>(
                      value: null,
                      child: Text('Belum diisi'),
                    ),
                    for (final g in Gender.values)
                      DropdownMenuItem<Gender?>(value: g, child: Text(g.label)),
                  ],
                  onChanged: enabled
                      ? (g) => setState(() => _gender = g)
                      : null,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.wc_outlined, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg + 4),
              LabeledField(
                label: 'Alamat (opsional)',
                child: TextFormField(
                  controller: _address,
                  enabled: enabled,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: RegistrationRules.addressMaxLength,
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? null
                      : RegistrationRules.validateAddress(v),
                  decoration: const InputDecoration(
                    hintText: 'Jalan, RT/RW, kelurahan, kecamatan, kota',
                    alignLabelWithHint: true,
                  ),
                ),
              ),
              _gap(),
              LabeledField(
                label: 'Kontak darurat (opsional)',
                child: TextFormField(
                  controller: _ecName,
                  enabled: enabled,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 80,
                  textInputAction: TextInputAction.next,
                  validator: (v) => _ecEmpty
                      ? null
                      : RegistrationRules.validateEmergencyName(v),
                  decoration: const InputDecoration(
                    hintText: 'Nama',
                    prefixIcon: Icon(
                      Icons.health_and_safety_outlined,
                      size: 20,
                    ),
                  ),
                ),
              ),
              _gap(),
              LabeledField(
                label: 'Hubungan kontak darurat',
                child: DropdownButtonFormField<EmergencyRelation?>(
                  initialValue: _ecRelation,
                  isExpanded: true,
                  hint: const Text('Pilih hubungan'),
                  items: [
                    for (final r in EmergencyRelation.values)
                      DropdownMenuItem<EmergencyRelation?>(
                        value: r,
                        child: Text(r.label),
                      ),
                  ],
                  validator: (v) => _ecEmpty || v != null
                      ? null
                      : 'Pilih hubungan dengan kontak darurat',
                  onChanged: enabled
                      ? (r) => setState(() => _ecRelation = r)
                      : null,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.people_alt_outlined, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg + 4),
              LabeledField(
                label: 'Nomor HP kontak darurat',
                child: TextFormField(
                  controller: _ecPhone,
                  enabled: enabled,
                  keyboardType: TextInputType.phone,
                  maxLength: 20,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d\s+-]')),
                  ],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) {
                    if (_ecEmpty) return null;
                    if ((v ?? '').trim().isEmpty) {
                      return 'Nomor HP kontak darurat wajib diisi';
                    }
                    return EmployeeRules.validatePhone(v) ??
                        RegistrationRules.emergencyPhoneConflict(
                          v!,
                          _phone.text,
                        );
                  },
                  decoration: const InputDecoration(
                    hintText: 'mis. 0813-2222-3333',
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                    helperText:
                        'Kosongkan nama, hubungan & nomor bila belum ada.',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (!_isEdit)
                Text(
                  'Password sementara dibuat otomatis oleh sistem dan '
                  'ditampilkan sekali setelah akun dibuat.',
                  style: textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: _isEdit ? 'Simpan perubahan' : 'Buat akun',
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: context.inkSecondary),
        ),
      ),
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
