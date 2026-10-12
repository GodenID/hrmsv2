import 'package:flutter/material.dart';

import '../app_info.dart';
import '../theme/app_spacing.dart';

/// Lokasi aset logo resmi Prasasti Connect.
///
/// Dibuat dari `logopc.png` (latar dibuat transparan, bayangan lunak
/// di bawah simbol dibuang agar rata dengan elemen UI).
abstract final class BrandAssets {
  /// Logo lengkap: simbol "P" + tulisan "Prasasti Connect".
  static const String logo = 'assets/brand/logo.png';

  /// Simbol "P" saja, persegi, latar transparan.
  static const String mark = 'assets/brand/logo_mark.png';

  /// Rasio lebar : tinggi [logo] (1024 x 309 px).
  static const double logoAspectRatio = 1024 / 309;
}

/// Tanda merek ringkas: simbol "P" + nama aplikasi dalam tipografi UI.
/// Dipakai di tempat sempit (sidebar, app bar).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.showSubtitle = true, this.size = 34});

  /// Tampilkan "Prasasti Group" di bawah nama aplikasi.
  final bool showSubtitle;

  /// Ukuran sisi simbol.
  final double size;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Semantics(
      label: '${AppInfo.appName}, ${AppInfo.companyName}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            BrandAssets.mark,
            width: size,
            height: size,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppInfo.appName,
                  style: textTheme.titleMedium?.copyWith(
                    fontSize: 15,
                    height: 1.15,
                    letterSpacing: 0.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (showSubtitle) ...[
                  const SizedBox(height: 2),
                  Text(
                    AppInfo.companyName,
                    style: textTheme.bodySmall?.copyWith(fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo lengkap Prasasti Connect (simbol + tulisan) untuk halaman
/// identitas: layar pembuka, login, dan registrasi.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 56});

  /// Tinggi logo; lebar mengikuti [BrandAssets.logoAspectRatio].
  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppInfo.appName,
      image: true,
      excludeSemantics: true,
      child: Image.asset(
        BrandAssets.logo,
        // Ukuran tetap agar tata letak tidak bergeser saat gambar dimuat.
        height: height,
        width: height * BrandAssets.logoAspectRatio,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// [BrandLogo] yang tetap terbaca di mode gelap: teks navy logo diberi
/// medali putih. Di mode terang tampil polos seperti biasa.
class AdaptiveBrandLogo extends StatelessWidget {
  const AdaptiveBrandLogo({super.key, this.height = 56});

  final double height;

  @override
  Widget build(BuildContext context) {
    final logo = BrandLogo(height: height);
    if (Theme.of(context).brightness != Brightness.dark) return logo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: logo,
    );
  }
}
