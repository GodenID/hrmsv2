import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/push_notifications.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/utils/date_format_id.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/loading_row.dart';
import '../../../core/widgets/panel.dart' show showAppSnackBar;
import '../../../data/announcement_repository.dart';
import '../../../data/auth_repository.dart';
import '../../shell/shell_routes.dart';
import '../announcement_detail_page.dart';
import 'announcement_editor.dart';

/// Pengumuman di dashboard: kartu yang bisa digeser kanan-kiri.
/// Ketuk kartu ("Baca selengkapnya") untuk membuka detail — saat itulah
/// karyawan tercatat sudah melihat.
class AnnouncementCarousel extends StatefulWidget {
  const AnnouncementCarousel({
    super.key,
    required this.user,
    required this.repository,
  });

  final AuthUser user;
  final AnnouncementRepository repository;

  @override
  State<AnnouncementCarousel> createState() => _AnnouncementCarouselState();
}

class _AnnouncementCarouselState extends State<AnnouncementCarousel> {
  static const double _gap = 12;

  List<AnnouncementFeedItem> _items = const [];
  bool _isLoading = true;
  String? _error;
  int _page = 0;
  PageController? _controller;

  bool get _canManage => widget.user.role.canManageAnnouncements;
  bool get _showViewCount => widget.user.role.canViewAnnouncementReaders;

  @override
  void initState() {
    super.initState();
    AppRefresh.announcements.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    AppRefresh.announcements.removeListener(_reload);
    _controller?.dispose();
    super.dispose();
  }

  void _reload() {
    if (mounted) _load();
  }

  /// viewportFraction tidak bisa diubah setelah dibuat, jadi controller
  /// dibuat ulang bila lebar melewati breakpoint.
  PageController _controllerFor(double fraction) {
    final current = _controller;
    if (current != null && current.viewportFraction == fraction) {
      return current;
    }
    final next = PageController(viewportFraction: fraction, initialPage: _page);
    _controller = next;
    if (current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return next;
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await widget.repository.fetchFeed(widget.user);
      if (!mounted) return;
      setState(() {
        _items = items;
        if (_page > items.length - 1) {
          _page = items.isEmpty ? 0 : items.length - 1;
        }
      });
      final controller = _controller;
      if (controller != null && controller.hasClients) {
        final shown = controller.page?.round() ?? 0;
        if (shown != _page) controller.jumpToPage(_page);
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Pengumuman gagal dimuat. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toast(String message) => showAppSnackBar(context, message);

  void _goTo(int page) {
    final controller = _controller;
    if (controller == null || !controller.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpToPage(page);
    } else {
      controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _create() async {
    final saved = await showAnnouncementEditor(
      context,
      onSubmit: (draft) async {
        await widget.repository.create(actor: widget.user, draft: draft);
      },
    );
    if (!saved || !mounted) return;
    _toast('Pengumuman diterbitkan.');
    _page = 0;
    await _load();
    if (mounted) _goTo(0);
  }

  Future<void> _open(AnnouncementFeedItem item) async {
    final result = await Navigator.of(context)
        .pushNamed<AnnouncementDetailResult>(
          ShellRoutes.announcementDetail,
          arguments: item.announcement,
        );
    if (!mounted) return;
    if (result == AnnouncementDetailResult.deleted) {
      _toast('Pengumuman dihapus.');
    }
    // Segarkan status "Baru", jumlah dilihat, dan isi yang mungkin diedit.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 640;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, isWide),
            const SizedBox(height: AppSpacing.md),
            _buildBody(context, constraints.maxWidth, isWide),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, bool isWide) {
    final textTheme = Theme.of(context).textTheme;
    final hasMany = _items.length > 1;

    return Row(
      children: [
        Semantics(
          header: true,
          child: Text(
            'Pengumuman',
            style: textTheme.titleMedium?.copyWith(fontSize: 18),
          ),
        ),
        if (_items.isNotEmpty) ...[
          const SizedBox(width: AppSpacing.sm),
          _CountBadge(count: _items.length),
        ],
        const Spacer(),
        if (_canManage)
          OutlinedButton.icon(
            onPressed: _isLoading && _items.isEmpty ? null : _create,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Tambah'),
          ),
        if (isWide && hasMany) ...[
          const SizedBox(width: AppSpacing.sm),
          _ArrowButton(
            icon: Icons.chevron_left,
            tooltip: 'Pengumuman sebelumnya',
            onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
          ),
          const SizedBox(width: 6),
          _ArrowButton(
            icon: Icons.chevron_right,
            tooltip: 'Pengumuman berikutnya',
            onPressed: _page < _items.length - 1
                ? () => _goTo(_page + 1)
                : null,
          ),
        ],
      ],
    );
  }

  Widget _buildBody(BuildContext context, double width, bool isWide) {
    if (_isLoading && _items.isEmpty) {
      return const _Frame(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: LoadingRow(label: 'Memuat pengumuman…'),
        ),
      );
    }
    if (_error != null && _items.isEmpty) {
      return _Frame(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FormErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return _Frame(child: _EmptyState(canManage: _canManage));
    }

    // Satu kartu penuh di layar lebar; di HP kartu berikutnya sedikit
    // terlihat sebagai petunjuk bisa digeser.
    final single = _items.length == 1;
    final fraction = isWide || single ? 1.0 : 0.88;
    final controller = _controllerFor(fraction);
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final height = (isWide ? 196.0 : 212.0) * textScale.clamp(1.0, 1.8);

    // PageView dilebarkan sebesar celah agar tepi kartu tetap sejajar
    // dengan panel absensi di atasnya.
    final carousel = SizedBox(
      height: height,
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: width + _gap,
        maxWidth: width + _gap,
        child: ScrollConfiguration(
          // Izinkan geser dengan mouse di web/desktop.
          behavior: ScrollConfiguration.of(context)
              .copyWith(dragDevices: PointerDeviceKind.values.toSet()),
          child: PageView.builder(
            controller: controller,
            padEnds: false,
            itemCount: _items.length,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, index) {
              final item = _items[index];
              return Padding(
                padding: const EdgeInsets.only(right: _gap),
                child: _AnnouncementCard(
                  item: item,
                  position: index + 1,
                  total: _items.length,
                  showViewCount: _showViewCount,
                  onOpen: () => _open(item),
                ),
              );
            },
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        carousel,
        if (!single) ...[
          const SizedBox(height: 14),
          _PageDots(count: _items.length, current: _page),
        ],
      ],
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.item,
    required this.position,
    required this.total,
    required this.showViewCount,
    required this.onOpen,
  });

  final AnnouncementFeedItem item;
  final int position;
  final int total;
  final bool showViewCount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final a = item.announcement;
    final unread = !item.viewedByMe;
    // Paragraf digabung agar cuplikan 3 baris terisi penuh.
    final excerpt = a.body.replaceAll(RegExp(r'\s*\n+\s*'), ' ');

    return Semantics(
      button: true,
      label:
          'Pengumuman $position dari $total. ${unread ? 'Belum dibaca. ' : ''}'
          '${a.pinned ? 'Disematkan. ' : ''}'
          '${a.title}. Oleh ${a.authorName}, '
          '${DateFormatId.shortDate(a.publishedAt)}. Baca selengkapnya',
      excludeSemantics: true,
      onTap: onOpen,
      child: Material(
        color: context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.panel),
          side: BorderSide(color: context.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          hoverColor: context.surfaceMuted,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (a.pinned) ...[
                      Icon(
                        Icons.push_pin,
                        size: 14,
                        color: context.accentText,
                        semanticLabel: 'Disematkan',
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        '${a.authorName}  ·  '
                        '${DateFormatId.shortDate(a.publishedAt)}',
                        style: textTheme.bodySmall?.copyWith(fontSize: 12.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (unread) const _NewPill(),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  a.title,
                  style: textTheme.bodyLarge?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(
                    excerpt,
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.inkSecondary,
                      height: 1.55,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Baca selengkapnya',
                      style: textTheme.labelLarge?.copyWith(
                        color: context.accentText,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward,
                      size: 16,
                      color: context.accentText,
                    ),
                    const Spacer(),
                    if (showViewCount) ...[
                      Icon(
                        Icons.visibility_outlined,
                        size: 15,
                        color: context.inkSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${item.viewCount} dilihat',
                        style: textTheme.bodySmall?.copyWith(
                          fontSize: 12.5,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewPill extends StatelessWidget {
  const _NewPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: context.accentSubtle,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 6,
            height: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.accentText,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            'Baru',
            style: TextStyle(
              color: context.accentText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Titik penanda posisi; titik aktif memanjang.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return Semantics(
      label: 'Pengumuman ${current + 1} dari $count',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            AnimatedContainer(
              duration: duration,
              width: i == current ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == current
                    ? context.accentText
                    : context.borderStrong,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.outlined(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        fixedSize: const Size(40, 40),
        padding: EdgeInsets.zero,
        foregroundColor: context.ink,
        disabledForegroundColor: context.borderStrong,
        side: BorderSide(color: context.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: context.border),
      ),
      child: child,
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$count pengumuman',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
        decoration: BoxDecoration(
          color: context.surfaceMuted,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.border),
        ),
        child: Text(
          '$count',
          style: TextStyle(
            color: context.inkSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      child: Column(
        children: [
          Icon(
            Icons.campaign_outlined,
            size: 28,
            color: context.inkTertiary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Belum ada pengumuman',
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            canManage
                ? 'Gunakan tombol Tambah untuk menerbitkan informasi ke '
                      'semua karyawan.'
                : 'Pengumuman dari manajemen akan muncul di sini.',
            style: textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
