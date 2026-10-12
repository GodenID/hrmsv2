import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/app_exception.dart';
import '../../data/attendance_repository.dart';
import '../shell/shell_routes.dart';
import 'location_form_page.dart';

/// Super Admin: daftar lokasi absen + radius. Karyawan hanya bisa clock in
/// / clock out bila berada di dalam radius salah satu lokasi ini.
class AttendanceLocationsPage extends StatefulWidget {
  const AttendanceLocationsPage({super.key});

  @override
  State<AttendanceLocationsPage> createState() =>
      _AttendanceLocationsPageState();
}

class _AttendanceLocationsPageState extends State<AttendanceLocationsPage> {
  late AttendanceRepository _repo;
  bool _initialized = false;

  List<AttendanceLocation>? _locations;
  bool _isLoading = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).attendance;
    _repo.changes.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _repo.changes.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await _repo.fetchLocations(SessionScope.userOf(context));
      if (mounted) setState(() => _locations = list);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Lokasi absen gagal dimuat. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openForm([AttendanceLocation? location]) async {
    final result = await Navigator.of(context).pushNamed<LocationFormResult>(
      ShellRoutes.locationForm,
      arguments: location,
    );
    if (!mounted || result == null) return;
    showAppSnackBar(
      context,
      result == LocationFormResult.deleted
          ? 'Lokasi absen dihapus.'
          : 'Lokasi absen disimpan. Langsung berlaku untuk absen berikutnya.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = AppSpacing.isSidebarLayout(MediaQuery.sizeOf(context).width);
    final textTheme = Theme.of(context).textTheme;

    return PageScaffold(
      title: 'Lokasi absen',
      onRefresh: _load,
      maxWidth: 760,
      actions: [
        if (isWide)
          FilledButton.icon(
            onPressed: () => _openForm(),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text('Tambah lokasi'),
          )
        else
          TextButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: const Text('Tambah'),
          ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Karyawan hanya bisa clock in dan clock out bila posisinya berada '
            'di dalam radius salah satu lokasi berikut. Atur titik & '
            'radiusnya sesuai area kantor.',
            style: textTheme.bodyMedium?.copyWith(
              color: context.inkSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AsyncBody(
            isLoading: _isLoading,
            error: _error,
            hasData: _locations != null,
            onRetry: _load,
            loadingLabel: 'Memuat lokasi absen…',
            builder: (context) => _buildList(_locations!),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<AttendanceLocation> locations) {
    final textTheme = Theme.of(context).textTheme;
    final remaining = LocationRules.plannedCount - locations.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          '${locations.length} lokasi aktif',
          trailing: Text(
            'Rencana ${LocationRules.plannedCount} lokasi',
            style: textTheme.bodySmall,
          ),
        ),
        if (locations.isEmpty)
          const Panel(
            padding: EdgeInsets.zero,
            child: EmptyState(
              icon: Icons.location_off_outlined,
              title: 'Belum ada lokasi absen',
              message:
                  'Karyawan belum bisa clock in sampai minimal satu lokasi '
                  'ditambahkan.',
            ),
          )
        else
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < locations.length; i++) ...[
                  if (i > 0) const Divider(),
                  _LocationRow(
                    number: i + 1,
                    location: locations[i],
                    onTap: () => _openForm(locations[i]),
                  ),
                ],
              ],
            ),
          ),
        if (remaining > 0) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Masih bisa menambah $remaining lokasi lagi sesuai rencana.',
            style: textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text(
          'Tips: berdirilah di titik tengah kantor lalu pakai "Gunakan lokasi '
          'saya saat ini" di formulir agar koordinatnya akurat.',
          style: textTheme.bodySmall?.copyWith(height: 1.5),
        ),
      ],
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.number,
    required this.location,
    required this.onTap,
  });

  final int number;
  final AttendanceLocation location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final l = location;

    return Semantics(
      button: true,
      label:
          'Lokasi $number: ${l.name}. Radius ${l.radiusMeters} meter. '
          'Ketuk untuk mengubah.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        hoverColor: context.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.accentSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: const Color(0xFFC6DDDA)),
                ),
                child: Text(
                  '$number',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.accentText,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.name,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l.coordinatesLabel,
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              StatusChip(
                label: 'Radius ${l.radiusMeters} m',
                tone: ChipTone.accent,
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: context.inkTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
