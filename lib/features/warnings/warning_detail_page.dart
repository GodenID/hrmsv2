import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/auth_repository.dart';
import '../../data/warning_repository.dart';

/// Isi SP: kronologi, pasal, status, tanda tangan / penolakan,
/// dan sanggahan. Pop `true` bila ada perubahan (untuk refresh daftar).
class WarningDetailPage extends StatefulWidget {
  const WarningDetailPage({super.key, required this.initial});

  final WarningLetterDetail initial;

  @override
  State<WarningDetailPage> createState() => _WarningDetailPageState();
}

class _WarningDetailPageState extends State<WarningDetailPage> {
  late WarningRepository _repo;
  bool _initialized = false;

  late WarningLetterDetail _detail;
  bool _busy = false;
  bool _changed = false;

  final _witness1Controller = TextEditingController();
  final _witness2Controller = TextEditingController();
  final _appealController = TextEditingController();
  final _responseController = TextEditingController();
  bool _showAppealForm = false;

  @override
  void initState() {
    super.initState();
    _detail = widget.initial;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).warnings;
  }

  @override
  void dispose() {
    _witness1Controller.dispose();
    _witness2Controller.dispose();
    _appealController.dispose();
    _responseController.dispose();
    super.dispose();
  }

  bool get _isMine =>
      _detail.employee.username ==
      SessionScope.userOf(context).username;

  bool get _isSuperAdmin =>
      SessionScope.userOf(context).role == UserRole.superadmin;

  void _markChanged(WarningLetterDetail updated) {
    setState(() {
      _detail = updated;
      _changed = true;
      _showAppealForm = false;
    });
  }

  Future<void> _sign() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tandatangani SP?'),
        content: const Text(
          'Tanda tangan berarti Anda telah membaca dan menerima surat ini. '
          'Isinya tetap bisa disanggah setelahnya.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Tandatangani'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await _repo.acknowledge(
        SessionScope.userOf(context),
        id: _detail.letter.id,
        refused: false,
      );
      if (mounted) {
        _markChanged(updated);
        showAppSnackBar(context, 'SP ditandatangani.');
      }
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Gagal menyimpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refuse() async {
    _witness1Controller.clear();
    _witness2Controller.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tolak tanda tangan?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Penolakan dicatat sebagai berita acara dan wajib disertai '
                '2 saksi yang berbeda.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _witness1Controller,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama saksi 1',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _witness2Controller,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama saksi 2',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.danger,
              foregroundColor: context.isDark ? context.surface : Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Tolak & catat'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final updated = await _repo.acknowledge(
        SessionScope.userOf(context),
        id: _detail.letter.id,
        refused: true,
        witness1: _witness1Controller.text,
        witness2: _witness2Controller.text,
      );
      if (mounted) {
        _markChanged(updated);
        showAppSnackBar(context, 'Penolakan dicatat dalam berita acara.');
      }
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Gagal menyimpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respond(bool accept) async {
    final note = _responseController.text;
    if (note.trim().length < WarningRules.minResponseNote) {
      showAppSnackBar(
        context,
        'Tulis catatan respons minimal '
        '${WarningRules.minResponseNote} karakter.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final updated = await _repo.respondAppeal(
        SessionScope.userOf(context),
        id: _detail.letter.id,
        accept: accept,
        note: note,
      );
      if (mounted) {
        _markChanged(updated);
        showAppSnackBar(
          context,
          accept ? 'Sanggahan diterima, SP dicabut.' : 'Sanggahan ditolak.',
        );
      }
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Gagal menyimpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendAppeal() async {
    setState(() => _busy = true);
    try {
      final updated = await _repo.appeal(
        SessionScope.userOf(context),
        id: _detail.letter.id,
        text: _appealController.text,
      );
      if (mounted) {
        _markChanged(updated);
        showAppSnackBar(context, 'Sanggahan terkirim.');
      }
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Gagal mengirim. Coba lagi.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final letter = _detail.letter;
    final now = DateTime.now();
    final isActive = letter.isActive(now);

    // Bila ada perubahan, kembalikan `true` agar daftar refresh.
    return PopScope(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: PageScaffold(
        title: letter.levelLabel,
        maxWidth: 720,
        busy: _busy,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _LevelBadge(level: letter.level),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _detail.employee.fullName,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _Fact(
                    label: 'Pelanggaran',
                    value:
                        '${letter.violationName} (${letter.severity.label})',
                  ),
                  _Fact(
                    label: 'Kejadian',
                    value: DateFormatId.shortDate(letter.incidentDate),
                  ),
                  _Fact(label: 'Pasal', value: letter.articleRef),
                  _Fact(
                    label: 'Status',
                    value: letter.voided
                        ? 'Dicabut (sanggahan diterima)'
                        : isActive
                        ? 'Aktif s/d ${DateFormatId.shortDate(letter.expiresAt)}'
                        : 'Kedaluwarsa ${DateFormatId.shortDate(letter.expiresAt)}',
                    valueColor: letter.voided
                        ? context.inkSecondary
                        : isActive
                        ? context.success
                        : context.inkSecondary,
                  ),
                  _Fact(
                    label: 'Diterbitkan',
                    value:
                        '${letter.issuedByName}, ${DateFormatId.shortDateTime(letter.issuedAt)}',
                  ),
                  const Divider(height: 24),
                  Text(
                    'Uraian kejadian',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(letter.description),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tanda tangan',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (!letter.signed)
                    const Text('Belum ditandatangani.')
                  else if (letter.refused)
                    Text(
                      'Ditolak pada ${DateFormatId.shortDateTime(letter.acknowledgedAt!)} '
                      '(berita acara). Saksi: ${letter.witness1}, ${letter.witness2}.',
                    )
                  else
                    Text(
                      'Ditandatangani ${letter.acknowledgedBy} pada '
                      '${DateFormatId.shortDateTime(letter.acknowledgedAt!)}.',
                    ),
                  if (_isMine &&
                      !letter.signed &&
                      !letter.voided) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: _busy ? null : _sign,
                            child: const Text('Tandatangani'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _busy ? null : _refuse,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.danger,
                            ),
                            child: const Text('Tolak'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sanggahan',
                    style: textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (letter.appeal != null) ...[
                    Text(
                      '“${letter.appeal}”\nDiajukan ${DateFormatId.shortDateTime(letter.appealAt!)}.',
                    ),
                    if (letter.appealAccepted != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        letter.appealAccepted!
                            ? 'Diterima — SP dicabut. Catatan: “${letter.appealResponseNote}”'
                            : 'Ditolak — SP tetap berlaku. Catatan: “${letter.appealResponseNote}”',
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: letter.appealAccepted!
                              ? context.success
                              : context.danger,
                        ),
                      ),
                    ] else if (_isSuperAdmin) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _responseController,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Catatan respons (wajib)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _busy ? null : () => _respond(true),
                              style: FilledButton.styleFrom(
                                backgroundColor: context.success,
                                foregroundColor: context.isDark
                                    ? context.surface
                                    : Colors.white,
                              ),
                              child: const Text('Terima & cabut SP'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy ? null : () => _respond(false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.danger,
                              ),
                              child: const Text('Tolak'),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(
                        'Menunggu respons Super Admin.',
                        style: textTheme.bodySmall?.copyWith(
                          color: context.warning,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ] else if (_isMine &&
                      !_showAppealForm &&
                      !letter.voided)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _showAppealForm = true),
                      icon: const Icon(Icons.edit_note_outlined, size: 18),
                      label: const Text('Ajukan sanggahan'),
                    )
                  else if (!_isMine)
                    const Text('Belum ada sanggahan.')
                  else
                    const SizedBox.shrink(),
                  if (_isMine &&
                      letter.appeal == null &&
                      _showAppealForm) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _appealController,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: WarningRules.maxAppeal,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Tulis sanggahan Anda',
                        hintText:
                            'Jelaskan duduk perkara menurut versi Anda…',
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton(
                      onPressed: _busy ? null : _sendAppeal,
                      child: const Text('Kirim sanggahan'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final color = switch (level) {
      1 => context.warning,
      2 => Colors.deepOrange,
      _ => context.danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'SP $level',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: context.inkSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
