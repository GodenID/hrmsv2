import 'dart:io';

import 'package:image/image.dart' as img;

/// Membuat foreground ikon adaptif Android: artwork `app_icon.png`
/// diperkecil (±70%) dan dipusatkan di kanvas putih 1024px, agar tidak
/// terpotong masker lingkaran/squircle launcher.
///
/// Dijalankan bila master ikon berubah:
///   flutter pub add image   (sementara; konflik versi dengan excel,
///                            hapus lagi setelah selesai)
///   dart run tool/make_icon_fg.dart
/// Lalu: dart run flutter_launcher_icons
void main() {
  final src = img.decodePng(
    File('assets/brand/app_icon.png').readAsBytesSync(),
  );
  if (src == null) {
    stderr.writeln('Gagal membaca assets/brand/app_icon.png');
    exit(1);
  }
  const size = 1024;
  final canvas = img.Image(width: size, height: size);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  final art = img.copyResize(
    src,
    width: (size * 0.7).round(),
    height: (size * 0.7).round(),
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(
    canvas,
    art,
    dstX: ((size - art.width) ~/ 2),
    dstY: ((size - art.height) ~/ 2),
  );
  File('assets/brand/app_icon_foreground.png')
      .writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('Ditulis assets/brand/app_icon_foreground.png');
}
