import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../../core/widgets/animated_check.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/picker_field.dart';
import '../../data/api/api_auth_repository.dart' show ApiConfig;
import '../../data/api/api_upload_repository.dart';
import '../../data/app_exception.dart';
import '../../data/leave_repository.dart';

String _contentTypeOf(String filename) {
  switch (filename.split('.').last.toLowerCase()) {
    case 'pdf':
      return 'application/pdf';
    case 'png':
      return 'image/png';
    default:
      return 'image/jpeg';
  }
}

/// Formulir pengajuan cuti / izin / sakit. Pop dengan `true` bila terkirim.
class LeaveFormPage extends StatefulWidget {
  const LeaveFormPage({super.key, this.initialBalance});

  final LeaveBalance? initialBalance;

  @override
  State<LeaveFormPage> createState() => _LeaveFormPageState();
}

class _LeaveFormPageState extends State<LeaveFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  LeaveType _type = LeaveType.annual;
  DateTime? _start;
  DateTime? _end;
  LeaveAttachment? _attachment;
  Uint8List? _attachmentBytes;

  String? _startError;
  String? _endError;
  String? _attachmentError;
  String? _error;
  bool _isSubmitting = false;
  bool _isPicking = false;

  LeaveBalance? get _balance => widget.initialBalance;

  DateTime get _today => WorkCalendar.dateOnly(DateTime.now());
  DateTime get _firstDate => _today.subtract(Duration(days: _type.maxDaysBack));
  DateTime get _lastDate =>
      _today.add(const Duration(days: LeaveRules.maxDaysAhead));

  int get _workingDays => _start == null || _end == null
      ? 0
      : WorkCalendar.workingDaysBetween(_start!, _end!);

  bool get _needsAttachment =>
      LeaveRules.attachmentRequired(_type, _workingDays);

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  void _selectType(LeaveType type) {
    if (type == _type || _isSubmitting) return;
    final wasMaternity = _type == LeaveType.maternity;
    setState(() {
      _type = type;
      _error = null;
      if (type == LeaveType.maternity) {
        // Tanggal otomatis: 3 bulan kalender sejak hari ini.
        _start = _today;
        _end = WorkCalendar.dateOnly(
          WorkCalendar.addMonths(_today, LeaveRules.maternityMonths),
        );
        _startError = null;
        _endError = null;
      } else if (wasMaternity) {
        // Kembali ke jenis biasa: tanggal otomatis dibuang, pilih ulang.
        _start = null;
        _end = null;
      }
      // Tanggal lama mungkin di luar batas jenis baru.
      if (_start != null && _start!.isBefore(_firstDate)) {
        _start = null;
        _end = null;
      }
      if (type != LeaveType.sick) {
        _attachment = null;
        _attachmentBytes = null;
        _attachmentError = null;
      }
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_start ?? (_today.isBefore(_firstDate) ? _firstDate : _today))
        : (_end ?? _start ?? _today);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(_firstDate) ? _firstDate : initial,
      firstDate: isStart ? _firstDate : (_start ?? _firstDate),
      lastDate: _lastDate,
      helpText: isStart ? 'Tanggal mulai' : 'Tanggal selesai',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _error = null;
      if (isStart) {
        _start = picked;
        _startError = null;
        if (_end == null || _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
        _endError = null;
      }
    });
  }

  Future<void> _pickAttachment() async {
    if (_isPicking) return;
    setState(() {
      _isPicking = true;
      _attachmentError = null;
    });    try {
      final file = await AppScope.of(context).platform.pickFile(
        allowedExtensions: LeaveAttachment.allowedExtensions,
        // bytes dibutuhkan untuk upload ke S3.
        withData: true,
      );
      if (file == null || !mounted) return;
      final ext = file.extension ?? '';
      if (!LeaveAttachment.allowedExtensions.contains(ext)) {
        setState(() => _attachmentError = 'Format harus PDF, JPG, atau PNG.');
        return;
      }
      if (file.sizeBytes > LeaveAttachment.maxBytes) {
        setState(() => _attachmentError = 'Ukuran file maksimal 2 MB.');
        return;
      }
      setState(() {
        _attachment = LeaveAttachment(
          name: file.name,
          sizeBytes: file.sizeBytes,
        );
        _attachmentBytes = file.bytes;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _attachmentError = 'File tidak dapat dibuka. Coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  bool _validate() {
    String? startError;
    String? endError;
    String? attachmentError;
    String? error;
    if (_start == null) startError = 'Pilih tanggal mulai';
    if (_end == null) endError = 'Pilih tanggal selesai';
    if (_start != null && _end != null) {
      if (_workingDays == 0) {
        error = 'Rentang tanggal hanya berisi akhir pekan.';
      } else if (_type.usesQuota &&
          _balance != null &&
          _workingDays > _balance!.available) {
        error =
            'Melebihi sisa cuti tahunan yang bisa diajukan '
            '(${_balance!.available} hari).';
      }
    }
    if (_needsAttachment && _attachment == null) {
      attachmentError = 'Surat dokter wajib untuk sakit 2 hari atau lebih.';
    }
    setState(() {
      _startError = startError;
      _endError = endError;
      _attachmentError = attachmentError;
      _error = error;
    });
    return startError == null &&
        endError == null &&
        attachmentError == null &&
        error == null;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final ok = _validate();
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!ok || !formOk) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    final scope = AppScope.of(context);
    final user = SessionScope.userOf(context);
    try {
      var attachment = _type == LeaveType.sick ? _attachment : null;
      // Mode API: unggah surat dokter ke S3 dulu, kirim key-nya.
      if (attachment != null &&
          ApiConfig.baseUrl.isNotEmpty &&
          _attachmentBytes != null) {
        final uploader = ApiUploadRepository(
          baseUrl: ApiConfig.baseUrl,
          sessionStorage: scope.sessionStorage,
        );
        final key = await uploader.upload(
          purpose: 'leave',
          filename: attachment.name,
          contentType: _contentTypeOf(attachment.name),
          bytes: _attachmentBytes!,
        );
        attachment = LeaveAttachment(
          name: attachment.name,
          sizeBytes: attachment.sizeBytes,
          key: key,
        );
      }
      await scope.leave.submit(
        user,
        type: _type,
        start: _start!,
        end: _end!,
        reason: _reasonController.text,
        attachment: attachment,
      );
      if (!mounted) return;
      await showSuccessSheet(
        context,
        title: 'Pengajuan terkirim',
        message:
            '${_type.label} ${DateFormatId.dateRange(_start!, _end!)} '
            'terkirim. Menunggu persetujuan.',
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

  String _hintFor(LeaveType type) {
    if (type == LeaveType.annual && _annualExhausted) return 'Kuota habis';
    return switch (type) {
      LeaveType.annual =>
        _balance == null ? 'Memotong kuota' : 'Sisa ${_balance!.available} hari',
      LeaveType.permission => 'Tanpa kuota',
      LeaveType.sick => 'Surat dokter ≥ 2 hari',
      LeaveType.maternity => 'Otomatis 3 bulan sejak hari ini',
    };
  }

  /// Cuti tahunan habis: opsi dikunci agar tidak bisa dipilih.
  bool get _annualExhausted =>
      _balance != null && _balance!.available <= 0;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PageScaffold(
      title: 'Pengajuan baru',
      maxWidth: 600,
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteractionIfError,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Jenis pengajuan'),
            _TypeSelector(
              selected: _type,
              hintFor: _hintFor,
              enabled: !_isSubmitting,
              onSelect: _selectType,
              disabled: _annualExhausted ? const {LeaveType.annual} : const {},
            ),
            const SizedBox(height: AppSpacing.xl),
            if (_type == LeaveType.maternity) ...[
              Panel(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: context.inkSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Otomatis $_workingDays hari kerja, '
                        '${DateFormatId.dateRange(_start!, _end!)}. '
                        'Berlaku sejak hari ini setelah disetujui. '
                        'Tidak memotong kuota cuti tahunan.',
                        style: textTheme.bodySmall?.copyWith(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final datesEnabled =
                    !_isSubmitting && _type != LeaveType.maternity;
                final startField = LabeledField(
                  label: 'Tanggal mulai',
                  child: PickerField(
                    valueText: _start == null
                        ? null
                        : DateFormatId.shortDate(_start!),
                    hint: 'Pilih tanggal',
                    icon: Icons.event_outlined,
                    errorText: _startError,
                    enabled: datesEnabled,
                    onTap: () => _pickDate(isStart: true),
                  ),
                );
                final endField = LabeledField(
                  label: 'Tanggal selesai',
                  child: PickerField(
                    valueText: _end == null
                        ? null
                        : DateFormatId.shortDate(_end!),
                    hint: 'Pilih tanggal',
                    icon: Icons.event_outlined,
                    errorText: _endError,
                    enabled: datesEnabled,
                    onTap: () => _pickDate(isStart: false),
                  ),
                );
                // Layar sempit: bertumpuk agar tanggal tidak terpotong.
                if (constraints.maxWidth < 340) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      startField,
                      const SizedBox(height: AppSpacing.md),
                      endField,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: startField),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: endField),
                  ],
                );
              },
            ),
            if (_start != null && _end != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                liveRegion: true,
                child: Text(
                  _workingDays == 0
                      ? 'Rentang ini hanya berisi akhir pekan.'
                      : '$_workingDays hari kerja  ·  '
                            '${DateFormatId.dayShort(_start!)} – '
                            '${DateFormatId.dayShort(_end!)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: _workingDays == 0
                        ? context.danger
                        : context.inkSecondary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg + 4),
            LabeledField(
              label: 'Alasan',
              child: TextFormField(
                controller: _reasonController,
                enabled: !_isSubmitting,
                minLines: 3,
                maxLines: 6,
                maxLength: 300,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return 'Alasan wajib diisi';
                  if (value.length < 5) return 'Alasan minimal 5 karakter';
                  return null;
                },
                decoration: InputDecoration(
                  hintText: switch (_type) {
                    LeaveType.annual => 'mis. Acara keluarga di luar kota.',
                    LeaveType.permission =>
                      'mis. Mengurus dokumen kependudukan.',
                    LeaveType.sick =>
                      'mis. Demam, disarankan istirahat oleh dokter.',
                    LeaveType.maternity =>
                      'mis. Perkiraan tanggal lahir 10 Januari.',
                  },
                ),
              ),
            ),
            if (_type == LeaveType.sick) ...[
              const SizedBox(height: AppSpacing.sm),
              _AttachmentField(
                attachment: _attachment,
                required: _needsAttachment,
                errorText: _attachmentError,
                isPicking: _isPicking,
                enabled: !_isSubmitting,
                onPick: _pickAttachment,
                onRemove: () => setState(() {
                  _attachment = null;
                  _attachmentBytes = null;
                }),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FormErrorBanner(message: _error!),
            ],
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Kirim pengajuan',
              loadingLabel: 'Mengirim…',
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Pengajuan diteruskan ke atasan Anda untuk disetujui. '
              'Akhir pekan tidak dihitung sebagai hari cuti.',
              style: textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  const _TypeSelector({
    required this.selected,
    required this.hintFor,
    required this.enabled,
    required this.onSelect,
    this.disabled = const {},
  });

  final LeaveType selected;
  final String Function(LeaveType) hintFor;
  final bool enabled;
  final ValueChanged<LeaveType> onSelect;

  /// Jenis yang dikunci (mis. cuti tahunan saat kuota habis).
  final Set<LeaveType> disabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 340;
        // Tiga kolom sempit: tanpa ikon radio (pilihan tetap jelas dari
        // garis tepi tebal, latar, dan warna teks).
        final compact = constraints.maxWidth < 520;
        final options = [
          for (final type in LeaveType.values)
            _TypeOption(
              label: type.label,
              hint: hintFor(type),
              selected: type == selected,
              showRadio: stacked || !compact,
              disabled: disabled.contains(type),
              onTap: enabled && !disabled.contains(type)
                  ? () => onSelect(type)
                  : null,
            ),
        ];
        if (stacked) {
          return Column(
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                options[i],
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: options[i]),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TypeOption extends StatelessWidget {
  const _TypeOption({
    required this.label,
    required this.hint,
    required this.selected,
    required this.onTap,
    this.showRadio = true,
    this.disabled = false,
  });

  final String label;
  final String hint;
  final bool selected;
  final VoidCallback? onTap;
  final bool showRadio;

  /// Dikunci (mis. kuota habis): redup dan tidak merespons sentuhan.
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      enabled: !disabled,
      label: disabled ? '$label, tidak tersedia. $hint' : '$label, $hint',
      excludeSemantics: true,
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: Material(
        color: selected ? context.accentSubtle : context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
          side: BorderSide(
            color: selected ? context.accentText : context.borderStrong,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.panel),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showRadio) ...[
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: selected
                        ? context.accentText
                        : context.borderStrong,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? context.accentText
                              : context.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: textTheme.bodySmall?.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class _AttachmentField extends StatelessWidget {
  const _AttachmentField({
    required this.attachment,
    required this.required,
    required this.errorText,
    required this.isPicking,
    required this.enabled,
    required this.onPick,
    required this.onRemove,
  });

  final LeaveAttachment? attachment;
  final bool required;
  final String? errorText;
  final bool isPicking;
  final bool enabled;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final a = attachment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 32,
          child: Row(
            children: [
              Text(
                required ? 'Surat dokter' : 'Surat dokter (opsional)',
                style: textTheme.labelMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        if (a == null)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: enabled && !isPicking ? onPick : null,
              icon: isPicking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file, size: 18),
              label: const Text('Pilih file'),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            decoration: BoxDecoration(
              color: context.surfaceMuted,
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: context.border),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.description_outlined,
                  size: 18,
                  color: context.inkSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    a.name,
                    style: textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(a.sizeLabel, style: textTheme.bodySmall),
                IconButton(
                  tooltip: 'Hapus lampiran',
                  onPressed: enabled ? onRemove : null,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          errorText ?? 'PDF, JPG, atau PNG, maksimal 2 MB.',
          style: textTheme.bodySmall?.copyWith(
            fontSize: 12.5,
            color: errorText == null ? context.inkSecondary : context.danger,
          ),
        ),
      ],
    );
  }
}
