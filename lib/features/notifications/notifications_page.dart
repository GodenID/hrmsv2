import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/push_notifications.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/segment_toggle.dart';
import '../../data/auth_repository.dart';
import '../../data/notification_repository.dart';
import '../shell/shell_controller.dart';

/// Daftar notifikasi. Mengetuk notifikasi menandainya sudah dibaca lalu
/// membuka menu terkait (mis. Cuti, Persetujuan).
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late NotificationRepository _repo;
  bool _initialized = false;

  List<AppNotification>? _items;
  bool _isLoading = false;
  bool _isMarking = false;
  String? _error;
  final _searchController = TextEditingController();
  bool _unreadOnly = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).notifications;
    _repo.changes.addListener(_onChanged);
    AppRefresh.notifications.addListener(_onChanged);
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _repo.changes.removeListener(_onChanged);
    AppRefresh.notifications.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(AppNotification n, String q) {
    if (q.isNotEmpty &&
        !'${n.title} ${n.body}'.toLowerCase().contains(q)) {
      return false;
    }
    if (_unreadOnly && n.read) return false;
    return true;
  }

  void _onChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await _repo.fetch(SessionScope.userOf(context));
      if (mounted) setState(() => _items = items);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Notifikasi gagal dimuat. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markAllRead() async {
    setState(() => _isMarking = true);
    try {
      await _repo.markAllRead(SessionScope.userOf(context));
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Gagal memperbarui. Coba lagi.');
    } finally {
      if (mounted) setState(() => _isMarking = false);
    }
  }

  Future<void> _clearAll() async {
    final count = _items?.length ?? 0;
    if (count == 0) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus semua notifikasi?'),
        content: Text(
          '$count notifikasi akan dihapus permanen dan tidak bisa '
          'dikembalikan. Pengajuan, pengumuman, dan event terkait tidak '
          'ikut terhapus.',
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
            child: const Text('Hapus semua'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isMarking = true);
    try {
      await _repo.clearAll(SessionScope.userOf(context));
      if (mounted) {
        setState(() => _items = const []);
        showAppSnackBar(context, 'Semua notifikasi dihapus.');
      }
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Gagal menghapus. Coba lagi.');
    } finally {
      if (mounted) setState(() => _isMarking = false);
    }
  }

  Future<void> _open(AppNotification n) async {
    final user = SessionScope.userOf(context);
    final shell = ShellController.maybeOf(context);
    final navigator = Navigator.of(context);
    if (!n.read) {
      try {
        await _repo.markRead(user, id: n.id);
      } catch (_) {
        // Tetap buka menu tujuan walaupun status baca gagal disimpan.
      }
    }
    if (!mounted) return;
    // Tutup halaman notifikasi, lalu buka detail pengajuan / pengumuman / SP
    // terkait (atau menu tujuannya bila detailnya tidak ketemu).
    navigator.pop();
    await shell?.openLink(n.kind.name, n.refType, n.refId);
  }
  @override
  Widget build(BuildContext context) {
    final items = _items;
    final hasUnread = items?.any((n) => !n.read) ?? false;
    final hasItems = items?.isNotEmpty ?? false;
    final isWide = AppSpacing.isSidebarLayout(MediaQuery.sizeOf(context).width);

    return PageScaffold(
      title: 'Notifikasi',
      maxWidth: 720,
      busy: _isMarking,
      onRefresh: _load,
      actions: [
        // HP: ikon saja agar muat di AppBar.
        if (hasUnread)
          isWide
              ? TextButton.icon(
                  onPressed: _isMarking ? null : _markAllRead,
                  icon: const Icon(Icons.done_all, size: 18),
                  label: const Text('Tandai semua dibaca'),
                )
              : IconButton(
                  tooltip: 'Tandai semua dibaca',
                  onPressed: _isMarking ? null : _markAllRead,
                  icon: const Icon(Icons.done_all, size: 20),
                ),
        if (hasItems)
          isWide
              ? TextButton.icon(
                  onPressed: _isMarking ? null : _clearAll,
                  style: TextButton.styleFrom(
                    foregroundColor: context.danger,
                  ),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('Hapus semua'),
                )
              : IconButton(
                  tooltip: 'Hapus semua notifikasi',
                  onPressed: _isMarking ? null : _clearAll,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                ),
      ],
      child: AsyncBody(
        isLoading: _isLoading,
        error: _error,
        hasData: items != null,
        onRetry: _load,
        loadingLabel: 'Memuat notifikasi…',
        builder: (context) {
          // hasData menjamin tidak null; cek ini untuk analyzer.
          final all = items;
          if (all == null) return const SizedBox.shrink();
          final q = _searchController.text.trim().toLowerCase();
          final unread = all.where((n) => !n.read).length;
          final shown = [
            for (final n in all)
              if (_matches(n, q)) n,
          ];
          final filtering = q.isNotEmpty || _unreadOnly;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Cari notifikasi',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: q.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Hapus pencarian',
                          onPressed: _searchController.clear,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentToggle(
                options: [
                  'Semua (${all.length})',
                  'Belum dibaca ($unread)',
                ],
                selectedIndex: _unreadOnly ? 1 : 0,
                onSelect: (i) => setState(() => _unreadOnly = i == 1),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (shown.isEmpty)
                Panel(
                  padding: EdgeInsets.zero,
                  child: EmptyState(
                    icon: Icons.notifications_none,
                    title: filtering
                        ? 'Tidak ada yang cocok'
                        : 'Belum ada notifikasi',
                    message: filtering
                        ? 'Coba kata kunci lain atau tampilkan semua.'
                        : 'Hasil persetujuan, pengumuman baru, dan info event '
                            'akan muncul di sini.',
                  ),
                )
              else
                Panel(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < shown.length; i++) ...[
                        if (i > 0) const Divider(),
                        _NotificationRow(
                          notification: shown[i],
                          onTap: () => _open(shown[i]),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  (IconData, Color) _visual(BuildContext context, NotificationKind kind) =>
      switch (kind) {
        NotificationKind.leaveApproved ||
        NotificationKind.correctionApproved => (
          Icons.check_circle_outline,
          context.success,
        ),
        NotificationKind.leaveRejected ||
        NotificationKind.correctionRejected => (
          Icons.cancel_outlined,
          context.danger,
        ),
        NotificationKind.reviewRequested => (
          Icons.assignment_outlined,
          context.warning,
        ),
        NotificationKind.announcement => (
          Icons.campaign_outlined,
          context.accentText,
        ),
        NotificationKind.eventCancelled => (
          Icons.event_busy_outlined,
          context.danger,
        ),
        NotificationKind.eventToday => (
          Icons.today_outlined,
          context.accentText,
        ),
        NotificationKind.accountRegistered => (
          Icons.person_add_alt_outlined,
          context.accentText,
        ),
        NotificationKind.contractExpiring => (
          Icons.hourglass_bottom_outlined,
          context.warning,
        ),
        NotificationKind.contractExpired => (
          Icons.assignment_late_outlined,
          context.danger,
        ),
        NotificationKind.outOfAreaApproved => (
          Icons.check_circle_outline,
          context.success,
        ),
        NotificationKind.outOfAreaRejected => (
          Icons.cancel_outlined,
          context.danger,
        ),
        NotificationKind.overtimeApproved => (
          Icons.check_circle_outline,
          context.success,
        ),
        NotificationKind.overtimeRejected => (
          Icons.cancel_outlined,
          context.danger,
        ),
        NotificationKind.warningIssued => (
          Icons.gavel_outlined,
          context.danger,
        ),
        NotificationKind.warningExpiring => (
          Icons.hourglass_bottom_outlined,
          context.warning,
        ),
        NotificationKind.collectiveLeaveApplied => (
          Icons.beach_access_outlined,
          context.warning,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final n = notification;
    final (icon, color) = _visual(context, n.kind);

    return Semantics(
      button: true,
      label:
          '${n.read ? '' : 'Belum dibaca. '}${n.title}. ${n.body}. '
          '${DateFormatId.shortDateTime(n.createdAt)}',
      excludeSemantics: true,
      child: Material(
        color: n.read
            ? context.surface
            : context.accentSubtle.withValues(alpha: 0.45),
        child: InkWell(
          onTap: onTap,
          hoverColor: context.surfaceMuted,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: n.read
                              ? FontWeight.w500
                              : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        n.body,
                        style: textTheme.bodySmall?.copyWith(
                          color: context.ink,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormatId.shortDateTime(n.createdAt),
                        style: textTheme.bodySmall?.copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (!n.read) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      color: context.accentText,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
