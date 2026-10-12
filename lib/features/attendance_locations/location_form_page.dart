import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/widgets/area_map.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../data/app_exception.dart';
import '../../data/attendance_repository.dart';

enum LocationFormResult { saved, deleted }

/// Tambah ([initial] null) / ubah lokasi absen. Hanya Super Admin.
class LocationFormPage extends StatefulWidget {
  const LocationFormPage({super.key, this.initial});

  final AttendanceLocation? initial;

  @override
  State<LocationFormPage> createState() => _LocationFormPageState();
}

class _LocationFormPageState extends State<LocationFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  late int _radius;

  bool _isSubmitting = false;
  bool _isLocating = false;
  String? _error;
  String? _positionNote;

  bool get _isEdit => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final l = widget.initial;
    _name = TextEditingController(text: l?.name);
    _lat = TextEditingController(text: l?.latitude.toStringAsFixed(6));
    _lng = TextEditingController(text: l?.longitude.toStringAsFixed(6));
    _radius = l?.radiusMeters ?? LocationRules.defaultRadius;
    // Peta pratinjau mengikuti ketikan koordinat.
    _lat.addListener(_onCoordChanged);
    _lng.addListener(_onCoordChanged);
  }

  void _onCoordChanged() {
    if (mounted) setState(() {});
  }

  double? get _parsedLat => LocationRules.parseCoordinate(_lat.text);
  double? get _parsedLng => LocationRules.parseCoordinate(_lng.text);

  /// Ketuk peta = pindahkan titik lokasi ke koordinat tersebut.
  void _pickOnMap(double latitude, double longitude) {
    if (_isSubmitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _lat.text = latitude.toStringAsFixed(6);
      _lng.text = longitude.toStringAsFixed(6);
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  /// Tempel "lat, lng" (mis. dari Google Maps) ke kolom latitude:
  /// otomatis dipecah ke dua kolom.
  void _maybeSplitPasted(String value) {
    final match = RegExp(
      r'^\s*(-?\d{1,3}(?:\.\d+)?)\s*[,;\s]\s*(-?\d{1,3}(?:\.\d+)?)\s*$',
    ).firstMatch(value);
    if (match == null) return;
    _lat.text = match.group(1)!;
    _lng.text = match.group(2)!;
    _lat.selection = TextSelection.collapsed(offset: _lat.text.length);
  }

  Future<void> _useCurrentLocation() async {
    if (_isLocating) return;
    setState(() {
      _isLocating = true;
      _error = null;
      _positionNote = null;
    });
    try {
      final p = await AppScope.of(context).platform.getCurrentPosition();
      if (!mounted) return;
      final accuracy = p.accuracyMeters;
      setState(() {
        _lat.text = p.latitude.toStringAsFixed(6);
        _lng.text = p.longitude.toStringAsFixed(6);
        _positionNote = accuracy == null
            ? 'Koordinat diisi dari lokasi perangkat.'
            : 'Koordinat diisi dari lokasi perangkat (akurasi '
                  '±${GeoMath.formatDistance(accuracy)}).';
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _stepRadius(int delta) {
    setState(() {
      _radius = (_radius + delta).clamp(
        LocationRules.minRadius,
        LocationRules.maxRadius,
      );
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    setState(() => _error = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);
    try {
      await AppScope.of(context).attendance.saveLocation(
        SessionScope.userOf(context),
        id: widget.initial?.id,
        draft: AttendanceLocationDraft(
          name: _name.text.trim(),
          latitude: LocationRules.parseCoordinate(_lat.text)!,
          longitude: LocationRules.parseCoordinate(_lng.text)!,
          radiusMeters: _radius,
        ),
      );
      if (mounted) Navigator.of(context).pop(LocationFormResult.saved);
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
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _delete() async {
    final l = widget.initial;
    if (l == null || _isSubmitting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus lokasi absen?'),
        content: Text(
          'Karyawan tidak bisa lagi clock in di "${l.name}". Riwayat absensi '
          'yang sudah tercatat tidak berubah.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: context.inkSecondary,
            ),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 44),
              backgroundColor: context.danger,
              foregroundColor: context.isDark ? context.surface : Colors.white,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await AppScope.of(context).attendance
          .deleteLocation(SessionScope.userOf(context), id: l.id);
      if (mounted) Navigator.of(context).pop(LocationFormResult.deleted);
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
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final enabled = !_isSubmitting;
    final coordFormatters = [
      FilteringTextInputFormatter.allow(RegExp(r'[-\d.,;\s]')),
      LengthLimitingTextInputFormatter(40),
    ];

    return PopScope(
      canPop: !_isSubmitting,
      child: PageScaffold(
        title: _isEdit ? 'Ubah lokasi absen' : 'Tambah lokasi absen',
        maxWidth: 560,
        busy: _isSubmitting,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteractionIfError,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                FormErrorBanner(message: _error!),
                const SizedBox(height: AppSpacing.lg),
              ],
              LabeledField(
                label: 'Nama lokasi',
                child: TextFormField(
                  controller: _name,
                  enabled: enabled,
                  autofocus: !_isEdit,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [LengthLimitingTextInputFormatter(60)],
                  textInputAction: TextInputAction.next,
                  validator: LocationRules.validateName,
                  decoration: const InputDecoration(
                    hintText: 'mis. Kantor Pusat',
                    prefixIcon: Icon(Icons.apartment_outlined, size: 20),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionTitle('Titik lokasi'),
              OutlinedButton.icon(
                onPressed: enabled && !_isLocating ? _useCurrentLocation : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                icon: _isLocating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location, size: 18),
                label: Text(
                  _isLocating
                      ? 'Mengambil lokasi…'
                      : 'Gunakan lokasi saya saat ini',
                ),
              ),
              if (_positionNote != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  liveRegion: true,
                  child: Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        size: 16,
                        color: context.success,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(_positionNote!, style: textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LabeledField(
                      label: 'Latitude',
                      child: TextFormField(
                        controller: _lat,
                        enabled: enabled,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        inputFormatters: coordFormatters,
                        textInputAction: TextInputAction.next,
                        onChanged: _maybeSplitPasted,
                        validator: LocationRules.validateLatitude,
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                        decoration: const InputDecoration(
                          hintText: '-6.175392',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: LabeledField(
                      label: 'Longitude',
                      child: TextFormField(
                        controller: _lng,
                        enabled: enabled,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                          decimal: true,
                        ),
                        inputFormatters: coordFormatters,
                        textInputAction: TextInputAction.done,
                        validator: LocationRules.validateLongitude,
                        style: const TextStyle(
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                        decoration: const InputDecoration(
                          hintText: '106.827153',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Bisa juga tempel koordinat dari Google Maps (mis. '
                '"-6.175392, 106.827153") ke kolom Latitude, atau ketuk '
                'langsung petanya di bawah.',
                style: textTheme.bodySmall?.copyWith(height: 1.45),
              ),
              const SizedBox(height: AppSpacing.md),
              _LocationMapPicker(
                latitude: _parsedLat,
                longitude: _parsedLng,
                radiusMeters: _radius,
                enabled: enabled,
                onPick: _pickOnMap,
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionTitle('Radius absen'),
              _RadiusControl(
                radius: _radius,
                enabled: enabled,
                onChanged: (v) => setState(() => _radius = v),
                onStep: _stepRadius,
              ),
              const SizedBox(height: AppSpacing.xxl),
              PrimaryButton(
                label: _isEdit ? 'Simpan perubahan' : 'Tambah lokasi',
                loadingLabel: 'Menyimpan…',
                isLoading: _isSubmitting,
                onPressed: _submit,
              ),
              if (_isEdit) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: enabled ? _delete : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: context.danger,
                    side: BorderSide(
                      color: context.danger.withValues(alpha: 0.4),
                    ),
                  ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Hapus lokasi'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Pratinjau peta titik + radius. Ketuk peta untuk memindahkan titik ke
/// koordinat tersebut (kolom latitude/longitude ikut terisi).
class _LocationMapPicker extends StatelessWidget {
  const _LocationMapPicker({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.enabled,
    required this.onPick,
  });

  final double? latitude;
  final double? longitude;
  final int radiusMeters;
  final bool enabled;
  final void Function(double latitude, double longitude) onPick;

  @override
  Widget build(BuildContext context) {
    final lat = latitude;
    final lng = longitude;
    final valid = lat != null && lng != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AreaMap(
          // Jakarta sebagai latar bila koordinat belum valid.
          centerLatitude: lat ?? -6.2,
          centerLongitude: lng ?? 106.8,
          zoom: valid ? 16 : 11,
          height: 220,
          onTap: enabled ? onPick : null,
          markers: [
            if (valid)
              AreaMapMarker(
                latitude: lat,
                longitude: lng,
                width: 40,
                height: 40,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                      BorderSide(color: Colors.white, width: 2.5),
                    ),
                  ),
                  child: Icon(Icons.place, size: 20, color: Colors.white),
                ),
              ),
          ],
          circles: [
            if (valid)
              AreaMapCircle(
                latitude: lat,
                longitude: lng,
                radiusMeters: radiusMeters.toDouble(),
                color: AppColors.accent.withValues(alpha: 0.12),
                borderColor: AppColors.accent,
              ),
          ],
          semanticsLabel:
              'Peta pratinjau lokasi absen. Ketuk untuk memindahkan titik.',
        ),
        const SizedBox(height: 6),
        Text(
          valid
              ? 'Ketuk peta untuk memindahkan titik lokasi.'
              : 'Isi koordinat valid (atau ketuk peta) untuk pratinjau.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Semantics(
        header: true,
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ),
    );
  }
}

/// Slider radius + tombol -/+ (langkah 25 m) + keterangan.
class _RadiusControl extends StatelessWidget {
  const _RadiusControl({
    required this.radius,
    required this.enabled,
    required this.onChanged,
    required this.onStep,
  });

  final int radius;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onStep;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const min = LocationRules.minRadius;
    const max = LocationRules.maxRadius;
    const step = LocationRules.radiusStep;

    ButtonStyle style() => IconButton.styleFrom(
      fixedSize: const Size(40, 40),
      foregroundColor: context.ink,
      disabledForegroundColor: context.borderStrong,
      side: BorderSide(color: context.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: context.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  label: 'Radius $radius meter',
                  excludeSemantics: true,
                  child: Text.rich(
                    TextSpan(
                      text: '$radius',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: context.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      children: [
                        TextSpan(
                          text: ' meter',
                          style: textTheme.bodyMedium?.copyWith(
                            color: context.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton.outlined(
                tooltip: 'Kurangi $step m',
                onPressed: enabled && radius > min ? () => onStep(-step) : null,
                style: style(),
                icon: const Icon(Icons.remove, size: 18),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                tooltip: 'Tambah $step m',
                onPressed: enabled && radius < max ? () => onStep(step) : null,
                style: style(),
                icon: const Icon(Icons.add, size: 18),
              ),
            ],
          ),
          Slider(
            value: radius.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min) ~/ step,
            label: '$radius m',
            semanticFormatterCallback: (v) => '${v.round()} meter',
            onChanged: enabled ? (v) => onChanged(v.round()) : null,
          ),
          Row(
            children: [
              Text('$min m', style: textTheme.bodySmall),
              const Spacer(),
              Text('$max m', style: textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Karyawan harus berada maksimal $radius m dari titik lokasi untuk '
            'bisa clock in / clock out. Akurasi GPS di dalam gedung bisa '
            'meleset 10–50 m, jadi beri sedikit kelonggaran.',
            style: textTheme.bodySmall?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }
}
