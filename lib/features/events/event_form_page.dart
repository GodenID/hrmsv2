import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/currency_format.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/picker_field.dart';
import '../../data/app_exception.dart';
import '../../data/event_repository.dart';
import 'event_presentation.dart';

/// Buat / edit event (Manager & Super Admin). Pop `true` bila tersimpan.
class EventFormPage extends StatefulWidget {
  const EventFormPage({super.key, this.initial});

  final EventItem? initial;

  @override
  State<EventFormPage> createState() => _EventFormPageState();
}

class _EventFormPageState extends State<EventFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _companyController;
  late final TextEditingController _locationController;
  late final TextEditingController _poController;
  bool _initialized = false;

  DateTime? _startDate;
  DateTime? _endDate;
  String? _startError;
  String? _endError;
  EventCategory? _category;
  List<EventCategory>? _categories;
  EventThresholds? _thresholds;
  String? _error;
  bool _isSubmitting = false;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final e = widget.initial;
    _nameController = TextEditingController(text: e?.name);
    _companyController = TextEditingController(text: e?.company);
    _locationController = TextEditingController(text: e?.location);
    _poController = TextEditingController(
      text: e?.poValue == null ? '' : Rupiah.group(e!.poValue!),
    );
    _startDate = e?.startDate;
    // Event 1 hari: selesai sama dengan mulai.
    _endDate = e?.endDate;
    // Pratinjau ukuran diperbarui saat nilai PO diketik.
    _poController.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _loadThresholds();
    _loadCategories();
  }

  Future<void> _loadThresholds() async {
    try {
      final t = await AppScope.of(context).events.fetchThresholds();
      if (mounted) setState(() => _thresholds = t);
    } catch (_) {
      // Pratinjau ukuran opsional; server tetap menghitung ukurannya.
    }
  }

  Future<void> _loadCategories() async {
    try {
      final repo = AppScope.of(context).events;
      final cats = await repo.fetchCategories(SessionScope.userOf(context));
      if (!mounted) return;
      setState(() {
        _categories = cats;
        // Samakan pilihan dengan kategori awal (edit) berdasarkan id.
        final initialId = widget.initial?.category.id;
        if (_category == null && initialId != null) {
          for (final c in cats) {
            if (c.id == initialId) _category = c;
          }
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Daftar kategori gagal dimuat. Coba lagi.');
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _locationController.dispose();
    _poController.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickDay({
    required DateTime? current,
    required String helpText,
  }) async {
    final today = WorkCalendar.dateOnly(DateTime.now());
    final first = today.subtract(const Duration(days: 365));
    final last = today.add(const Duration(days: 730));
    var initial = current ?? today;
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    return showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: helpText,
    );
  }

  Future<void> _pickStart() async {
    final picked = await _pickDay(
      current: _startDate,
      helpText: 'Tanggal mulai event',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _startDate = picked;
      _startError = null;
      // Default 1 hari: selesai mengikuti mulai bila belum dipilih.
      _endDate ??= picked;
      _endError = _rangeError(_startDate, _endDate);
    });
  }

  Future<void> _pickEnd() async {
    final picked = await _pickDay(
      current: _endDate ?? _startDate,
      helpText: 'Tanggal selesai event',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _endDate = picked;
      _endError = _rangeError(_startDate, _endDate);
    });
  }

  static String? _rangeError(DateTime? start, DateTime? end) {
    if (end == null) return 'Pilih tanggal selesai';
    if (start != null && end.isBefore(start)) {
      return 'Tidak boleh sebelum tanggal mulai';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() {
      _error = null;
      _startError = _startDate == null ? 'Pilih tanggal mulai' : null;
      _endError = _rangeError(_startDate, _endDate);
    });
    final formOk = _formKey.currentState?.validate() ?? false;
    if (!formOk ||
        _startDate == null ||
        _endDate == null ||
        _endError != null ||
        _category == null) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    final repo = AppScope.of(context).events;
    final user = SessionScope.userOf(context);
    final po = Rupiah.parse(_poController.text)!;
    try {
      if (_isEdit) {
        await repo.updateEvent(
          user,
          id: widget.initial!.id,
          name: _nameController.text,
          company: _companyController.text,
          categoryId: _category!.id,
          startDate: _startDate!,
          endDate: _endDate!,
          location: _locationController.text,
          poValue: po,
        );
      } else {
        await repo.createEvent(
          user,
          name: _nameController.text,
          company: _companyController.text,
          categoryId: _category!.id,
          startDate: _startDate!,
          endDate: _endDate!,
          location: _locationController.text,
          poValue: po,
        );
      }
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
    final po = Rupiah.parse(_poController.text);
    final t = _thresholds;

    return PageScaffold(
      title: _isEdit ? 'Edit event' : 'Buat event',
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
              label: 'Nama event',
              child: TextFormField(
                controller: _nameController,
                enabled: !_isSubmitting,
                autofocus: !_isEdit,
                maxLength: 100,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return 'Nama event wajib diisi';
                  if (value.length < 3) return 'Minimal 3 karakter';
                  return null;
                },
                decoration: const InputDecoration(
                  hintText: 'mis. Peluncuran Produk Aurora',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            LabeledField(
              label: 'Nama perusahaan',
              child: TextFormField(
                controller: _companyController,
                enabled: !_isSubmitting,
                maxLength: 100,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return 'Nama perusahaan wajib diisi';
                  if (value.length < 3) return 'Minimal 3 karakter';
                  return null;
                },
                decoration: const InputDecoration(
                  hintText: 'mis. PT Maju Bersama',
                  prefixIcon: Icon(Icons.business_outlined, size: 20),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            LabeledField(
              label: 'Kategori event',
              child: DropdownButtonFormField<EventCategory>(
                initialValue: _category,
                items: [
                  for (final c in _categories ?? const <EventCategory>[])
                    DropdownMenuItem(value: c, child: Text(c.name)),
                ],
                onChanged: !_isSubmitting && _categories != null
                    ? (c) => setState(() => _category = c)
                    : null,
                validator: (c) => c == null ? 'Pilih kategori event' : null,
                decoration: InputDecoration(
                  hintText: _categories == null
                      ? 'Memuat kategori…'
                      : 'Pilih kategori',
                  prefixIcon: const Icon(
                    Icons.category_outlined,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            LayoutBuilder(
              builder: (context, constraints) {
                final startField = LabeledField(
                  label: 'Tanggal mulai',
                  child: PickerField(
                    valueText: _startDate == null
                        ? null
                        : DateFormatId.longDate(_startDate!),
                    hint: 'Pilih tanggal',
                    icon: Icons.event_outlined,
                    errorText: _startError,
                    enabled: !_isSubmitting,
                    onTap: _pickStart,
                  ),
                );
                final endField = LabeledField(
                  label: 'Tanggal selesai',
                  child: PickerField(
                    valueText: _endDate == null
                        ? null
                        : DateFormatId.longDate(_endDate!),
                    hint: 'Sama dengan mulai = 1 hari',
                    icon: Icons.event_available_outlined,
                    errorText: _endError,
                    enabled: !_isSubmitting,
                    onTap: _pickEnd,
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
            const SizedBox(height: AppSpacing.lg + 4),
            LabeledField(
              label: 'Lokasi acara',
              child: TextFormField(
                controller: _locationController,
                enabled: !_isSubmitting,
                maxLength: 120,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (value.isEmpty) return 'Lokasi acara wajib diisi';
                  if (value.length < 3) return 'Minimal 3 karakter';
                  return null;
                },
                decoration: const InputDecoration(
                  hintText: 'mis. Jakarta Convention Center, Hall A',
                  prefixIcon: Icon(Icons.place_outlined, size: 20),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            LabeledField(
              label: 'Nilai PO event',
              child: TextFormField(
                controller: _poController,
                enabled: !_isSubmitting,
                keyboardType: TextInputType.number,
                inputFormatters: [RupiahInputFormatter()],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                style: textTheme.bodyLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                validator: (v) {
                  final value = Rupiah.parse(v ?? '');
                  if (value == null) return 'Nilai PO wajib diisi';
                  if (value <= 0) return 'Nilai PO harus lebih dari 0';
                  return null;
                },
                decoration: const InputDecoration(
                  hintText: '0',
                  prefixText: 'Rp ',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (t != null)
              Semantics(
                liveRegion: true,
              child: po == null || po <= 0
                  ? Text(
                      'Ukuran ditentukan otomatis dari nilai PO.',
                      style: textTheme.bodySmall,
                    )
                  : Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Ukuran:', style: textTheme.bodySmall),
                          EventSizeChip(size: t.classify(po), long: true),
                          Text(
                            'PO ${t.rangeLabel(t.classify(po))}',
                            style: textTheme.bodySmall?.copyWith(
                              color: t.classify(po) == EventSize.overLimit
                                  ? context.warning
                                  : context.inkSecondary,
                            ),
                          ),
                        ],
                      ),
              ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: _isEdit ? 'Simpan perubahan' : 'Buat event',
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
