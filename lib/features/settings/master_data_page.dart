import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/auth_repository.dart';
import '../../data/master_data.dart';

/// Master data organisasi (Super Admin): divisi & jabatan.
/// Divisi/jabatan yang masih dipakai karyawan tidak bisa dihapus atau
/// dinonaktifkan; server menolak dan pesannya ditampilkan di sini.
class MasterDataPage extends StatefulWidget {
  const MasterDataPage({super.key});

  @override
  State<MasterDataPage> createState() => _MasterDataPageState();
}

class _MasterDataPageState extends State<MasterDataPage> {
  late MasterDataRepository _repo;
  bool _initialized = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<MasterDivision>? _divisions;
  List<MasterPosition>? _positions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).master;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final actor = SessionScope.userOf(context);
      final divisions = await _repo.fetchDivisions(actor);
      final positions = await _repo.fetchPositions(actor);
      if (!mounted) return;
      setState(() {
        _divisions = divisions;
        _positions = positions;
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Master data gagal dimuat. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      if (mounted) showAppSnackBar(context, success);
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Tidak dapat terhubung ke server. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askName({
    required String title,
    required String label,
    String? initial,
    String? helper,
  }) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (context) => ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final valid = value.text.trim().length >= 2;
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: label,
                helperText: helper,
              ),
              onSubmitted: valid
                  ? (_) => Navigator.of(context).pop(controller.text.trim())
                  : null,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.of(context).pop(controller.text.trim())
                    : null,
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool> _confirmDelete(String name, String consequence) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus "$name"?'),
        content: Text(consequence),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
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
    return ok == true;
  }

  Future<void> _addDivision() async {
    final label = await _askName(
      title: 'Tambah divisi',
      label: 'Nama divisi',
      helper: 'Kode dibuat otomatis dan tidak bisa diubah.',
    );
    if (label == null || !mounted) return;
    await _run(
      () => _repo.createDivision(SessionScope.userOf(context), label: label),
      'Divisi "$label" ditambahkan.',
    );
  }

  Future<void> _renameDivision(MasterDivision d) async {
    final label = await _askName(
      title: 'Ubah nama divisi',
      label: 'Nama divisi',
      initial: d.label,
      helper: 'Kode tetap ${d.code} agar data karyawan tidak berubah.',
    );
    if (label == null || label == d.label || !mounted) return;
    await _run(
      () => _repo.updateDivision(
        SessionScope.userOf(context),
        code: d.code,
        label: label,
      ),
      'Nama divisi diperbarui.',
    );
  }

  Future<void> _toggleDivision(MasterDivision d) async {
    await _run(
      () => _repo.updateDivision(
        SessionScope.userOf(context),
        code: d.code,
        active: !d.active,
      ),
      d.active ? 'Divisi dinonaktifkan.' : 'Divisi diaktifkan kembali.',
    );
  }

  Future<void> _deleteDivision(MasterDivision d) async {
    final ok = await _confirmDelete(
      d.label,
      'Divisi hanya bisa dihapus bila tidak dipakai karyawan. '
      'Data karyawan tidak terhapus.',
    );
    if (!ok || !mounted) return;
    await _run(
      () => _repo.deleteDivision(SessionScope.userOf(context), code: d.code),
      'Divisi "${d.label}" dihapus.',
    );
  }

  Future<void> _addPosition() async {
    final name = await _askName(
      title: 'Tambah jabatan',
      label: 'Nama jabatan',
      helper: 'Muncul sebagai pilihan di formulir karyawan.',
    );
    if (name == null || !mounted) return;
    await _run(
      () => _repo.createPosition(SessionScope.userOf(context), name: name),
      'Jabatan "$name" ditambahkan.',
    );
  }

  Future<void> _renamePosition(MasterPosition p) async {
    final name = await _askName(
      title: 'Ubah nama jabatan',
      label: 'Nama jabatan',
      initial: p.name,
      helper: 'Karyawan dengan jabatan lama ikut menampilkan nama baru.',
    );
    if (name == null || name == p.name || !mounted) return;
    await _run(
      () => _repo.updatePosition(
        SessionScope.userOf(context),
        id: p.id,
        name: name,
      ),
      'Nama jabatan diperbarui.',
    );
  }

  Future<void> _togglePosition(MasterPosition p) async {
    await _run(
      () => _repo.updatePosition(
        SessionScope.userOf(context),
        id: p.id,
        active: !p.active,
      ),
      p.active ? 'Jabatan dinonaktifkan.' : 'Jabatan diaktifkan kembali.',
    );
  }

  Future<void> _deletePosition(MasterPosition p) async {
    final ok = await _confirmDelete(
      p.name,
      'Jabatan hanya bisa dihapus bila tidak dipakai karyawan. '
      'Data karyawan tidak terhapus.',
    );
    if (!ok || !mounted) return;
    await _run(
      () => _repo.deletePosition(SessionScope.userOf(context), id: p.id),
      'Jabatan "${p.name}" dihapus.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Master data',
      maxWidth: 760,
      busy: _busy,
      onRefresh: _load,
      child: AsyncBody(
        isLoading: _loading,
        error: _error,
        hasData: _divisions != null && _positions != null,
        onRetry: _load,
        loadingLabel: 'Memuat master data…',
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _section(
              title: 'Divisi',
              hint:
                  'Dipakai untuk data karyawan dan sasaran pengumuman. '
                  'Kode divisi tidak berubah saat nama diubah.',
              onAdd: _addDivision,
              children: [
                for (var i = 0; i < _divisions!.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _divisionRow(_divisions![i]),
                ],
                if (_divisions!.isEmpty)
                  const _EmptyRow('Belum ada divisi.'),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _section(
              title: 'Jabatan',
              hint:
                  'Pilihan jabatan pada formulir tambah/ubah karyawan.',
              onAdd: _addPosition,
              children: [
                for (var i = 0; i < _positions!.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _positionRow(_positions![i]),
                ],
                if (_positions!.isEmpty)
                  const _EmptyRow('Belum ada jabatan.'),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Data yang masih dipakai karyawan tidak bisa dihapus. '
              'Pindahkan karyawan ke divisi/jabatan lain, atau nonaktifkan '
              'agar tidak muncul di pilihan baru.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section({
    required String title,
    required String hint,
    required VoidCallback onAdd,
    required List<Widget> children,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title.toUpperCase(),
                style: textTheme.labelSmall?.copyWith(
                  color: context.inkSecondary,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _busy ? null : onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tambah'),
            ),
          ],
        ),
        Text(hint, style: textTheme.bodySmall),
        const SizedBox(height: AppSpacing.sm),
        Panel(padding: EdgeInsets.zero, child: Column(children: children)),
      ],
    );
  }

  Widget _rowMenu({
    required bool active,
    required VoidCallback onRename,
    required VoidCallback onToggle,
    required VoidCallback onDelete,
  }) {
    return PopupMenuButton<String>(
      tooltip: 'Aksi',
      enabled: !_busy,
      onSelected: (value) {
        switch (value) {
          case 'rename':
            onRename();
          case 'toggle':
            onToggle();
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'rename', child: Text('Ubah nama')),
        PopupMenuItem(
          value: 'toggle',
          child: Text(active ? 'Nonaktifkan' : 'Aktifkan'),
        ),
        const PopupMenuItem(value: 'delete', child: Text('Hapus')),
      ],
    );
  }

  Widget _divisionRow(MasterDivision d) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      title: Text(
        d.label,
        style: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: d.active ? context.ink : context.inkSecondary,
        ),
      ),
      subtitle: Text(
        '${d.code} · ${d.employees} karyawan',
        style: textTheme.bodySmall?.copyWith(fontSize: 12.5),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!d.active)
            const StatusChip(label: 'Nonaktif', tone: ChipTone.neutral),
          _rowMenu(
            active: d.active,
            onRename: () => _renameDivision(d),
            onToggle: () => _toggleDivision(d),
            onDelete: () => _deleteDivision(d),
          ),
        ],
      ),
    );
  }

  Widget _positionRow(MasterPosition p) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
      title: Text(
        p.name,
        style: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: p.active ? context.ink : context.inkSecondary,
        ),
      ),
      subtitle: Text(
        '${p.employees} karyawan',
        style: textTheme.bodySmall?.copyWith(fontSize: 12.5),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!p.active)
            const StatusChip(label: 'Nonaktif', tone: ChipTone.neutral),
          _rowMenu(
            active: p.active,
            onRename: () => _renamePosition(p),
            onToggle: () => _togglePosition(p),
            onDelete: () => _deletePosition(p),
          ),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
