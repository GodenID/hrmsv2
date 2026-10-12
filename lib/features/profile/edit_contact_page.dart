import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../data/auth_repository.dart';
import '../../data/employee_repository.dart';
import '../../data/profile_repository.dart';
import '../auth/widgets/emergency_contact_section.dart';

/// Karyawan memperbarui nomor HP, alamat, dan kontak darurat sendiri.
/// Pop dengan [EmployeeProfile] terbaru bila tersimpan.
class EditContactPage extends StatefulWidget {
  const EditContactPage({super.key, required this.initial});

  final EmployeeProfile initial;

  @override
  State<EditContactPage> createState() => _EditContactPageState();
}

class _EditContactPageState extends State<EditContactPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _emergencyName;
  late final TextEditingController _emergencyPhone;
  EmergencyRelation? _relation;

  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    final ec = p.emergencyContact;
    _phone = TextEditingController(text: p.phone);
    _address = TextEditingController(text: p.address);
    _emergencyName = TextEditingController(text: ec?.name);
    _emergencyPhone = TextEditingController(text: ec?.phone);
    _relation = ec?.relation;
  }

  @override
  void dispose() {
    for (final c in [_phone, _address, _emergencyName, _emergencyPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    try {
      final updated = await AppScope.of(context).profile.updateContactInfo(
        SessionScope.userOf(context),
        draft: ContactInfoDraft(
          phone: _phone.text.trim(),
          address: _address.text.trim(),
          emergencyContact: EmergencyContact(
            name: _emergencyName.text.trim(),
            relation: _relation!,
            phone: _emergencyPhone.text.trim(),
          ),
        ),
      );
      if (mounted) Navigator.of(context).pop(updated);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu '
              'coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = !_isSubmitting;

    return PopScope(
      canPop: !_isSubmitting,
      child: PageScaffold(
        title: 'Ubah data kontak',
        maxWidth: 560,
        busy: _isSubmitting,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteractionIfError,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Perbarui nomor HP, alamat, dan kontak darurat Anda. '
                'Perubahan langsung terlihat oleh Tim HR.',
                style: textTheme.bodyMedium?.copyWith(
                  color: context.inkSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (_error != null) ...[
                FormErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
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
              const SizedBox(height: AppSpacing.lg),
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
              const SizedBox(height: AppSpacing.lg),
              EmergencyContactSection(
                nameController: _emergencyName,
                phoneController: _emergencyPhone,
                relation: _relation,
                onRelationChanged: (r) => setState(() => _relation = r),
                ownPhone: () => _phone.text,
                platform: AppScope.of(context).platform,
                enabled: enabled,
                onSubmitted: _submit,
              ),
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
                      'Nama, NIK, jenis kelamin, email, dan data kepegawaian '
                      'diubah oleh Tim HR.',
                      style: textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Simpan perubahan',
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
