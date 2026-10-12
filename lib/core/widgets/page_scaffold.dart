import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/theme_colors.dart';

/// Aksi tambahan dari kerangka aplikasi (mis. lonceng notifikasi) yang
/// ditampilkan di AppBar halaman utama setiap menu pada tata letak HP.
class PageChrome extends InheritedWidget {
  const PageChrome({
    super.key,
    required this.rootActions,
    required super.child,
  });

  final List<Widget> rootActions;

  static List<Widget> rootActionsOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageChrome>()?.rootActions ??
      const [];

  @override
  bool updateShouldNotify(PageChrome oldWidget) =>
      rootActions != oldWidget.rootActions;
}

/// Kerangka setiap halaman di dalam shell.
///
/// - Desktop (ada menu samping): tanpa AppBar; judul + aksi menjadi header
///   di atas konten, sejajar dengan kolom konten.
/// - HP/tablet: AppBar putih dengan judul + aksi (+ [PageChrome] di halaman
///   utama menu).
/// Tombol kembali muncul otomatis bila halaman bisa di-pop.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.mobileTitle,
    this.showWideHeader = true,
    this.maxWidth = 880,
    this.onRefresh,
    this.busy = false,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;

  /// Pengganti judul di AppBar HP (mis. logo di Beranda).
  final Widget? mobileTitle;

  /// false bila konten sudah punya judul sendiri (mis. sapaan di Beranda).
  final bool showWideHeader;
  final double maxWidth;

  /// Tarik-untuk-menyegarkan (HP).
  final Future<void> Function()? onRefresh;

  /// Menampilkan garis progres tipis di atas (mis. saat menghapus).
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isWide = AppSpacing.isSidebarLayout(MediaQuery.sizeOf(context).width);
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    final textTheme = Theme.of(context).textTheme;

    Widget backButton() => IconButton(
      tooltip: 'Kembali',
      onPressed: busy ? null : () => Navigator.of(context).maybePop(),
      icon: const Icon(Icons.arrow_back, size: 20),
    );

    Widget scrollable(EdgeInsets padding, Widget content) {
      Widget view = SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: padding,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: content,
          ),
        ),
      );
      if (onRefresh != null) {
        view = RefreshIndicator(
          onRefresh: onRefresh!,
          color: context.accentText,
          child: view,
        );
      }
      return view;
    }

    final progress = busy
        ? const LinearProgressIndicator(minHeight: 2)
        : const SizedBox(height: 2);

    if (isWide) {
      final header = showWideHeader
          ? Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Row(
                children: [
                  if (canPop) ...[
                    backButton(),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(title, style: textTheme.headlineSmall),
                    ),
                  ),
                  ...actions,
                ],
              ),
            )
          : const SizedBox.shrink();

      return Scaffold(
        backgroundColor: context.surface,
        body: Column(
          children: [
            progress,
            Expanded(
              child: scrollable(
                const EdgeInsets.fromLTRB(40, 34, 40, 56),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, child],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.surface,
      appBar: AppBar(
        backgroundColor: context.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        toolbarHeight: 60,
        automaticallyImplyLeading: false,
        leading: canPop ? backButton() : null,
        titleSpacing: canPop ? 0 : 16,
        title:
            mobileTitle ??
            Semantics(
              header: true,
              child: Text(title, style: textTheme.titleMedium),
            ),
        shape: Border(bottom: BorderSide(color: context.border)),
        actions: [
          ...actions,
          if (!canPop) ...PageChrome.rootActionsOf(context),
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: progress,
        ),
      ),
      body: scrollable(const EdgeInsets.fromLTRB(16, 20, 16, 32), child),
    );
  }
}
