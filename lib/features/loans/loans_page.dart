import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';

/// Placeholder roadmap. Belum ada transaksi apa pun.
class LoansPage extends StatelessWidget {
  const LoansPage({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return PageScaffold(
      title: 'Peminjaman',
      maxWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.86, end: 1),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) => Center(
              child: Transform.scale(scale: scale, child: child),
            ),
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: context.accentSubtle,
                shape: BoxShape.circle,
                border: Border.all(color: context.accentText.withValues(alpha: 0.25)),
              ),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                size: 40,
                color: context.accentText,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: StatusChip(
              label: 'Segera hadir',
              tone: ChipTone.warning,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Peminjaman akan segera tersedia',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Ajukan pinjaman, pantau cicilan, dan lihat sisa pokok langsung '
            'dari aplikasi. Fitur ini sedang disiapkan.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: context.inkSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Yang akan tersedia', style: textTheme.labelMedium),
                const SizedBox(height: AppSpacing.sm),
                _line(context, 'Pengajuan dengan persetujuan atasan'),
                _line(context, 'Jadwal cicilan dan sisa pokok'),
                _line(context, 'Rekap peminjaman di laporan Excel'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 18,
              color: context.accentText,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}
