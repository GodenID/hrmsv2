import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app_routes.dart';
import '../../core/session_storage.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/widgets/brand_loading.dart';
import '../../core/widgets/brand_mark.dart';
import '../../data/auth_repository.dart';
import '../shell/app_shell.dart';
import 'login_page.dart';

/// Halaman pertama: memutar video splash (6 detik, full-screen) sambil
/// memulihkan sesi tersimpan di background, lalu menuju Beranda
/// (sesi valid) atau halaman login dengan transisi fade + zoom.
///
/// - Durasi tunggu = durasi video itu sendiri (navigasi saat video selesai,
///   bukan timer hardcode), jadi ganti videonya tanpa ubah kode.
/// - Bila video gagal dimuat (aset rusak / codec tak didukung / mode uji),
///   otomatis fallback ke logo + langsung lanjut tanpa menunggu.
/// - Ketuk layar untuk melewati video lebih cepat.
class StartupPage extends StatefulWidget {
  const StartupPage({
    super.key,
    required this.authRepository,
    required this.sessionStorage,
  });

  final AuthRepository authRepository;
  final SessionStorage sessionStorage;

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  static const String _splashAsset = 'assets/splash/splash.mp4';

  /// Pengaman agar aplikasi tidak pernah macet di splash.
  static const Duration _forceTimeout = Duration(seconds: 15);

  VideoPlayerController? _controller;
  bool _videoReady = false;
  bool _videoFailed = false;
  bool _videoDone = false;
  bool _exiting = false;

  bool _restored = false;
  AuthSession? _session;
  bool _navigated = false;
  Timer? _forceTimer;

  @override
  void initState() {
    super.initState();
    _forceTimer = Timer(_forceTimeout, () {
      _videoFailed = true;
      _videoDone = true;
      _go();
    });
    _initVideo();
    _restore();
  }

  Future<void> _initVideo() async {
    try {
      final controller = VideoPlayerController.asset(_splashAsset);
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(false);
      controller.addListener(_onVideoTick);
      if (!mounted) return;
      setState(() => _videoReady = true);
      await controller.play();
    } catch (_) {
      // Aset hilang / codec tak didukung / lingkungan uji tanpa plugin:
      // fallback ke logo statis dan lanjut tanpa menunggu video.
      if (!mounted) return;
      setState(() {
        _videoFailed = true;
        _videoDone = true;
      });
      _go();
    }
  }

  void _onVideoTick() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.hasError) {
      controller.removeListener(_onVideoTick);
      if (mounted) {
        setState(() {
          _videoFailed = true;
          _videoDone = true;
        });
      }
      _go();
      return;
    }
    final position = controller.value.position;
    final duration = controller.value.duration;
    if (duration > Duration.zero &&
        position >= duration - const Duration(milliseconds: 120)) {
      controller.removeListener(_onVideoTick);
      if (mounted) setState(() => _videoDone = true);
      _go();
    }
  }

  Future<void> _restore() async {
    AuthSession? session;
    try {
      final token = await widget.sessionStorage.readToken();
      if (token != null) {
        final user = await widget.authRepository.restoreSession(token);
        session = AuthSession(token: token, user: user);
      }
    } on AuthException {
      // Token tidak berlaku lagi: hapus agar tidak dicoba terus.
      try {
        await widget.sessionStorage.clear();
      } catch (_) {}
    } catch (_) {
      // Penyimpanan / server tidak tersedia: lanjut ke login. Token tetap
      // disimpan agar dicoba lagi saat aplikasi dibuka berikutnya.
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _restored = true;
    });
    _go();
  }

  /// Berangkat hanya bila video selesai (atau gagal) DAN sesi selesai
  /// dipulihkan. Keluar dulu dengan fade cepat, lalu ganti rute dengan
  /// transisi fade + scale + geser naik yang sinematik.
  void _go() {
    if (_navigated || _exiting) return;
    if (!(_videoDone || _videoFailed) || !_restored) return;
    _navigated = true;
    if (!mounted) return;
    setState(() => _exiting = true);
    Future<void>.delayed(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      final session = _session;
      if (session != null) {
        // Langsung ke Beranda dengan sesi yang sudah dipulihkan.
        Navigator.of(context).pushReplacement(
          _cinematicRoute<void>(
            settings: const RouteSettings(name: AppRoutes.home),
            builder: (_) => AppShell(session: session),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          _cinematicRoute<void>(
            settings: const RouteSettings(name: AppRoutes.login),
            builder: (_) => LoginPage(
              authRepository: widget.authRepository,
              sessionStorage: widget.sessionStorage,
            ),
          ),
        );
      }
    });
  }

  /// Ketuk untuk melewati: hentikan video, tetap tunggu sesi bila belum
  /// selesai (ada pengaman timeout 15 detik).
  void _skip() {
    if (_videoDone || _exiting) return;
    try {
      _controller?.pause();
    } catch (_) {}
    setState(() => _videoDone = true);
    _go();
  }

  @override
  void dispose() {
    _forceTimer?.cancel();
    try {
      _controller?.removeListener(_onVideoTick);
    } catch (_) {}
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showVideo =
        _videoReady && !_videoFailed && controller != null;

    return Scaffold(
      backgroundColor: _videoFailed ? context.surface : Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: showVideo ? _skip : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedOpacity(
              opacity: _exiting ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              child: showVideo
                  ? Semantics(
                      label: 'Animasi pembuka Prasasti Connect',
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.size.width,
                          height: controller.value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      ),
                    )
                  : Center(
                      child: Semantics(
                        label: 'Memuat sesi',
                        liveRegion: true,
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AdaptiveBrandLogo(height: 64),
                            SizedBox(height: 28),
                            BrandPulseLogo(size: 44),
                          ],
                        ),
                      ),
                    ),
            ),
            // Petunjuk lewati: muncul halus setelah 1 detik, hanya saat
            // video berjalan.
            if (showVideo && !_exiting)
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.paddingOf(context).bottom + 20,
                child: const _SkipHint(),
              ),
          ],
        ),
      ),
    );
  }
}

/// Petunjuk "ketuk untuk lewati" yang fade-in setelah 1 detik.
class _SkipHint extends StatefulWidget {
  const _SkipHint();

  @override
  State<_SkipHint> createState() => _SkipHintState();
}

class _SkipHintState extends State<_SkipHint> {
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _opacity = 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 600),
      child: const Text(
        'Ketuk untuk lewati',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white54, fontSize: 12),
      ),
    );
  }
}

/// Transisi sinematik: halaman baru fade-in + scale dari 94% + geser naik
/// ringan, 650ms dengan kurva sinematik.
Route<T> _cinematicRoute<T>({
  required RouteSettings settings,
  required WidgetBuilder builder,
}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: const Duration(milliseconds: 650),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, 0.035),
                  end: Offset.zero,
                ).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}
