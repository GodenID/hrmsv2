import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/widgets/area_map.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/attendance_repository.dart';
import '../../../data/auth_repository.dart';

/// Hasil lembar radar: jam langsung tercatat, atau pengajuan luar area
/// terkirim dan menunggu persetujuan.
class ClockRadarResult {
  const ClockRadarResult.recorded(this.record) : request = null;

  const ClockRadarResult.submitted(this.request) : record = null;

  final AttendanceRecord? record;
  final OutOfAreaRequest? request;

  bool get isRecorded => record != null;
}

/// Lembar konfirmasi clock in / clock out dengan visual radar: titik
/// lokasi absen + radiusnya, posisi pengguna, dan jarak keduanya.
/// Di dalam radius → clock biasa; di luar radius → pengajuan luar area
/// (butuh alasan, menunggu persetujuan Atasan).
Future<ClockRadarResult?> showClockRadarSheet(
  BuildContext context, {
  required AuthUser user,
  required AttendanceRepository repository,
  required OutOfAreaKind action,
  required GeoPoint position,
  required List<AttendanceLocation> locations,
}) {
  return showModalBottomSheet<ClockRadarResult>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (context) => _ClockRadarSheet(
      user: user,
      repository: repository,
      action: action,
      position: position,
      locations: locations,
    ),
  );
}

class _ClockRadarSheet extends StatefulWidget {
  const _ClockRadarSheet({
    required this.user,
    required this.repository,
    required this.action,
    required this.position,
    required this.locations,
  });

  final AuthUser user;
  final AttendanceRepository repository;
  final OutOfAreaKind action;
  final GeoPoint position;
  final List<AttendanceLocation> locations;

  @override
  State<_ClockRadarSheet> createState() => _ClockRadarSheetState();
}

class _ClockRadarSheetState extends State<_ClockRadarSheet> {
  String? _selectedId;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _mocked => widget.position.isMocked;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// Lokasi yang ditampilkan: pilihan pengguna, atau yang terdekat.
  AttendanceLocation get _location {
    final locations = widget.locations;
    for (final l in locations) {
      if (l.id == _selectedId) return l;
    }
    var best = locations.first;
    var bestDistance = double.infinity;
    for (final l in locations) {
      final d = l.distanceTo(
        widget.position.latitude,
        widget.position.longitude,
      );
      if (d < bestDistance) {
        bestDistance = d;
        best = l;
      }
    }
    return best;
  }

  double get _distance => _location.distanceTo(
    widget.position.latitude,
    widget.position.longitude,
  );

  bool get _inside => _distance <= _location.radiusMeters;

  Future<void> _submitInside() async {
    if (_busy || _mocked) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final record = widget.action == OutOfAreaKind.clockIn
          ? await widget.repository.clockIn(
              widget.user,
              position: widget.position,
            )
          : await widget.repository.clockOut(
              widget.user,
              position: widget.position,
            );
      if (mounted) Navigator.of(context).pop(ClockRadarResult.recorded(record));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu '
              'coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitOutside() async {
    if (_busy || _mocked) return;
    FocusScope.of(context).unfocus();
    final reason = _reason.text.trim();
    if (reason.length < OutOfAreaRules.minReasonLength) {
      setState(
        () => _error =
            'Alasan minimal ${OutOfAreaRules.minReasonLength} karakter.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = await widget.repository.submitOutOfArea(
        widget.user,
        kind: widget.action,
        position: widget.position,
        reason: reason,
      );
      if (mounted) {
        Navigator.of(context).pop(ClockRadarResult.submitted(request));
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu '
              'coba lagi.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final actionLabel = widget.action.label;
    final locations = widget.locations;
    final accuracy = widget.position.accuracyMeters;

    return SafeArea(
      child: SingleChildScrollView(
        // Ruang keyboard agar field alasan & tombol kirim tidak tertutup
        // saat keyboard HP muncul.
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      actionLabel,
                      style: textTheme.titleMedium?.copyWith(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (_mocked)
                  const StatusChip(
                    label: 'Lokasi palsu',
                    tone: ChipTone.danger,
                  )
                else if (locations.isEmpty)
                  const StatusChip(
                    label: 'Belum ada lokasi',
                    tone: ChipTone.neutral,
                  )
                else
                  StatusChip(
                    label: _inside ? 'Di dalam area' : 'Di luar area',
                    tone: _inside ? ChipTone.success : ChipTone.warning,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (locations.isEmpty) ...[
              const FormErrorBanner(
                message:
                    'Belum ada lokasi absen yang diatur. Hubungi Super Admin.',
              ),
            ] else ...[
              if (locations.length > 1) ...[
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final l in locations)
                      ChoiceChip(
                        label: Text(l.name),
                        selected: l.id == _location.id,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _selectedId = l.id),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              _AreaMapView(
                location: _location,
                position: widget.position,
                distanceMeters: _distance,
                inside: _inside,
              ),
              const SizedBox(height: AppSpacing.md),
              _Readout(
                location: _location,
                distanceMeters: _distance,
                inside: _inside,
                accuracyMeters: accuracy,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (_error != null) ...[
                FormErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
              if (_mocked)
                const FormErrorBanner(
                  message:
                      'Lokasi palsu terdeteksi. Matikan aplikasi pemalsu '
                      'lokasi (mock location) lalu coba lagi.',
                )
              else if (_inside)
                PrimaryButton(
                  label: actionLabel,
                  loadingLabel: 'Mencatat…',
                  isLoading: _busy,
                  onPressed: _submitInside,
                )
              else ...[
                Panel(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.info_outline,
                          size: 18,
                          color: context.warning,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Anda di luar area absen. Pengajuan ini baru '
                          'tercatat sebagai jam $actionLabel setelah '
                          'disetujui Atasan.',
                          style: textTheme.bodySmall?.copyWith(height: 1.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                LabeledField(
                  label: 'Alasan',
                  child: TextFormField(
                    controller: _reason,
                    enabled: !_busy,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 300,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText:
                          'mis. Bertugas di venue klien sejak pagi.',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Ajukan $actionLabel',
                  loadingLabel: 'Mengirim…',
                  isLoading: _busy,
                  onPressed: _submitOutside,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Ringkasan posisi: lokasi, radius, jarak, dan akurasi perangkat.
class _Readout extends StatelessWidget {
  const _Readout({
    required this.location,
    required this.distanceMeters,
    required this.inside,
    required this.accuracyMeters,
  });

  final AttendanceLocation location;
  final double distanceMeters;
  final bool inside;
  final double? accuracyMeters;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accuracy = accuracyMeters;
    final poorAccuracy = accuracy != null && accuracy > 100;

    Widget row(IconData icon, String text, {Color? color}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                icon,
                size: 16,
                color: color ?? context.inkSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: textTheme.bodySmall?.copyWith(height: 1.45),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        row(Icons.place_outlined, location.name),
        row(
          Icons.radar_outlined,
          'Radius ${location.radiusMeters} m  ·  kamu '
          '${GeoMath.formatDistance(distanceMeters)} '
          '${inside ? 'di dalam' : 'di luar'}',
          color: inside ? context.success : context.warning,
        ),
        if (accuracy != null)
          row(
            Icons.my_location,
            'Akurasi perangkat ±${GeoMath.formatDistance(accuracy)}'
            '${poorAccuracy ? ' — aktifkan GPS / lokasi akurat.' : ''}',
            color: poorAccuracy ? context.warning : null,
          ),
      ],
    );
  }
}

/// Peta area absen sesungguhnya: pin lokasi + lingkaran radiusnya, titik
/// posisi pengguna, dan lingkaran akurasi GPS. Bisa digeser & dizoom.
class _AreaMapView extends StatelessWidget {
  const _AreaMapView({
    required this.location,
    required this.position,
    required this.distanceMeters,
    required this.inside,
  });

  final AttendanceLocation location;
  final GeoPoint position;
  final double distanceMeters;
  final bool inside;

  @override
  Widget build(BuildContext context) {
    final userColor = inside ? context.success : context.warning;
    final accuracy = position.accuracyMeters;
    // Cakupan: radius + posisi pengguna selalu muat + napas.
    final maxRange = math.max(
      location.radiusMeters.toDouble(),
      distanceMeters * 1.15,
    );

    Widget dot(Color color, double border) {
      return DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(color: Colors.white, width: border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: color == AppColors.accent
            ? const Icon(Icons.place, size: 20, color: Colors.white)
            : null,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return AreaMap(
          centerLatitude:
              (location.latitude + position.latitude) / 2,
          centerLongitude:
              (location.longitude + position.longitude) / 2,
          zoom: _fitZoom(
            maxRange,
            (location.latitude + position.latitude) / 2,
            constraints.maxWidth,
          ),
          markers: [
            AreaMapMarker(
              latitude: location.latitude,
              longitude: location.longitude,
              width: 40,
              height: 40,
              child: dot(AppColors.accent, 2.5),
            ),
            AreaMapMarker(
              latitude: position.latitude,
              longitude: position.longitude,
              width: 34,
              height: 34,
              child: dot(userColor, 3),
            ),
          ],
          circles: [
            if (accuracy != null && accuracy > 0)
              AreaMapCircle(
                latitude: position.latitude,
                longitude: position.longitude,
                radiusMeters: accuracy,
                color: userColor.withValues(alpha: 0.14),
                borderColor: Colors.transparent,
                borderWidth: 0,
              ),
            AreaMapCircle(
              latitude: location.latitude,
              longitude: location.longitude,
              radiusMeters: location.radiusMeters.toDouble(),
              color: AppColors.accent.withValues(alpha: 0.12),
              borderColor: AppColors.accent,
            ),
          ],
          semanticsLabel:
              'Peta area absen. ${location.name}, radius '
              '${location.radiusMeters} meter. Kamu '
              '${GeoMath.formatDistance(distanceMeters)} '
              '${inside ? 'di dalam' : 'di luar'} area.',
        );
      },
    );
  }
}

/// Zoom pas agar [maxRangeMeters] (diameter pandang) muat di [widthPx].
/// Kembali ke 320px bila lebar belum terukur.
double _fitZoom(double maxRangeMeters, double latitude, double widthPx) {
  final metersPerPixel0 =
      156543.03 * math.cos(latitude * math.pi / 180);
  final width = widthPx <= 0 ? 320.0 : widthPx;
  final targetMpp = (maxRangeMeters * 2.4) / width;
  return (math.log(metersPerPixel0 / targetMpp) / math.ln2).clamp(3.0, 18.0);
}
