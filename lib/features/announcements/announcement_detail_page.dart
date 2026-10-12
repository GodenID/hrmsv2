import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/loading_row.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/announcement_repository.dart';
import '../../data/api/api_auth_repository.dart' show ApiConfig;
import '../../data/api/api_upload_repository.dart';
import '../../data/auth_repository.dart';
import 'widgets/announcement_editor.dart';
import 'widgets/read_report_section.dart';

enum AnnouncementDetailResult { deleted }

/// Halaman baca pengumuman.
/// - Semua role: isi lengkap. Membuka halaman ini = tercatat sudah melihat.
/// - Semua role: daftar siapa yang sudah/belum melihat.
/// - Super Admin: Edit & Hapus.
class AnnouncementDetailPage extends StatefulWidget {
  const AnnouncementDetailPage({
    super.key,
    required this.user,
    required this.initial,
    required this.repository,
  });

  final AuthUser user;
  final Announcement initial;
  final AnnouncementRepository repository;

  @override
  State<AnnouncementDetailPage> createState() => _AnnouncementDetailPageState();
}

class _AnnouncementDetailPageState extends State<AnnouncementDetailPage> {
  static const _networkError =
      'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu coba lagi.';

  late Announcement _announcement = widget.initial;
  String? _openError;

  AnnouncementReadReport? _report;
  bool _reportLoading = false;
  String? _reportError;

  bool _isDeleting = false;
  String? _openingKey;

  bool get _canManage => widget.user.role.canManageAnnouncements;
  bool get _canViewReaders => widget.user.role.canViewAnnouncementReaders;

  /// Buka lampiran dari S3 (mode API).
  Future<void> _openAttachment(AnnouncementAttachment attachment) async {
    final key = attachment.key;
    if (key == null || key.isEmpty || _openingKey != null) return;
    setState(() => _openingKey = key);
    try {
      final uploader = ApiUploadRepository(
        baseUrl: ApiConfig.baseUrl,
        sessionStorage: AppScope.of(context).sessionStorage,
      );
      final url = await uploader.viewUrl(key);
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const AppException('Dokumen tidak dapat dibuka.');
      }
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Dokumen tidak dapat dibuka.');
    } finally {
      if (mounted) setState(() => _openingKey = null);
    }
  }

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    setState(() => _openError = null);
    try {
      final a = await widget.repository.open(
        viewer: widget.user,
        id: widget.initial.id,
      );
      if (!mounted) return;
      setState(() => _announcement = a);
      // Laporan dimuat setelah tercatat, agar pengguna ini ikut terhitung.
      if (_canViewReaders) await _loadReport();
    } on AppException catch (e) {
      if (mounted) setState(() => _openError = e.message);
    } catch (_) {
      if (mounted) setState(() => _openError = _networkError);
    }
  }

  Future<void> _loadReport() async {
    setState(() {
      _reportLoading = true;
      _reportError = null;
    });
    try {
      final report = await widget.repository.fetchReadReport(
        actor: widget.user,
        id: _announcement.id,
      );
      if (mounted) setState(() => _report = report);
    } on AppException catch (e) {
      if (mounted) setState(() => _reportError = e.message);
    } catch (_) {
      if (mounted) setState(() => _reportError = _networkError);
    } finally {
      if (mounted) setState(() => _reportLoading = false);
    }
  }

  void _toast(String message) => showAppSnackBar(context, message);

  Future<void> _edit() async {
    final saved = await showAnnouncementEditor(
      context,
      initial: _announcement,
      onSubmit: (draft) async {
        final updated = await widget.repository.update(
          actor: widget.user,
          id: _announcement.id,
          draft: draft,
        );
        if (mounted) setState(() => _announcement = updated);
      },
    );
    if (saved && mounted) _toast('Pengumuman diperbarui.');
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus pengumuman?'),
        content: Text(
          '"${_announcement.title}" akan dihapus beserta catatan siapa saja '
          'yang sudah melihatnya. Tindakan ini tidak dapat dibatalkan.',
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
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 44),
              backgroundColor: context.danger,
              foregroundColor: context.isDark ? context.surface : Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await widget.repository.delete(actor: widget.user, id: _announcement.id);
      if (mounted) {
        Navigator.of(context).pop(AnnouncementDetailResult.deleted);
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        _toast(e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isDeleting = false);
        _toast('Pengumuman gagal dihapus. Coba lagi.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = AppSpacing.isSidebarLayout(MediaQuery.sizeOf(context).width);
    final disabled = _isDeleting;

    return PopScope(
      canPop: !_isDeleting,
      child: PageScaffold(
        title: 'Pengumuman',
        maxWidth: 680,
        busy: _isDeleting,
        actions: [
          if (_canManage) ...[
            if (isWide) ...[
              OutlinedButton.icon(
                onPressed: disabled ? null : _edit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: disabled ? null : _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.danger,
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Hapus'),
              ),
            ] else ...[
              IconButton(
                tooltip: 'Edit',
                onPressed: disabled ? null : _edit,
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
              IconButton(
                tooltip: 'Hapus',
                onPressed: disabled ? null : _delete,
                color: context.danger,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ],
        ],
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final a = _announcement;
    final meta = StringBuffer(
      '${a.authorName}  ·  ${DateFormatId.shortDateTime(a.publishedAt)}',
    );
    if (a.updatedAt != null) {
      meta.write('  ·  diedit ${DateFormatId.shortDateTime(a.updatedAt!)}');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_openError != null) ...[
          FormErrorBanner(message: _openError!),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Coba lagi'),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
        Text(meta.toString(), style: textTheme.bodySmall),
        if (a.pinned ||
            a.expiresAt != null ||
            a.targetDivisions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (a.pinned)
                const StatusChip(
                  label: 'Disematkan',
                  tone: ChipTone.accent,
                ),
              if (a.expiresAt != null)
                StatusChip(
                  label:
                      'Berlaku s.d. ${DateFormatId.shortDate(a.expiresAt!)}',
                  tone: ChipTone.neutral,
                ),
              if (a.targetDivisions.isNotEmpty)
                StatusChip(
                  label: a.targetDivisions.map((d) => d.label).join(', '),
                  tone: ChipTone.neutral,
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Semantics(
          header: true,
          child: Text(
            a.title,
            style: textTheme.headlineSmall?.copyWith(height: 1.25),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        SelectableText(
          a.body,
          style: textTheme.bodyLarge?.copyWith(
            height: 1.7,
            color: context.ink,
          ),
        ),
        if (a.attachments.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          const SectionLabel('Lampiran'),
          Panel(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Column(
              children: [
                for (final attachment in a.attachments)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Icon(
                          Icons.insert_drive_file_outlined,
                          size: 18,
                          color: context.inkSecondary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                attachment.name,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                attachment.sizeLabel,
                                style: textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (attachment.key != null && attachment.key!.isNotEmpty)
                          TextButton.icon(
                            onPressed: _openingKey != null
                                ? null
                                : () => _openAttachment(attachment),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: Text(
                              _openingKey == attachment.key ? 'Membuka…' : 'Lihat',
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (_canViewReaders) ...[
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: AppSpacing.xl),
          _buildReport(),
        ],
      ],
    );
  }

  Widget _buildReport() {
    final report = _report;
    if (report != null) return ReadReportSection(report: report);
    if (_reportError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FormErrorBanner(message: _reportError!),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: _loadReport,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Coba lagi'),
          ),
        ],
      );
    }
    if (_reportLoading || _openError == null) {
      return const LoadingRow(label: 'Memuat daftar pembaca…');
    }
    return const SizedBox.shrink();
  }
}
