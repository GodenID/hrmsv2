import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';

/// Sisi foto profil hasil editor (px).
const int kProfilePhotoSize = 512;

/// Gambar tidak bisa dibaca (rusak / format tidak didukung).
class PhotoDecodeException implements Exception {
  const PhotoDecodeException();
}

/// Membuka editor foto profil:
/// - Potong: geser, perbesar (cubit / gulir / penggeser), putar, cermin.
/// - Sesuaikan: kecerahan, kontras, saturasi.
///
/// Mengembalikan PNG persegi [kProfilePhotoSize] px, atau null bila
/// dibatalkan. Melempar [PhotoDecodeException] bila gambar tidak terbaca.
Future<Uint8List?> showPhotoEditor(
  BuildContext context,
  Uint8List source,
) async {
  final image = await _decode(source);
  if (!context.mounted) {
    image.dispose();
    return null;
  }
  final fullscreen = MediaQuery.sizeOf(context).width < 640;
  return showDialog<Uint8List>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (context) {
      // Editor yang membuang [image] saat ditutup (setelah animasi selesai).
      final editor = PhotoEditor(image: image, fullscreen: fullscreen);
      if (fullscreen) {
        return Dialog.fullscreen(child: editor);
      }
      return Dialog(
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 720),
          child: editor,
        ),
      );
    },
  );
}

/// Decode sekali dengan sisi terpanjang maks. 2048 px (foto kamera HP bisa
/// 12+ MP; cukup besar untuk diperbesar 5x tanpa boros memori).
Future<ui.Image> _decode(Uint8List bytes) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) {
        const max = 2048;
        if (w <= max && h <= max) return ui.TargetImageSize();
        final s = max / math.max(w, h);
        return ui.TargetImageSize(
          width: (w * s).round(),
          height: (h * s).round(),
        );
      },
    );
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (_) {
    throw const PhotoDecodeException();
  }
}

/// Posisi & penyesuaian foto. Semua jarak dalam satuan sisi area potong
/// (1.0 = selebar lingkaran), jadi tidak bergantung ukuran layar dan bisa
/// dipakai ulang untuk merender hasil akhir.
@immutable
class _Edit {
  const _Edit({
    this.zoom = 1,
    this.offset = Offset.zero,
    this.turns = 0,
    this.flipped = false,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
  });

  /// 1 = sisi terpendek foto pas dengan lingkaran.
  final double zoom;

  /// Pusat foto relatif terhadap pusat lingkaran.
  final Offset offset;

  /// Putaran 90° (dalam ruang foto).
  final int turns;
  final bool flipped;

  /// -1 .. 1, 0 = asli.
  final double brightness;
  final double contrast;
  final double saturation;

  bool get isAdjusted => brightness != 0 || contrast != 0 || saturation != 0;

  _Edit copyWith({
    double? zoom,
    Offset? offset,
    int? turns,
    bool? flipped,
    double? brightness,
    double? contrast,
    double? saturation,
  }) => _Edit(
    zoom: zoom ?? this.zoom,
    offset: offset ?? this.offset,
    turns: turns ?? this.turns,
    flipped: flipped ?? this.flipped,
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
  );

  /// Matriks warna: saturasi, lalu kontras & kecerahan.
  ColorFilter? get colorFilter {
    if (!isAdjusted) return null;
    final s = 1 + saturation; // 0 .. 2
    final c = 1 + contrast * 0.5; // 0.5 .. 1.5
    // Kolom translasi ColorFilter.matrix memakai skala 0..255.
    final t = 128 * (1 - c) + brightness * 80;
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final r = lr * (1 - s), g = lg * (1 - s), b = lb * (1 - s);
    return ColorFilter.matrix([
      c * (r + s), c * g, c * b, 0, t, //
      c * r, c * (g + s), c * b, 0, t, //
      c * r, c * g, c * (b + s), 0, t, //
      0, 0, 0, 1, 0,
    ]);
  }
}

/// Ukuran foto setelah diputar, dalam satuan sisi lingkaran.
Size _displaySize(ui.Image image, _Edit e) {
  final w = image.width.toDouble(), h = image.height.toDouble();
  final rw = e.turns.isOdd ? h : w, rh = e.turns.isOdd ? w : h;
  final m = math.min(rw, rh);
  return Size(rw / m * e.zoom, rh / m * e.zoom);
}

/// Batasi geseran agar lingkaran selalu tertutup foto (tanpa celah kosong).
Offset _clampOffset(ui.Image image, _Edit e, Offset o) {
  final d = _displaySize(image, e);
  final mx = (d.width - 1) / 2, my = (d.height - 1) / 2;
  return Offset(o.dx.clamp(-mx, mx), o.dy.clamp(-my, my));
}

/// Menggambar foto dengan pusat lingkaran di [center] dan diameter [side].
/// Dipakai untuk pratinjau dan hasil akhir.
void _paintPhoto(
  Canvas canvas,
  ui.Image image,
  _Edit e, {
  required Offset center,
  required double side,
}) {
  final w = image.width.toDouble(), h = image.height.toDouble();
  final m = e.turns.isOdd ? math.min(h, w) : math.min(w, h);
  final k = side / m * e.zoom;
  canvas
    ..save()
    ..translate(center.dx + e.offset.dx * side, center.dy + e.offset.dy * side);
  if (e.flipped) canvas.scale(-1, 1);
  canvas
    ..rotate(e.turns * math.pi / 2)
    ..scale(k);
  final paint = Paint()
    ..filterQuality = FilterQuality.high
    ..isAntiAlias = true;
  final filter = e.colorFilter;
  if (filter != null) paint.colorFilter = filter;
  canvas
    ..drawImage(image, Offset(-w / 2, -h / 2), paint)
    ..restore();
}

class PhotoEditor extends StatefulWidget {
  const PhotoEditor({super.key, required this.image, this.fullscreen = false});

  /// Dimiliki editor: dibuang saat editor ditutup.
  final ui.Image image;
  final bool fullscreen;

  @override
  State<PhotoEditor> createState() => _PhotoEditorState();
}

class _PhotoEditorState extends State<PhotoEditor> {
  static const double _maxZoom = 5;

  /// Lingkaran potong = 86% area pratinjau; sisanya memperlihatkan bagian
  /// foto di luar potongan (diredupkan).
  static const double _cropFraction = 0.86;

  _Edit _edit = const _Edit();
  _ToolTab _tab = _ToolTab.crop;
  bool _interacting = false;
  bool _saving = false;
  double _gestureStartZoom = 1;
  final FocusNode _cropFocus = FocusNode(debugLabel: 'area potong foto');

  ui.Image get _image => widget.image;

  @override
  void dispose() {
    _cropFocus.dispose();
    widget.image.dispose();
    super.dispose();
  }

  void _update(_Edit next) {
    setState(() {
      _edit = next.copyWith(offset: _clampOffset(_image, next, next.offset));
    });
  }

  /// Perbesar ke [zoom] dengan titik [focal] (relatif pusat lingkaran,
  /// satuan sisi lingkaran) tetap di tempat.
  _Edit _zoomed(_Edit e, double zoom, [Offset focal = Offset.zero]) {
    final z = zoom.clamp(1.0, _maxZoom);
    final o = focal + (e.offset - focal) * (z / e.zoom);
    final next = e.copyWith(zoom: z);
    return next.copyWith(offset: _clampOffset(_image, next, o));
  }

  void _rotate() {
    final e = _edit;
    // Putar searah jarum jam di layar (saat dicermin, arah dibalik).
    _update(
      e.copyWith(
        turns: (e.turns + (e.flipped ? 3 : 1)) % 4,
        offset: Offset(-e.offset.dy, e.offset.dx),
      ),
    );
  }

  void _flip() {
    final e = _edit;
    _update(
      e.copyWith(
        flipped: !e.flipped,
        offset: Offset(-e.offset.dx, e.offset.dy),
      ),
    );
  }

  void _reset() => setState(() => _edit = const _Edit());

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    const step = 0.02;
    final e = _edit;
    final key = event.logicalKey;
    // Panah = geser foto ke arah tersebut.
    final move = switch (key) {
      LogicalKeyboardKey.arrowLeft => const Offset(-step, 0),
      LogicalKeyboardKey.arrowRight => const Offset(step, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, -step),
      LogicalKeyboardKey.arrowDown => const Offset(0, step),
      _ => null,
    };
    if (move != null) {
      _update(e.copyWith(offset: e.offset + move));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.add ||
        key == LogicalKeyboardKey.numpadAdd) {
      setState(() => _edit = _zoomed(e, e.zoom * 1.1));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      setState(() => _edit = _zoomed(e, e.zoom / 1.1));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      const size = kProfilePhotoSize;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        Paint()..color = Colors.white,
      );
      _paintPhoto(
        canvas,
        _image,
        _edit,
        center: const Offset(size / 2, size / 2),
        side: size.toDouble(),
      );
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(size, size);
      picture.dispose();
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      rendered.dispose();
      if (!mounted) return;
      if (data == null) throw StateError('encode gagal');
      Navigator.of(context).pop(data.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Foto gagal diproses. Coba lagi.')),
      );
    }
  }

  Widget _cropArea(double viewport) {
    final cropSide = viewport * _cropFraction;
    final center = Offset(viewport / 2, viewport / 2);
    Offset toUnits(Offset local) => (local - center) / cropSide;

    final painter = _CropPainter(
      image: _image,
      edit: _edit,
      cropSide: cropSide,
      showGrid: _interacting,
    );

    return Semantics(
      label:
          'Area potong foto. Geser untuk mengatur posisi, tombol panah untuk '
          'menggeser, plus atau minus untuk memperbesar.',
      child: Focus(
        focusNode: _cropFocus,
        onKeyEvent: _onKey,
        child: Listener(
          // Gulir mouse / trackpad = perbesar di titik kursor.
          onPointerSignal: (event) {
            if (event is! PointerScrollEvent) return;
            GestureBinding.instance.pointerSignalResolver.register(event, (e) {
              final s = e as PointerScrollEvent;
              final factor = math.exp(-s.scrollDelta.dy / 300);
              setState(() {
                _edit = _zoomed(
                  _edit,
                  _edit.zoom * factor,
                  toUnits(s.localPosition),
                );
              });
            });
          },
          child: GestureDetector(
            onTapDown: (_) => _cropFocus.requestFocus(),
            onScaleStart: (_) {
              _gestureStartZoom = _edit.zoom;
              setState(() => _interacting = true);
            },
            onScaleUpdate: (d) {
              setState(() {
                final panned = _edit.copyWith(
                  offset: _edit.offset + d.focalPointDelta / cropSide,
                );
                _edit = _zoomed(
                  panned,
                  _gestureStartZoom * d.scale,
                  toUnits(d.localFocalPoint),
                );
              });
            },
            onScaleEnd: (_) => setState(() => _interacting = false),
            child: MouseRegion(
              cursor: _interacting
                  ? SystemMouseCursors.grabbing
                  : SystemMouseCursors.grab,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.panel),
                child: SizedBox.square(
                  dimension: viewport,
                  child: CustomPaint(painter: painter),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Widget _cropControls() {
    final e = _edit;
    final enabled = !_saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Perkecil',
              onPressed: enabled && e.zoom > 1
                  ? () => setState(() => _edit = _zoomed(e, e.zoom / 1.25))
                  : null,
              icon: const Icon(Icons.zoom_out, size: 22),
            ),
            Expanded(
              child: Slider(
                value: e.zoom,
                min: 1,
                max: _maxZoom,
                label: '${(e.zoom * 100).round()}%',
                semanticFormatterCallback: (v) =>
                    'Perbesaran ${(v * 100).round()} persen',
                onChanged: enabled
                    ? (v) => setState(() => _edit = _zoomed(_edit, v))
                    : null,
              ),
            ),
            IconButton(
              tooltip: 'Perbesar',
              onPressed: enabled && e.zoom < _maxZoom
                  ? () => setState(() => _edit = _zoomed(e, e.zoom * 1.25))
                  : null,
              icon: const Icon(Icons.zoom_in, size: 22),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          alignment: WrapAlignment.center,
          children: [
            _toolButton(
              icon: Icons.rotate_right,
              label: 'Putar',
              onPressed: enabled ? _rotate : null,
            ),
            _toolButton(
              icon: Icons.flip,
              label: 'Cermin',
              onPressed: enabled ? _flip : null,
            ),
            TextButton.icon(
              onPressed: enabled ? _reset : null,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Atur ulang'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _adjustControls() {
    final e = _edit;
    final enabled = !_saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AdjustSlider(
          icon: Icons.light_mode_outlined,
          label: 'Kecerahan',
          value: e.brightness,
          onChanged: enabled
              ? (v) => setState(() => _edit = _edit.copyWith(brightness: v))
              : null,
        ),
        _AdjustSlider(
          icon: Icons.contrast,
          label: 'Kontras',
          value: e.contrast,
          onChanged: enabled
              ? (v) => setState(() => _edit = _edit.copyWith(contrast: v))
              : null,
        ),
        _AdjustSlider(
          icon: Icons.palette_outlined,
          label: 'Saturasi',
          value: e.saturation,
          onChanged: enabled
              ? (v) => setState(() => _edit = _edit.copyWith(saturation: v))
              : null,
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
    child: Semantics(
      header: true,
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    ),
  );

  /// Pilihan panel kontrol pada tata letak bertumpuk (HP).
  Widget _tabSwitcher() {
    return SegmentedButton<_ToolTab>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: context.accentSubtle,
        selectedForegroundColor: context.accentText,
        foregroundColor: context.inkSecondary,
        side: BorderSide(color: context.borderStrong),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),
      segments: const [
        ButtonSegment(
          value: _ToolTab.crop,
          icon: Icon(Icons.crop, size: 18),
          label: Text('Potong'),
        ),
        ButtonSegment(
          value: _ToolTab.adjust,
          icon: Icon(Icons.tune, size: 18),
          label: Text('Sesuaikan'),
        ),
      ],
      selected: {_tab},
      onSelectionChanged: (s) => setState(() => _tab = s.first),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'Atur foto profil',
                style: textTheme.titleMedium?.copyWith(fontSize: 18),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Tutup',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 22),
          ),
        ],
      ),
    );

    final hint = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Text(
        'Seret foto untuk mengatur posisi. Cubit atau gulir untuk '
        'memperbesar.',
        style: textTheme.bodySmall,
      ),
    );

    final footer = Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: context.inkSecondary,
            ),
            child: const Text('Batal'),
          ),
          const SizedBox(width: AppSpacing.sm),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size(132, 44)),
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Simpan foto'),
          ),
        ],
      ),
    );

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Layar lebar: pratinjau kiri, kontrol kanan (semua terlihat
          // tanpa menggulir). Sempit: kontrol dibagi dua tab.
          final sideBySide = constraints.maxWidth >= 760;

          if (sideBySide) {
            final viewport = math
                .min(420.0, constraints.maxHeight - 190)
                .clamp(240.0, 420.0);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                hint,
                const SizedBox(height: AppSpacing.lg),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Di luar area gulir agar seret foto tidak
                        // menggulir panel.
                        _cropArea(viewport),
                        const SizedBox(width: AppSpacing.xl),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _sectionLabel('POTONG'),
                                _cropControls(),
                                const SizedBox(height: AppSpacing.xl),
                                _sectionLabel('SESUAIKAN'),
                                _adjustControls(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                footer,
              ],
            );
          }

          final viewport = math.max(
            200.0,
            math.min(
              math.min(constraints.maxWidth - 40, 420.0),
              constraints.maxHeight - 360,
            ),
          );
          final panel = SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: _tab == _ToolTab.crop ? _cropControls() : _adjustControls(),
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              hint,
              const SizedBox(height: AppSpacing.md),
              Center(child: _cropArea(viewport)),
              const SizedBox(height: AppSpacing.md),
              Center(child: _tabSwitcher()),
              const SizedBox(height: AppSpacing.xs),
              if (widget.fullscreen)
                Expanded(child: panel)
              else
                Flexible(child: panel),
              const Divider(),
              footer,
            ],
          );
        },
      ),
    );
  }
}

enum _ToolTab { crop, adjust }

class _AdjustSlider extends StatelessWidget {
  const _AdjustSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final percent = (value * 100).round();
    final text = percent > 0 ? '+$percent' : '$percent';

    return Row(
      children: [
        const SizedBox(width: 8),
        Icon(icon, size: 18, color: context.inkSecondary),
        const SizedBox(width: 10),
        SizedBox(width: 84, child: Text(label, style: textTheme.bodyMedium)),
        Expanded(
          child: Slider(
            value: value,
            min: -1,
            max: 1,
            divisions: 40,
            label: text,
            semanticFormatterCallback: (v) => '$label ${(v * 100).round()}',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            text,
            textAlign: TextAlign.right,
            style: textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Pratinjau: foto + redup di luar lingkaran + garis bantu saat digeser.
class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.edit,
    required this.cropSide,
    required this.showGrid,
  });

  final ui.Image image;
  final _Edit edit;
  final double cropSide;
  final bool showGrid;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final center = bounds.center;
    canvas.drawRect(bounds, Paint()..color = AppColors.ink);
    _paintPhoto(canvas, image, edit, center: center, side: cropSide);

    final circle = Rect.fromCenter(
      center: center,
      width: cropSide,
      height: cropSide,
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(bounds)
        ..addOval(circle),
      Paint()..color = Colors.black.withValues(alpha: 0.6),
    );

    if (showGrid) {
      final grid = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = 1;
      canvas
        ..save()
        ..clipPath(Path()..addOval(circle));
      for (var i = 1; i < 3; i++) {
        final x = circle.left + circle.width * i / 3;
        final y = circle.top + circle.height * i / 3;
        canvas
          ..drawLine(Offset(x, circle.top), Offset(x, circle.bottom), grid)
          ..drawLine(Offset(circle.left, y), Offset(circle.right, y), grid);
      }
      canvas.restore();
    }

    canvas.drawOval(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.image != image ||
      old.edit != edit ||
      old.cropSide != cropSide ||
      old.showGrid != showGrid;
}
