import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/date_format_id.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/panel.dart';
import '../../../core/widgets/picker_field.dart';
import '../../../data/auth_repository.dart';
import '../../../data/employee_repository.dart';
import '../../../data/profile_repository.dart';
import 'widgets/auth_shell.dart';

/// Lengkapi data diri (login pertama akun bulk). Tidak bisa dilewati
/// maupun kembali. Pop `true` bila tersimpan.
class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({super.key, required this.user, this.onCompleted});

  final AuthUser user;

  /// Bila diisi, dipanggil saat berhasil (pengganti pop). Dipakai alur
  /// startup yang sudah mengganti rute (tidak ada yang bisa di-pop).
  final VoidCallback? onCompleted;

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nikController = TextEditingController();
  final _birthPlaceController = TextEditingController();
  final _addressController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _ecNameController = TextEditingController();
  final _ecPhoneController = TextEditingController();

  DateTime? _birthDate;
  Gender _gender = Gender.male;
  EmergencyRelation _relation = EmergencyRelation.parent;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.user.fullName != 'Karyawan Baru') {
      _nameController.text = widget.user.fullName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nikController.dispose();
    _birthPlaceController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _ecNameController.dispose();
    _ecPhoneController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(today.year - 25, 1, 1),
      firstDate: DateTime(today.year - 70),
      lastDate: today,
      helpText: 'Tanggal lahir',
    );
    if (picked != null && mounted) setState(() => _birthDate = picked);
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_birthDate == null) {
      setState(() => _error = 'Pilih tanggal lahir.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.of(context).profile.completeProfile(
            widget.user,
            draft: ProfileCompletionDraft(
              fullName: _nameController.text.trim(),
              nik: _nikController.text.trim(),
              birthPlace: _birthPlaceController.text.trim(),
              birthDate: _birthDate!,
              gender: _gender,
              address: _addressController.text.trim(),
              email: _emailController.text.trim(),
              phone: _phoneController.text.trim(),
              emergencyContact: EmergencyContact(
                name: _ecNameController.text.trim(),
                relation: _relation,
                phone: _ecPhoneController.text.trim(),
              ),
            ),
          );
      if (mounted) {
        if (widget.onCompleted != null) {
          widget.onCompleted!();
        } else {
          Navigator.of(context).pop(true);
        }
      }
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
              'Lengkapi data diri',
              style: textTheme.headlineSmall?.copyWith(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              'Satu kali saja. Data ini dipakai HR untuk administrasi '
              'kepegawaianmu.',
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
                  const SectionLabel('Data diri'),
                  TextFormField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    validator: EmployeeRules.validateFullName,
                    decoration: const InputDecoration(
                      labelText: 'Nama lengkap (KTP)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _nikController,
                    keyboardType: TextInputType.number,
                    validator: EmployeeRules.validateNik,
                    decoration: const InputDecoration(
                      labelText: 'NIK KTP (16 digit)',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _birthPlaceController,
                          textCapitalization: TextCapitalization.words,
                          validator: RegistrationRules.validateBirthPlace,
                          decoration: const InputDecoration(
                            labelText: 'Tempat lahir',
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: LabeledField(
                          label: 'Tgl. lahir',
                          child: PickerField(
                            valueText: _birthDate == null
                                ? null
                                : DateFormatId.shortDate(_birthDate!),
                            hint: 'Pilih',
                            icon: Icons.event_outlined,
                            onTap: _pickBirthDate,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<Gender>(
                    initialValue: _gender,
                    items: [
                      for (final g in Gender.values)
                        DropdownMenuItem(value: g, child: Text(g.label)),
                    ],
                    onChanged: (g) => setState(() => _gender = g ?? _gender),
                    decoration: const InputDecoration(
                      labelText: 'Jenis kelamin',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionLabel('Kontak'),
                  TextFormField(
                    controller: _addressController,
                    maxLines: 2,
                    validator: RegistrationRules.validateAddress,
                    decoration: const InputDecoration(
                      labelText: 'Alamat domisili',
                      hintText: 'Jalan, RT/RW, kelurahan, kota',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: EmployeeRules.validateEmail,
                    decoration: const InputDecoration(
                      labelText: 'Email pribadi',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    validator: EmployeeRules.validatePhone,
                    decoration: const InputDecoration(
                      labelText: 'Nomor HP',
                      hintText: 'mis. 0812-3456-7890',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionLabel('Kontak darurat'),
                  TextFormField(
                    controller: _ecNameController,
                    textCapitalization: TextCapitalization.words,
                    validator: RegistrationRules.validateEmergencyName,
                    decoration: const InputDecoration(
                      labelText: 'Nama',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<EmergencyRelation>(
                    initialValue: _relation,
                    items: [
                      for (final r in EmergencyRelation.values)
                        DropdownMenuItem(value: r, child: Text(r.label)),
                    ],
                    onChanged: (r) =>
                        setState(() => _relation = r ?? _relation),
                    decoration: const InputDecoration(
                      labelText: 'Hubungan',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _ecPhoneController,
                    keyboardType: TextInputType.phone,
                    validator: EmployeeRules.validatePhone,
                    decoration: const InputDecoration(
                      labelText: 'Nomor HP darurat',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Simpan data diri',
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
