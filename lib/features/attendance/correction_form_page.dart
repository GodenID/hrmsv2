import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/animated_check.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/picker_field.dart';
import '../../data/app_exception.dart';
import '../../data/attendance_repository.dart';

/// Formulir koreksi absensi. Pop dengan `true` bila terkirim.
class CorrectionFormPage extends StatefulWidget {
  const CorrectionFormPage({super.key, required this.day});

  final AttendanceDay day;

  @override
  State<CorrectionFormPage> createState() => _CorrectionFormPageState();
}

class _CorrectionFormPageState extends State<CorrectionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  TimeOfDay? _clockIn;
  TimeOfDay? _clockOut;
  String? _clockInError;
  String? _clockOutError;
  String? _error;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    final d = widget.day;
    _clockIn = d.clockIn == null ? null : TimeOfDay.fromDateTime(d.clockIn!);
    _clockOut = d.clockOut == null ? null : TimeOfDay.fromDateTime(d.clockOut!);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pick({required bool isClockIn}) async {
    final current = isClockIn ? _clockIn : _clockOut;
    final picked = await showTimePicker(
      context: context,
      initialTime:
          current ??
          (isClockIn
              ? const TimeOfDay(hour: 8, minute: 0)
              : const TimeOfDay(hour: 17, minute: 0)),
      helpText: isClockIn ? 'Jam masuk' : 'Jam pulang',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isClockIn) {
        _clockIn = picked;
        _clockInError = null;
      } else {
        _clockOut = picked;
        _clockOutError = null;
      }
    });
  }

  bool _validateTimes() {
    String? inError;
    String? outError;
    if (_clockIn == null) inError = 'Jam masuk wajib diisi';
    if (_clockOut == null) {
      outError = 'Jam pulang wajib diisi';
    } else if (_clockIn != null &&
        _minutes(_clockOut!) <= _minutes(_clockIn!)) {
      outError = 'Harus setelah jam masuk';
    }
    setState(() {
      _clockInError = inError;
      _clockOutError = outError;
    });
    return inError == null && outError == null;
  }

  bool get _unchanged {
    final d = widget.day;
    if (d.clockIn == null || d.clockOut == null) return false;
    return _fmt(TimeOfDay.fromDateTime(d.clockIn!)) == _fmt(_clockIn!) &&
        _fmt(TimeOfDay.fromDateTime(d.clockOut!)) == _fmt(_clockOut!);
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _error = null);
    final timesOk = _validateTimes();
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!timesOk || !formOk) return;
    if (_unchanged) {
      setState(() => _error = 'Ubah minimal satu jam dari catatan saat ini.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    final date = widget.day.date;
    DateTime at(TimeOfDay t) =>
        DateTime(date.year, date.month, date.day, t.hour, t.minute);
    try {
      await AppScope.of(context).attendance.submitCorrection(
        SessionScope.userOf(context),
        date: date,
        clockIn: at(_clockIn!),
        clockOut: at(_clockOut!),
        reason: _reasonController.text,
      );
      if (!mounted) return;
      await showSuccessSheet(
        context,
        title: 'Koreksi dikirim',
        message:
            'Pengajuan koreksi ${DateFormatId.shortDate(date)} terkirim. '
            'Menunggu persetujuan Atasan.',
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
    final textTheme = Theme.of(context).textTheme;
    final d = widget.day;
    final recorded =
        '${d.clockIn == null ? '—' : DateFormatId.time(d.clockIn!)}  –  '
        '${d.clockOut == null ? '—' : DateFormatId.time(d.clockOut!)}';

    return PageScaffold(
      title: 'Ajukan koreksi',
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
                    Icons.event_note_outlined,
                    size: 20,
                    color: context.inkSecondary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormatId.longDate(d.date),
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tercatat: $recorded',
                          style: textTheme.bodySmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Jam masuk',
                    child: PickerField(
                      valueText: _clockIn == null ? null : _fmt(_clockIn!),
                      hint: 'Pilih jam',
                      icon: Icons.login,
                      errorText: _clockInError,
                      enabled: !_isSubmitting,
                      onTap: () => _pick(isClockIn: true),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: LabeledField(
                    label: 'Jam pulang',
                    child: PickerField(
                      valueText: _clockOut == null ? null : _fmt(_clockOut!),
                      hint: 'Pilih jam',
                      icon: Icons.logout,
                      errorText: _clockOutError,
                      enabled: !_isSubmitting,
                      onTap: () => _pick(isClockIn: false),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
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
                  if (value.length < 10) return 'Alasan minimal 10 karakter';
                  return null;
                },
                decoration: const InputDecoration(
                  hintText:
                      'mis. Lupa clock out karena rapat di luar kantor '
                      'sampai pukul 18.00.',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Koreksi diperiksa oleh Atasan. Jika disetujui, jam di atas '
              'menggantikan catatan absensi tanggal ini.',
              style: textTheme.bodySmall?.copyWith(height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Kirim pengajuan',
              loadingLabel: 'Mengirim…',
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
