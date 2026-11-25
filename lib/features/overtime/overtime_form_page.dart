import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../../core/widgets/animated_check.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/picker_field.dart';
import '../../data/app_exception.dart';
import '../../data/overtime_repository.dart';

/// Mengajukan lembur yang sudah dikerjakan (maksimal 30 hari ke belakang,
/// minimal 1 jam). Pop `true` bila terkirim.
class OvertimeFormPage extends StatefulWidget {
  const OvertimeFormPage({super.key});

  @override
  State<OvertimeFormPage> createState() => _OvertimeFormPageState();
}

class _OvertimeFormPageState extends State<OvertimeFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();

  DateTime? _date;
  TimeOfDay? _start;
  TimeOfDay? _end;
  OvertimeSlot _slot = OvertimeSlot.morning;
  String? _dateError;
  String? _timeError;
  String? _error;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  DateTime? get _startAt {
    final d = _date;
    final t = _start;
    if (d == null || t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  DateTime? get _endAt {
    final d = _date;
    final t = _end;
    if (d == null || t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  String? get _durationPreview {
    final s = _startAt;
    final e = _endAt;
    if (s == null || e == null || !e.isAfter(s)) return null;
    return DateFormatId.duration(e.difference(s));
  }

  Future<void> _pickDate() async {
    final today = WorkCalendar.dateOnly(DateTime.now());
    final first = today.subtract(
      const Duration(days: OvertimeRules.maxDaysBack),
    );
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? today,
      firstDate: first,
      lastDate: today,
      helpText: 'Tanggal lembur',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = picked;
      _dateError = null;
      _timeError = _rangeError();
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          (isStart ? _start : _end) ?? const TimeOfDay(hour: 18, minute: 0),
      helpText: isStart ? 'Jam mulai lembur' : 'Jam selesai lembur',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
      _timeError = _rangeError();
    });
  }

  bool _isSundayFor(String division) =>
      isProduksiMutiariDivision(division) &&
      _date?.weekday == DateTime.sunday;

  String? _rangeError() {
    if (_isSundayFor(SessionScope.userOf(context).division)) return null;
    final s = _startAt;
    final e = _endAt;
    if (s == null || e == null) return null;
    if (!e.isAfter(s)) return 'Jam selesai harus setelah jam mulai.';
    if (e.difference(s).inMinutes < OvertimeRules.minMinutes) {
      return 'Durasi lembur minimal ${OvertimeRules.minMinutes} menit (1 jam).';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final user = SessionScope.userOf(context);
    final isMutiari = isProduksiMutiariDivision(user.division);
    final sunday = _isSundayFor(user.division);
    setState(() {
      _error = null;
      _dateError = _date == null ? 'Pilih tanggal lembur' : null;
      _timeError = sunday
          ? null
          : _startAt == null || _endAt == null
              ? 'Pilih jam mulai dan jam selesai'
              : _rangeError();
    });
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk ||
        _date == null ||
        (!sunday && (_startAt == null || _endAt == null)) ||
        _timeError != null) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    try {
      final midnight = DateTime(_date!.year, _date!.month, _date!.day);
      await AppScope.of(context).overtime.submit(
        user,
        date: _date!,
        start: sunday ? midnight : _startAt!,
        end: sunday ? midnight : _endAt!,
        reason: _reasonController.text,
        slot: sunday
            ? OvertimeSlot.sunday
            : isMutiari
                ? _slot
                : OvertimeSlot.single,
      );
      if (!mounted) return;
      await showSuccessSheet(
        context,
        title: 'Pengajuan terkirim',
        message:
            'Lembur ${DateFormatId.shortDate(_date!)} terkirim. '
            'Menunggu persetujuan.',
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
    final duration = _durationPreview;
    final division = SessionScope.userOf(context).division;
    final isMutiari = isProduksiMutiariDivision(division);
    final sunday = _isSundayFor(division);
    final showSlot = isMutiari && !sunday;

    return PageScaffold(
      title: 'Ajukan lembur',
      maxWidth: 600,
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
            LabeledField(
              label: 'Tanggal lembur',
              child: PickerField(
                valueText: _date == null
                    ? null
                    : DateFormatId.longDate(_date!),
                hint: 'Pilih tanggal (maks. 30 hari lalu)',
                icon: Icons.event_outlined,
                errorText: _dateError,
                enabled: !_isSubmitting,
                onTap: _pickDate,
              ),
            ),
            if (showSlot) ...[
              const SizedBox(height: AppSpacing.sm),
              LabeledField(
                label: 'Jenis lembur',
                child: SegmentedButton<OvertimeSlot>(
                  segments: [
                    ButtonSegment(
                      value: OvertimeSlot.morning,
                      label: Text('Pagi'),
                      icon: Icon(Icons.wb_sunny_outlined),
                      enabled: !_isSubmitting,
                    ),
                    ButtonSegment(
                      value: OvertimeSlot.evening,
                      label: Text('Malam'),
                      icon: Icon(Icons.nights_stay_outlined),
                      enabled: !_isSubmitting,
                    ),
                  ],
                  selected: {_slot},
                  onSelectionChanged: (selected) {
                    if (selected.isEmpty) return;
                    setState(() => _slot = selected.first);
                  },
                ),
              ),
            ],
            if (sunday) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                'Lembur Minggu tidak perlu jam mulai dan selesai. '
                'Cukup tanggal dan keterangan.',
                style: textTheme.bodySmall?.copyWith(
                  color: context.inkSecondary,
                ),
              ),
            ],
            if (!sunday) ...[
              const SizedBox(height: AppSpacing.sm),
              LayoutBuilder(
                builder: (context, constraints) {
                final startField = LabeledField(
                  label: 'Jam mulai',
                  child: PickerField(
                    valueText: _start?.format(context),
                    hint: 'mis. 18.00',
                    icon: Icons.schedule_outlined,
                    enabled: !_isSubmitting,
                    onTap: () => _pickTime(isStart: true),
                  ),
                );
                final endField = LabeledField(
                  label: 'Jam selesai',
                  child: PickerField(
                    valueText: _end?.format(context),
                    hint: 'mis. 21.30',
                    icon: Icons.schedule_outlined,
                    enabled: !_isSubmitting,
                    onTap: () => _pickTime(isStart: false),
                  ),
                );
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
            if (_timeError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _timeError!,
                style: Theme.of(
                  context,
                ).inputDecorationTheme.errorStyle,
              ),
            ],
            if (duration != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Semantics(
                liveRegion: true,
                child: Text(
                  'Durasi lembur: $duration',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.accentText,
                  ),
                ),
              ),
            ],
            ],
            const SizedBox(height: AppSpacing.sm),
            LabeledField(
              label: 'Keterangan',
              child: TextFormField(
                controller: _reasonController,
                enabled: !_isSubmitting,
                minLines: 3,
                maxLines: 5,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: OvertimeRules.validateReason,
                decoration: const InputDecoration(
                  hintText: 'mis. Menyelesaikan laporan akhir bulan.',
                  alignLabelWithHint: true,
                ),
              ),
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
