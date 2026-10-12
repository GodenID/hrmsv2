import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_colors.dart';

/// Basemap OpenStreetMap standar: gratis, tanpa API key. Wajib
/// mencantumkan atribusi (ditampilkan otomatis oleh [AreaMap]) +
/// User-Agent valid (dikirim otomatis).
abstract final class MapTiles {
  static const String osmUrl =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  static TileLayer osm() => TileLayer(
    urlTemplate: osmUrl,
    userAgentPackageName: 'hrms_app',
    maxZoom: 19,
  );
}

/// Penanda titik di [AreaMap].
class AreaMapMarker {
  const AreaMapMarker({
    required this.latitude,
    required this.longitude,
    required this.child,
    this.width = 40,
    this.height = 40,
  });

  final double latitude;
  final double longitude;
  final Widget child;
  final double width;
  final double height;
}

/// Lingkaran radius (meter) di [AreaMap].
class AreaMapCircle {
  const AreaMapCircle({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.color,
    required this.borderColor,
    this.borderWidth = 2,
  });

  final double latitude;
  final double longitude;
  final double radiusMeters;
  final Color color;
  final Color borderColor;
  final double borderWidth;
}

/// Peta interaktif bersama (lembar absensi, form lokasi, dsb.): basemap
/// OSM + lingkaran + penanda + atribusi. Utara selalu di atas.
class AreaMap extends StatelessWidget {
  const AreaMap({
    super.key,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.zoom,
    this.height = 260,
    this.markers = const [],
    this.circles = const [],
    this.onTap,
    this.semanticsLabel,
  });

  final double centerLatitude;
  final double centerLongitude;
  final double zoom;
  final double height;
  final List<AreaMapMarker> markers;
  final List<AreaMapCircle> circles;

  /// Ketuk peta (mis. memilih titik lokasi). null = nonaktif.
  final void Function(double latitude, double longitude)? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final map = Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: context.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(centerLatitude, centerLongitude),
              initialZoom: zoom,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: onTap == null
                  ? null
                  : (_, point) => onTap!(point.latitude, point.longitude),
            ),
            children: [
              MapTiles.osm(),
              for (final c in circles)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: LatLng(c.latitude, c.longitude),
                      radius: c.radiusMeters,
                      useRadiusInMeter: true,
                      color: c.color,
                      borderColor: c.borderColor,
                      borderStrokeWidth: c.borderWidth,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  for (final m in markers)
                    Marker(
                      point: LatLng(m.latitude, m.longitude),
                      width: m.width,
                      height: m.height,
                      child: m.child,
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: ExcludeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '© OpenStreetMap contributors',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.inkSecondary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final label = semanticsLabel;
    if (label == null) return map;
    return Semantics(label: label, excludeSemantics: true, child: map);
  }
}
