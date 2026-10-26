import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/app_update.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';

enum _Phase { prompt, downloading, ready, launching }

/// Dialog pembaruan: tawarkan versi baru, unduh dengan progres, verifikasi
/// checksum, lalu buka pemasang Android.
class AppUpdateDialog extends StatefulWidget {
  const AppUpdateDialog({
    super.key,
    required this.update,
    required this.updater,
  });

  final AppUpdate update;
  final AppUpdater updater;

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog>
    with WidgetsBindingObserver {
  _Phase _phase = _Phase.prompt;
  bool _cancelRequested = false;
  int _received = 0;
  int _total = 0;
  File? _file;
  bool _canInstall = true;
  String? _error;

  AppRelease get _release => widget.update.release;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshInstallPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Kembali dari layar izin "Install unknown apps": segarkan status.
    if (state == AppLifecycleState.resumed && _phase == _Phase.ready) {
      unawaited(_refreshInstallPermission());
    }
  }

  Future<void> _refreshInstallPermission() async {
    final ok = await widget.updater.canInstall();
    if (mounted) setState(() => _canInstall = ok);
  }

  Future<void> _startDownload() async {
    setState(() {
      _phase = _Phase.downloading;
      _error = null;
      _cancelRequested = false;
      _received = 0;
      _total = _release.sizeBytes;
    });
    try {
      final file = await widget.updater.download(
        _release,
        onProgress: (received, total) {
          if (!mounted) return;
          // Setiap chunk memicu callback; batasi rebuild agar UI tetap mulus.
          final finished = total > 0 && received >= total;
          if (!finished && received - _received < 256 * 1024) return;
          setState(() {
            _received = received;
            _total = total > 0 ? total : received;
          });
        },
        isCancelled: () => _cancelRequested,
      );
      if (!mounted) return;
      setState(() {
        _file = file;
        _phase = _Phase.ready;
      });
      await _refreshInstallPermission();
    } on AppUpdateCancelled {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.prompt;
        _received = 0;
      });
    } on AppUpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.prompt;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.prompt;
        _error = 'Unduhan gagal. Periksa koneksi, lalu coba lagi.';
      });
    }
  }

  Future<void> _install() async {
    final file = _file;
    if (file == null) return;
    if (!await widget.updater.canInstall()) {
      await widget.updater.openInstallSettings();
      return;
    }
    try {
      await widget.updater.install(file);
      if (mounted) setState(() => _phase = _Phase.launching);
    } on AppUpdateException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _permissionFirst() async {
    await widget.updater.openInstallSettings();
    await _refreshInstallPermission();
  }

  Future<void> _dismissLater() async {
    await widget.updater.skip(_release.versionCode);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final update = widget.update;

    return PopScope(
      // Pembaruan wajib tidak bisa ditutup dengan tombol kembali, kecuali
      // pemasangan sudah dibuka atau unduhan gagal (agar aplikasi tidak
      // terkunci permanen saat jaringan bermasalah).
      canPop:
          !update.forced ||
          _phase == _Phase.launching ||
          (_phase == _Phase.prompt && _error != null),
      child: AlertDialog(
        title: Text(_title()),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _content(textTheme),
          ),
        ),
        actions: _actions(),
      ),
    );
  }

  String _title() => switch (_phase) {
    _Phase.prompt => 'Pembaruan tersedia',
    _Phase.downloading => 'Mengunduh pembaruan',
    _Phase.ready => 'Siap dipasang',
    _Phase.launching => 'Menyelesaikan pembaruan',
  };

  List<Widget> _content(TextTheme textTheme) {
    final children = <Widget>[];
    switch (_phase) {
      case _Phase.prompt:
        children.addAll(_promptContent(textTheme));
      case _Phase.downloading:
        children.add(_progressContent(textTheme));
      case _Phase.ready:
        children.addAll(_readyContent(textTheme));
      case _Phase.launching:
        children.addAll([
          Text(
            'Ikuti petunjuk di layar pemasangan. Aplikasi akan tertutup dan '
            'terbuka lagi dengan versi ${_release.versionName}.',
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Data dan sesi Anda tetap tersimpan.',
            style: textTheme.bodySmall,
          ),
        ]);
    }
    return children;
  }

  List<Widget> _promptContent(TextTheme textTheme) {
    return [
      Text(
        'Versi ${_release.versionName} sudah tersedia. '
        'Versi terpasang: build ${widget.update.currentVersionCode}.',
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Ukuran ${_formatBytes(_release.sizeBytes)}. Unduhan berjalan sekali, '
        'lalu pemasang Android terbuka otomatis.',
        style: textTheme.bodySmall,
      ),
      if (_release.notes.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: context.border),
          ),
          child: Text(_release.notes, style: textTheme.bodySmall),
        ),
      ],
      if (widget.update.forced) ...[
        const SizedBox(height: AppSpacing.md),
        Text(
          'Pembaruan ini wajib dipasang untuk melanjutkan.',
          style: textTheme.bodySmall?.copyWith(
            color: context.danger,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: AppSpacing.md),
        _ErrorBanner(message: _error!),
      ],
    ];
  }

  Widget _progressContent(TextTheme textTheme) {
    final fraction = _total > 0 ? (_received / _total).clamp(0.0, 1.0) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: fraction),
        const SizedBox(height: AppSpacing.sm),
        Text(
          fraction == null
              ? _formatBytes(_received)
              : '${(fraction * 100).floor()}%  ·  '
                    '${_formatBytes(_received)} / ${_formatBytes(_total)}',
          style: textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  List<Widget> _readyContent(TextTheme textTheme) {
    return [
      Text(
        'Berkas sudah diunduh dan diperiksa. '
        'Ketuk pasang, lalu setujui di layar Android.',
      ),
      if (!_canInstall) ...[
        const SizedBox(height: AppSpacing.md),
        _ErrorBanner(
          message:
              'Izinkan pemasangan aplikasi dari Prasasti Connect '
              'terlebih dahulu.',
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: AppSpacing.md),
        _ErrorBanner(message: _error!),
      ],
      const SizedBox(height: AppSpacing.md),
      Text(
        'Jangan tutup aplikasi selama proses pemasangan.',
        style: textTheme.bodySmall,
      ),
    ];
  }

  List<Widget> _actions() {
    final canClose =
        !widget.update.forced ||
        _phase == _Phase.launching ||
        (_phase == _Phase.prompt && _error != null);

    switch (_phase) {
      case _Phase.prompt:
        return [
          if (!widget.update.forced)
            TextButton(onPressed: _dismissLater, child: const Text('Nanti'))
          else if (canClose)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tutup'),
            ),
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.system_update_alt, size: 18),
            label: Text(_error == null ? 'Unduh & pasang' : 'Coba lagi'),
          ),
        ];
      case _Phase.downloading:
        return [
          TextButton(
            onPressed: () => setState(() => _cancelRequested = true),
            child: const Text('Batal'),
          ),
        ];
      case _Phase.ready:
        return [
          if (!widget.update.forced)
            TextButton(onPressed: _dismissLater, child: const Text('Nanti')),
          FilledButton.icon(
            onPressed: _canInstall ? _install : _permissionFirst,
            icon: Icon(
              _canInstall ? Icons.download_done : Icons.lock_open,
              size: 18,
            ),
            label: Text(_canInstall ? 'Pasang sekarang' : 'Izinkan pemasangan'),
          ),
        ];
      case _Phase.launching:
        return [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Tutup'),
          ),
        ];
    }
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.dangerSubtle,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: context.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: context.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: context.danger),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
