import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/currency_format.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/loading_row.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/app_exception.dart';
import '../../data/event_repository.dart';
import 'event_presentation.dart';

/// Manager & Super Admin: ambang nilai PO (kecil/sedang/besar) + daftar
/// kategori event. Pop `true` bila ambang disimpan.
class EventSettingsPage extends StatefulWidget {
  const EventSettingsPage({super.key});

  @override
  State<EventSettingsPage> createState() => _EventSettingsPageState();
}

class _EventSettingsPageState extends State<EventSettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _small = TextEditingController();
  final _medium = TextEditingController();
  final _large = TextEditingController();
  bool _initialized = false;

  List<EventCategory>? _categories;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _busyCategory = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    for (final c in [_small, _medium, _large]) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  @override
  void dispose() {
    _small.dispose();
    _medium.dispose();
    _large.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repo = AppScope.of(context).events;
      final results = await Future.wait([
        repo.fetchThresholds(),
        repo.fetchCategories(SessionScope.userOf(context)),
      ]);
      if (!mounted) return;
      final t = results[0] as EventThresholds;
      _small.text = Rupiah.group(t.smallMax);
      _medium.text = Rupiah.group(t.mediumMax);
      _large.text = Rupiah.group(t.largeMax);
      setState(() => _categories = results[1] as List<EventCategory>);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Pengaturan gagal dimuat. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reloadCategories() async {
    try {
      final cats = await AppScope.of(context).events.fetchCategories(
        SessionScope.userOf(context),
      );
      if (mounted) setState(() => _categories = cats);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Daftar kategori gagal dimuat. Coba lagi.');
      }
    }
  }

  EventThresholds? get _draft {
    final s = Rupiah.parse(_small.text);
    final m = Rupiah.parse(_medium.text);
    final l = Rupiah.parse(_large.text);
    if (s == null || m == null || l == null) return null;
    return EventThresholds(smallMax: s, mediumMax: m, largeMax: l);
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final draft = _draft!;
    final invalid = draft.validate();
    if (invalid != null) {
      setState(() => _error = invalid);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    try {
      await AppScope.of(context).events
          .updateThresholds(SessionScope.userOf(context), draft);
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
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _editCategory({EventCategory? existing}) async {
    final controller = TextEditingController(text: existing?.name);
    String? dialogError;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialog) => AlertDialog(
          title: Text(existing == null ? 'Tambah kategori' : 'Ubah kategori'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: controller,
                autofocus: true,
                maxLength: 40,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  hintText: 'mis. Employee Gathering',
                ),
                onFieldSubmitted: (_) async {
                  final ok = await _submitCategory(
                    controller.text,
                    existing: existing,
                    setDialogError: (m) =>
                        setDialog(() => dialogError = m),
                  );
                  if (ok && context.mounted) Navigator.of(context).pop(true);
                },
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 8),
                Text(
                  dialogError!,
                  style: Theme.of(
                    context,
                  ).inputDecorationTheme.errorStyle,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: context.inkSecondary,
              ),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await _submitCategory(
                  controller.text,
                  existing: existing,
                  setDialogError: (m) => setDialog(() => dialogError = m),
                );
                if (ok && context.mounted) Navigator.of(context).pop(true);
              },
              child: Text(existing == null ? 'Tambah' : 'Simpan'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (saved == true && mounted) {
      await _reloadCategories();
      if (mounted) {
        showAppSnackBar(
          context,
          existing == null
              ? 'Kategori ditambahkan.'
              : 'Kategori diperbarui.',
        );
      }
    }
  }

  /// Menyimpan kategori dari dialog. Mengembalikan true bila berhasil.
  Future<bool> _submitCategory(
    String name, {
    required EventCategory? existing,
    required ValueChanged<String> setDialogError,
  }) async {
    try {
      await AppScope.of(context).events.saveCategory(
        SessionScope.userOf(context),
        id: existing?.id,
        name: name,
      );
      return true;
    } catch (e) {
      setDialogError(
        e is AppException
            ? e.message
            : 'Tidak dapat terhubung ke server. Coba lagi.',
      );
      return false;
    }
  }

  Future<void> _deleteCategory(EventCategory category) async {
    if (_busyCategory) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus kategori?'),
        content: Text(
          '"${category.name}" akan dihapus dari daftar pilihan. '
          'Kategori yang masih dipakai event tidak bisa dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: context.inkSecondary,
            ),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: context.danger,
              foregroundColor: context.isDark ? context.surface : Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyCategory = true);
    try {
      await AppScope.of(context).events.deleteCategory(
        SessionScope.userOf(context),
        id: category.id,
      );
      if (!mounted) return;
      await _reloadCategories();
      if (mounted) showAppSnackBar(context, 'Kategori dihapus.');
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Gagal menghapus. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _busyCategory = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool last = false,
  }) {
    return LabeledField(
      label: label,
      child: TextFormField(
        controller: controller,
        enabled: !_isSaving,
        keyboardType: TextInputType.number,
        inputFormatters: [RupiahInputFormatter()],
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        onFieldSubmitted: last ? (_) => _save() : null,
        style: Theme.of(context).textTheme.bodyLarge
            ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        validator: (v) {
          final value = Rupiah.parse(v ?? '');
          if (value == null || value <= 0) return 'Isi nilai lebih dari 0';
          return null;
        },
        decoration: const InputDecoration(prefixText: 'Rp ', hintText: '0'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final draft = _draft;
    final draftValid = draft != null && draft.validate() == null;
    final cats = _categories;

    return PageScaffold(
      title: 'Pengaturan event',
      maxWidth: 560,
      child: _isLoading
          ? const LoadingRow(label: 'Memuat pengaturan…')
          : Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteractionIfError,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Ambang nilai PO'),
                  Text(
                    'Ukuran event ditentukan dari nilai PO. Setiap angka di '
                    'bawah adalah nilai PO maksimal untuk ukurannya. '
                    'Perubahan langsung berlaku untuk semua event.',
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
                  _field('Event kecil — PO maksimal', _small),
                  const SizedBox(height: AppSpacing.lg),
                  _field('Event sedang — PO maksimal', _medium),
                  const SizedBox(height: AppSpacing.lg),
                  _field('Event besar — PO maksimal', _large, last: true),
                  const SizedBox(height: AppSpacing.xl),
                  if (draftValid)
                    Panel(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SectionLabel('Pratinjau'),
                          for (final size in EventSize.values)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 120,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: EventSizeChip(size: size),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      'PO ${draft.rangeLabel(size)}',
                                      style: textTheme.bodyMedium?.copyWith(
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xl),
                  PrimaryButton(
                    label: 'Simpan ambang',
                    loadingLabel: 'Menyimpan…',
                    isLoading: _isSaving,
                    onPressed: _save,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  const SectionLabel('Kategori event'),
                  Text(
                    'Dipilih saat membuat event, mis. Employee Gathering atau '
                    'Family Gathering. Kategori yang masih dipakai event '
                    'tidak bisa dihapus.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.inkSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: cats == null || cats.isEmpty
                        ? const EmptyState(
                            icon: Icons.category_outlined,
                            title: 'Belum ada kategori',
                            message: 'Tambahkan kategori pertama di bawah.',
                          )
                        : Column(
                            children: [
                              for (var i = 0; i < cats.length; i++) ...[
                                if (i > 0) const Divider(),
                                _CategoryRow(
                                  category: cats[i],
                                  onEdit: () =>
                                      _editCategory(existing: cats[i]),
                                  onDelete: () => _deleteCategory(cats[i]),
                                ),
                              ],
                            ],
                          ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  OutlinedButton.icon(
                    onPressed: _busyCategory
                        ? null
                        : () => _editCategory(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Tambah kategori'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  final EventCategory category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              category.name,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Ubah ${category.name}',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined, size: 20),
          ),
          IconButton(
            tooltip: 'Hapus ${category.name}',
            onPressed: onDelete,
            color: context.danger,
            icon: const Icon(Icons.delete_outline, size: 20),
          ),
        ],
      ),
    );
  }
}
