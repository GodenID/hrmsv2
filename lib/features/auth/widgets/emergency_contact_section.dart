import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/platform_services.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/auth_repository.dart';
import '../../../data/employee_repository.dart';
import 'form_subsection.dart';

/// Kotak "Kontak darurat": nama, hubungan, nomor HP, plus tombol
/// "Pilih dari kontak HP" (Android & iOS). Dipakai di pendaftaran dan di
/// Profil › Ubah data kontak. Harus berada di dalam [Form].
class EmergencyContactSection extends StatefulWidget {
  const EmergencyContactSection({
    super.key,
    required this.nameController,
    required this.phoneController,
    required this.relation,
    required this.onRelationChanged,
    required this.ownPhone,
    required this.platform,
    this.enabled = true,
    this.onSubmitted,
  });

  final TextEditingController nameController;
  final TextEditingController phoneController;
  final EmergencyRelation? relation;
  final ValueChanged<EmergencyRelation?> onRelationChanged;

  /// Nomor HP karyawan sendiri (nomor darurat harus berbeda).
  final String Function() ownPhone;
  final PlatformServices platform;
  final bool enabled;

  /// Dipanggil saat menekan Enter di field terakhir.
  final VoidCallback? onSubmitted;

  @override
  State<EmergencyContactSection> createState() =>
      _EmergencyContactSectionState();
}

class _EmergencyContactSectionState extends State<EmergencyContactSection> {
  static const Widget _gap = SizedBox(height: AppSpacing.lg);

  String? _pickedName;
  bool _isPicking = false;

  Future<void> _pick() async {
    if (_isPicking || !widget.enabled) return;
    setState(() => _isPicking = true);
    try {
      final picked = await widget.platform.pickContactPhone();
      if (!mounted || picked == null) return;
      final phone = PhoneNumbers.clean(picked.phone);
      if (phone.replaceAll('+', '').isEmpty) {
        showAppSnackBar(
          context,
          'Kontak yang dipilih tidak memiliki nomor telepon.',
        );
        return;
      }
      setState(() {
        if (picked.name.isNotEmpty) widget.nameController.text = picked.name;
        widget.phoneController.text = phone;
        _pickedName = widget.nameController.text;
      });
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          'Daftar kontak tidak dapat dibuka. Isi data kontak darurat secara '
          'manual.',
        );
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return FormSubsection(
      icon: Icons.health_and_safety_outlined,
      title: 'Kontak darurat',
      description:
          'Orang yang dihubungi bila terjadi keadaan darurat saat Anda '
          'bekerja.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ..._buildPicker(enabled),
          LabeledField(
            label: 'Nama kontak darurat',
            child: TextFormField(
              controller: widget.nameController,
              enabled: enabled,
              textCapitalization: TextCapitalization.words,
              inputFormatters: [LengthLimitingTextInputFormatter(80)],
              textInputAction: TextInputAction.next,
              validator: RegistrationRules.validateEmergencyName,
              decoration: const InputDecoration(
                hintText: 'mis. Sri Wahyuni',
                prefixIcon: Icon(Icons.person_outline, size: 20),
              ),
            ),
          ),
          _gap,
          LabeledField(
            label: 'Hubungan',
            child: DropdownButtonFormField<EmergencyRelation>(
              initialValue: widget.relation,
              isExpanded: true,
              hint: const Text('Pilih hubungan'),
              items: [
                for (final r in EmergencyRelation.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              validator: (v) =>
                  v == null ? 'Pilih hubungan dengan kontak darurat' : null,
              onChanged: enabled ? widget.onRelationChanged : null,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.people_alt_outlined, size: 20),
              ),
            ),
          ),
          _gap,
          LabeledField(
            label: 'Nomor HP kontak darurat',
            child: TextFormField(
              controller: widget.phoneController,
              enabled: enabled,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d\s+-]')),
                LengthLimitingTextInputFormatter(20),
              ],
              textInputAction: TextInputAction.done,
              validator: (v) {
                if ((v ?? '').trim().isEmpty) {
                  return 'Nomor HP kontak darurat wajib diisi';
                }
                return EmployeeRules.validatePhone(v) ??
                    RegistrationRules.emergencyPhoneConflict(
                      v!,
                      widget.ownPhone(),
                    );
              },
              onFieldSubmitted: (_) => widget.onSubmitted?.call(),
              decoration: const InputDecoration(
                hintText: 'mis. 0813-2222-3333',
                prefixIcon: Icon(Icons.phone_outlined, size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPicker(bool enabled) {
    final textTheme = Theme.of(context).textTheme;
    if (!widget.platform.supportsContactPicker) {
      return [
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
                'Pilih dari kontak tersedia di aplikasi Android & iOS. Di '
                'perangkat ini, isi data secara manual.',
                style: textTheme.bodySmall?.copyWith(height: 1.45),
              ),
            ),
          ],
        ),
        _gap,
      ];
    }
    return [
      OutlinedButton.icon(
        onPressed: enabled && !_isPicking ? _pick : null,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
          backgroundColor: context.surface,
        ),
        icon: _isPicking
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.contacts_outlined, size: 18),
        label: Text(_isPicking ? 'Membuka kontak…' : 'Pilih dari kontak HP'),
      ),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: widget.nameController,
        builder: (context, value, _) {
          final picked = _pickedName;
          if (picked == null || value.text != picked) {
            return _gap;
          }
          return Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, AppSpacing.lg),
            child: Semantics(
              liveRegion: true,
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: context.success,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Diisi dari kontak HP. Pilih hubungan, lalu periksa '
                      'nomornya.',
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ];
  }
}
