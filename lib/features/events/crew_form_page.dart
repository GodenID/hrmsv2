import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/app_exception.dart';
import '../../data/event_repository.dart';
import 'event_presentation.dart';

/// Mendaftarkan diri (atau mengubah bagian) sebagai partisipan event.
/// Nama lengkap otomatis dari akun yang login. Pop `true` bila tersimpan.
class CrewFormPage extends StatefulWidget {
  const CrewFormPage({super.key, required this.event});

  final EventItem event;

  @override
  State<CrewFormPage> createState() => _CrewFormPageState();
}

class _CrewFormPageState extends State<CrewFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _noteController = TextEditingController();
  bool _initialized = false;

  CrewMember? _existing;
  CrewRole? _role;
  String? _roleError;
  String? _error;
  bool _submitted = false;
  bool _isSubmitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _existing = widget.event.memberFor(SessionScope.userOf(context).username);
    _role = _existing?.role;
    _noteController.text = _existing?.note ?? '';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _selectRole(CrewRole role) {
    setState(() {
      _role = role;
      _roleError = null;
    });
    // Aturan "wajib keterangan" berubah sesuai bagian.
    if (_submitted) _formKey.currentState?.validate();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() {
      _submitted = true;
      _error = null;
      _roleError = _role == null ? 'Pilih bagian Anda di event ini' : null;
    });
    final formOk = _formKey.currentState?.validate() ?? false;
    if (_role == null || !formOk) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    try {
      await AppScope.of(context).events.joinEvent(
        SessionScope.userOf(context),
        id: widget.event.id,
        role: _role!,
        note: _noteController.text,
      );
      if (mounted) Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    final user = SessionScope.userOf(context);
    final textTheme = Theme.of(context).textTheme;
    final e = widget.event;
    final role = _role;
    final noteRequired = role?.requiresNote ?? false;

    return PageScaffold(
          title: _existing == null ? 'Jadi partisipan' : 'Ubah bagian saya',
      maxWidth: 560,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteractionIfError,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Panel(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.festival_outlined,
                    size: 20,
                    color: context.inkSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.name,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${DateFormatId.dateRange(e.startDate, e.endDate)}'
                          '  ·  ${e.location}',
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_error != null) ...[
              FormErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            LabeledField(
              label: 'Nama lengkap',
              child: TextFormField(
                initialValue: user.fullName,
                readOnly: true,
                enableInteractiveSelection: false,
                canRequestFocus: false,
                style: textTheme.bodyLarge?.copyWith(
                  color: context.inkSecondary,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: context.surfaceMuted,
                  prefixIcon: const Icon(Icons.person_outline, size: 20),
                  suffixIcon: const Tooltip(
                    message: 'Tidak bisa diubah',
                    child: Icon(Icons.lock_outline, size: 18),
                  ),
                  helperText: 'Otomatis dari akun yang sedang login.',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 32,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Bagian', style: textTheme.labelMedium),
              ),
            ),
            const SizedBox(height: 2),
            CrewRolePicker(
              selected: role,
              enabled: !_isSubmitting,
              onSelect: _selectRole,
            ),
            if (_roleError != null) ...[
              const SizedBox(height: 6),
              Text(
                _roleError!,
                style: textTheme.bodySmall?.copyWith(
                  color: context.danger,
                  fontSize: 12.5,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg + 4),
            LabeledField(
              label: noteRequired ? 'Keterangan' : 'Keterangan (opsional)',
              child: TextFormField(
                controller: _noteController,
                enabled: !_isSubmitting,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: (v) {
                  // Baca _role saat validasi (bukan nilai saat build), agar
                  // ganti bagian langsung memperbarui aturan wajib.
                  final required = _role?.requiresNote ?? false;
                  if (required && (v?.trim().isEmpty ?? true)) {
                    return 'Tulis PIC bagian apa, mis. PIC Venue';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  hintText: role?.noteHint ?? 'Pilih bagian terlebih dahulu',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: _existing == null ? 'Daftar' : 'Simpan perubahan',
              loadingLabel: 'Menyimpan…',
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
