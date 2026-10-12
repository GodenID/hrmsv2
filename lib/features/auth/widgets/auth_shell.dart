import 'package:flutter/material.dart';

import '../../../core/app_info.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/widgets/brand_mark.dart';
import 'local_clock.dart';

/// Kerangka halaman autentikasi.
///
/// - Lebar >= 960: dua panel. Kiri = identitas portal + jam lokal
///   (latar abu sangat muda), kanan = formulir di atas putih.
/// - Lebar < 960: satu kolom, latar putih penuh, merek ringkas di atas.
class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.child});

  final Widget child;

  static const String _footer = AppInfo.footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= AppSpacing.splitBreakpoint) {
            return _SplitLayout(child: child);
          }
          return _SingleColumnLayout(child: child);
        },
      ),
    );
  }
}

class _SplitLayout extends StatelessWidget {
  const _SplitLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Panel identitas
        Expanded(
          flex: 5,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.surfaceMuted,
              border: Border(right: BorderSide(color: context.border)),
            ),
            child: LayoutBuilder(
              builder: (context, viewport) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewport.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(56, 48, 56, 40),
                    child: Column(
                      // Merek di atas, narasi + jam menempel di bawah.
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const AdaptiveBrandLogo(height: 64),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: AppSpacing.xxxl),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 440),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Portal Karyawan',
                                    style: textTheme.headlineSmall?.copyWith(
                                      fontSize: 34,
                                      height: 40 / 34,
                                      letterSpacing: -0.6,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Text(
                                    'Absensi, cuti, event, dan pengumuman '
                                    'karyawan ${AppInfo.companyName} dalam '
                                    'satu akun.',
                                    style: textTheme.bodyLarge?.copyWith(
                                      color: context.inkSecondary,
                                      height: 1.55,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xxxl),
                            const Divider(),
                            const SizedBox(height: AppSpacing.xl),
                            const LocalClock(),
                            const SizedBox(height: AppSpacing.xxxl),
                            Text(AuthShell._footer, style: textTheme.bodySmall),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Panel formulir
        Expanded(
          flex: 6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 28, 40, 0),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Butuh bantuan? Hubungi Tim HR',
                    style: textTheme.bodySmall,
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 32,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppSpacing.formMaxWidth,
                      ),
                      child: child,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SingleColumnLayout extends StatelessWidget {
  const _SingleColumnLayout({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, viewport) => SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              // minHeight = tinggi layar agar footer menempel di bawah,
              // tetapi konten tetap bisa di-scroll saat keyboard muncul.
              constraints: BoxConstraints(
                maxWidth: AppSpacing.formMaxWidth + 48,
                minHeight: viewport.maxHeight,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: AdaptiveBrandLogo(height: 56),
                        ),
                        const SizedBox(height: 40),
                        child,
                        const SizedBox(height: AppSpacing.xxl),
                      ],
                    ),
                    Text(
                      AuthShell._footer,
                      style: textTheme.bodySmall?.copyWith(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
