import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/date_format_id.dart';
import '../../../core/utils/work_calendar.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../data/announcement_repository.dart';
import '../../../data/api/api_auth_repository.dart' show ApiConfig;
import '../../../data/api/api_upload_repository.dart';
import '../../../data/auth_repository.dart';
import '../../../data/master_data.dart';

typedef AnnouncementSubmit = Future<void> Function(AnnouncementDraft draft);

/// Membuka formulir tambah/ubah pengumuman.
/// Layar sempit: layar penuh. Layar lebar: dialog 560px.
/// Mengembalikan true bila tersimpan.
Future<bool> showAnnouncementEditor(
  BuildContext context, {
  Announcement? initial,
  required AnnouncementSubmit onSubmit,
}) async {
  final isNarrow = MediaQuery.sizeOf(context).width < 600;
  final editor = _AnnouncementEditor(
    initial: initial,
    onSubmit: onSubmit,
    fullscreen: isNarrow,
  );

  final saved = await showDialog<bool>(
    context: context,
    // Hindari teks yang sedang diketik hilang karena klik di luar dialog.
    barrierDismissible: false,
    builder: (context) => isNarrow
        ? Dialog.fullscreen(child: editor)
        : Dialog(
            insetPadding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: editor,
            ),
          ),
  );
  return saved ?? false;
}

class _AnnouncementEditor extends StatefulWidget {
  const _AnnouncementEditor({
    required this.initial,
    required this.onSubmit,
    required this.fullscreen,
  });

  final Announcement? initial;
  final AnnouncementSubmit onSubmit;
  final bool fullscreen;

  @override
  State<_AnnouncementEditor> createState() => _AnnouncementEditorState();
}

class _AnnouncementEditorState extends State<_AnnouncementEditor> {
  static const int _titleMax = 120;
  static const int _bodyMax = 2000;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;

  bool _scheduled = false;
  DateTime? _publishDate;
  TimeOfDay? _publishTime;
  bool _hasExpiry = false;
  DateTime? _expiryDate;
  bool _pinned = false;
  final Set<Division> _targets = {};
  final List<AnnouncementAttachment> _attachments = [];

  /// Pilihan divisi sasaran dari master data (dimuat sekali per editor).
  Future<List<MasterDivision>>? _divisionsFuture;

  /// Bytes lampiran baru (kunci: nama file), untuk upload S3 mode API.
  final Map<String, Uint8List> _attachmentData = {};
  String? _attachmentError;

  bool _isSaving = false;
  String? _error;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final a = widget.initial;
    _titleController = TextEditingController(text: a?.title);
    _bodyController = TextEditingController(text: a?.body);
    _pinned = a?.pinned ?? false;
    _targets.addAll(a?.targetDivisions ?? const []);
    _attachments.addAll(a?.attachments ?? const []);
    final now = DateTime.now();
    if (a != null && a.publishedAt.isAfter(now)) {
      _scheduled = true;
      final p = a.publishedAt;
      _publishDate = DateTime(p.year, p.month, p.day);
      _publishTime = TimeOfDay.fromDateTime(p);
    }
    if (a?.expiresAt != null) {
      _hasExpiry = true;
      final e = a!.expiresAt!;
      _expiryDate = DateTime(e.year, e.month, e.day);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _divisionsFuture ??= AppScope.of(context).master.fetchDivisions(
          SessionScope.userOf(context),
        );
  }

  String? _validateTitle(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Judul wajib diisi';
    if (v.length < 5) return 'Judul minimal 5 karakter';
    return null;
  }

  String? _validateBody(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Isi pengumuman wajib diisi';
    if (v.length < 10) return 'Isi pengumuman minimal 10 karakter';
    return null;
  }

  Future<void> _pickPublishDate() async {
    final today = WorkCalendar.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _publishDate ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Tanggal terbit',
    );
    if (picked != null && mounted) setState(() => _publishDate = picked);
  }

  Future<void> _pickPublishTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _publishTime ?? const TimeOfDay(hour: 9, minute: 0),
      helpText: 'Jam terbit',
    );
    if (picked != null && mounted) setState(() => _publishTime = picked);
  }

  Future<void> _pickExpiryDate() async {
    final today = WorkCalendar.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? today.add(const Duration(days: 30)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 730)),
      helpText: 'Tanggal kedaluwarsa',
    );
    if (picked != null && mounted) setState(() => _expiryDate = picked);
  }

  Future<void> _addAttachment() async {
    if (_isSaving) return;
    if (_attachments.length >= AnnouncementRules.maxAttachments) {
      setState(
        () => _attachmentError =
            'Maksimal ${AnnouncementRules.maxAttachments} lampiran.',
      );
      return;
    }
    try {
      final picked = await AppScope.of(context).platform.pickFile(
        allowedExtensions: AnnouncementRules.allowedExtensions,
        withData: ApiConfig.baseUrl.isNotEmpty,
      );
      if (picked == null || !mounted) return;
      final error = AnnouncementRules.validateAttachment(
        picked.name,
        picked.sizeBytes,
      );
      if (error != null) {
        setState(() => _attachmentError = error);
        return;
      }
      setState(() {
        _attachmentError = null;
        _attachments.add(
          AnnouncementAttachment(
            name: picked.name,
            sizeBytes: picked.sizeBytes,
          ),
        );
        if (picked.bytes != null) _attachmentData[picked.name] = picked.bytes!;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _attachmentError = 'File tidak dapat dibuka. Coba lagi.',
        );
      }
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;

    DateTime? publishAt;
    if (_scheduled) {
      final date = _publishDate;
      final time = _publishTime;
      if (date == null || time == null) {
        setState(() => _error = 'Pilih tanggal dan jam terbit.');
        return;
      }
      publishAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (!publishAt.isAfter(DateTime.now())) {
        setState(() => _error = 'Jadwal terbit harus di masa depan.');
        return;
      }
    }
    DateTime? expiresAt;
    if (_hasExpiry) {
      final date = _expiryDate;
      if (date == null) {
        setState(() => _error = 'Pilih tanggal kedaluwarsa.');
        return;
      }
      expiresAt = DateTime(date.year, date.month, date.day, 23, 59);
    }
    final scheduleError = AnnouncementRules.validateSchedule(
      publishAt,
      expiresAt,
    );
    if (scheduleError != null) {
      setState(() => _error = scheduleError);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    final scope = AppScope.of(context);
    try {
      // Mode API: unggah lampiran baru ke S3 dulu.
      final attachments = <AnnouncementAttachment>[];
      if (ApiConfig.baseUrl.isNotEmpty) {
        final uploader = ApiUploadRepository(
          baseUrl: ApiConfig.baseUrl,
          sessionStorage: scope.sessionStorage,
        );
        for (final a in _attachments) {
          final bytes = _attachmentData[a.name];
          if (a.key != null || bytes == null) {
            attachments.add(a);
            continue;
          }
          final key = await uploader.upload(
            purpose: 'announcement',
            filename: a.name,
            contentType: _contentTypeOf(a.name),
            bytes: bytes,
          );
          attachments.add(
            AnnouncementAttachment(
              name: a.name,
              sizeBytes: a.sizeBytes,
              key: key,
            ),
          );
        }
      } else {
        attachments.addAll(_attachments);
      }
      await widget.onSubmit(
        AnnouncementDraft(
          title: _titleController.text,
          body: _bodyController.text,
          publishAt: publishAt,
          expiresAt: expiresAt,
          pinned: _pinned,
          targetDivisions: _targets.toList(),
          attachments: attachments,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu coba lagi.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = _isEdit ? 'Edit pengumuman' : 'Tambah pengumuman';

    final form = Form(
      key: _formKey,
      // Pesan galat hilang begitu field diperbaiki.
      autovalidateMode: AutovalidateMode.onUserInteractionIfError,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(fontSize: 18),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Tutup',
                onPressed: _isSaving
                    ? null
                    : () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Tanpa pengaturan di bawah, pengumuman langsung terlihat oleh '
            'semua karyawan di dashboard.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xl),
          if (_error != null) ...[
            FormErrorBanner(message: _error!),
            const SizedBox(height: AppSpacing.lg),
          ],
          LabeledField(
            label: 'Judul',
            child: TextFormField(
              controller: _titleController,
              enabled: !_isSaving,
              autofocus: !_isEdit,
              maxLength: _titleMax,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              validator: _validateTitle,
              decoration: const InputDecoration(
                hintText: 'mis. Jadwal libur bersama akhir tahun',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          LabeledField(
            label: 'Isi pengumuman',
            child: TextFormField(
              controller: _bodyController,
              enabled: !_isSaving,
              minLines: 6,
              maxLines: 12,
              maxLength: _bodyMax,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              validator: _validateBody,
              decoration: const InputDecoration(
                hintText: 'Tulis informasi yang perlu diketahui karyawan…',
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _SwitchRow(
            title: 'Jadwalkan terbit',
            subtitle: _scheduled ? null : 'Terbit segera setelah disimpan',
            value: _scheduled,
            enabled: !_isSaving,
            onChanged: (v) => setState(() => _scheduled = v),
          ),
          if (_scheduled) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _pickPublishDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      _publishDate == null
                          ? 'Tanggal'
                          : DateFormatId.shortDate(_publishDate!),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _pickPublishTime,
                    icon: const Icon(Icons.schedule_outlined, size: 18),
                    label: Text(
                      _publishTime == null
                          ? 'Jam'
                          : _publishTime!.format(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _SwitchRow(
            title: 'Atur tanggal kedaluwarsa',
            subtitle: _hasExpiry
                ? null
                : 'Tanpa batas (selalu tampil)',
            value: _hasExpiry,
            enabled: !_isSaving,
            onChanged: (v) => setState(() => _hasExpiry = v),
          ),
          if (_hasExpiry) ...[
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _pickExpiryDate,
                icon: const Icon(Icons.event_busy_outlined, size: 18),
                label: Text(
                  _expiryDate == null
                      ? 'Pilih tanggal'
                      : DateFormatId.shortDate(_expiryDate!),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _SwitchRow(
            title: 'Sematkan di paling atas',
            value: _pinned,
            enabled: !_isSaving,
            onChanged: (v) => setState(() => _pinned = v),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Untuk divisi', style: textTheme.labelSmall),
          const SizedBox(height: AppSpacing.sm),
          FutureBuilder<List<MasterDivision>>(
            future: _divisionsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Text('Memuat divisi…', style: textTheme.bodySmall);
              }
              if (snapshot.hasError) {
                return Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Daftar divisi gagal dimuat.',
                        style: textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: _isSaving
                          ? null
                          : () => setState(() {
                                _divisionsFuture = AppScope.of(context)
                                    .master
                                    .fetchDivisions(
                                      SessionScope.userOf(context),
                                    );
                              }),
                      child: const Text('Coba lagi'),
                    ),
                  ],
                );
              }
              final options = <Division>{
                for (final d in snapshot.data ?? const <MasterDivision>[])
                  d.division,
                ..._targets,
              }.toList()
                ..sort((a, b) => a.label.compareTo(b.label));
              return Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final d in options)
                    FilterChip(
                      label: Text(d.label),
                      selected: _targets.contains(d),
                      onSelected: _isSaving
                          ? null
                          : (selected) => setState(() {
                                if (selected) {
                                  _targets.add(d);
                                } else {
                                  _targets.remove(d);
                                }
                              }),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            _targets.isEmpty
                ? 'Kosong = semua karyawan.'
                : '${_targets.length} divisi dipilih.',
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Text('Lampiran', style: textTheme.labelSmall),
              const Spacer(),
              TextButton.icon(
                onPressed:
                    _isSaving ||
                        _attachments.length >=
                            AnnouncementRules.maxAttachments
                    ? null
                    : _addAttachment,
                icon: const Icon(Icons.attach_file, size: 18),
                label: Text(
                  'Tambah (${_attachments.length}/${AnnouncementRules.maxAttachments})',
                ),
              ),
            ],
          ),
          if (_attachmentError != null) ...[
            const SizedBox(height: 4),
            Text(
              _attachmentError!,
              style: Theme.of(
                context,
              ).inputDecorationTheme.errorStyle,
            ),
          ],
          for (final a in _attachments)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.insert_drive_file_outlined,
                    size: 18,
                    color: context.inkSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          a.name,
                          style: textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          a.sizeLabel,
                          style: textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hapus ${a.name}',
                    onPressed: _isSaving
                        ? null
                        : () => setState(() {
                              _attachments.remove(a);
                              _attachmentData.remove(a.name);
                            }),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isSaving
                    ? null
                    : () => Navigator.of(context).pop(false),
                style: TextButton.styleFrom(
                  foregroundColor: context.inkSecondary,
                  minimumSize: const Size(72, 44),
                ),
                child: const Text('Batal'),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                onPressed: _isSaving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size(140, 44)),
                child: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isEdit ? 'Simpan perubahan' : 'Terbitkan'),
              ),
            ],
          ),
        ],
      ),
    );

      return PopScope(
      canPop: !_isSaving,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            widget.fullscreen ? 12 : 20,
            widget.fullscreen ? 16 : 20,
            24,
          ),
          child: form,
        ),
      ),
    );
  }
}

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

/// Baris label + switch (jadwal, kedaluwarsa, sematkan).
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (subtitle != null)
                Text(subtitle!, style: textTheme.bodySmall),
            ],
          ),
        ),
        Switch(value: value, onChanged: enabled ? onChanged : null),
      ],
    );
  }
}
