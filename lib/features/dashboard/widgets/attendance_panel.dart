import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/platform_services.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/app_haptics.dart';
import '../../../core/utils/date_format_id.dart';
import '../../../core/utils/work_calendar.dart';
import '../../../core/widgets/animated_check.dart';
import '../../../core/widgets/form_widgets.dart';
import '../../../core/widgets/loading_row.dart';
import '../../../core/widgets/now_builder.dart';
import '../../../core/widgets/panel.dart';
import '../../../data/attendance_repository.dart';
import '../../../data/auth_repository.dart';
import '../../../features/attendance/widgets/clock_radar_sheet.dart';

enum _AttendanceAction { clockIn, clockOut }

/// Panel absensi hari ini: jam berjalan, kotak Clock in & Clock out
/// beserta jam tercatat, dan durasi kerja.
class AttendancePanel extends StatefulWidget {
  const AttendancePanel({
    super.key,
    required this.user,
    required this.repository,
  });

  final AuthUser user;
  final AttendanceRepository repository;

  @override
  State<AttendancePanel> createState() => _AttendancePanelState();
}

class _AttendancePanelState extends State<AttendancePanel> {
  AttendanceRecord? _record;
  List<OutOfAreaRequest> _outOfArea = [];
  bool _isLoading = true;
  String? _loadError;
  String? _actionError;
  bool _canOpenSettings = false;
  _AttendanceAction? _busy;

  /// true selama menunggu posisi GPS (sebelum dikirim ke server).
  bool _locating = false;

  static const _networkError =
      'Tidak dapat terhubung ke server. Periksa koneksi Anda lalu coba lagi.';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final record = await widget.repository.fetchToday(widget.user);
      if (!mounted) return;
      setState(() => _record = record);
      // Status pengajuan luar-area opsional: panel tetap tampil tanpanya
      // bila gagal dimuat.
      try {
        final outOfArea = await widget.repository.fetchMyOutOfArea(
          widget.user,
        );
        if (!mounted) return;
        setState(() => _outOfArea = outOfArea);
      } catch (_) {
        // Abaikan: bukan data utama panel.
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _loadError = _networkError);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Alur clock: ambil posisi + daftar lokasi, buka lembar radar untuk
  /// konfirmasi (di dalam area) atau pengajuan (di luar area).
  Future<void> _openSheet(_AttendanceAction action) async {
    if (_busy != null) return;
    final repository = widget.repository;
    setState(() {
      _busy = action;
      _locating = true;
      _actionError = null;
      _canOpenSettings = false;
    });
    try {
      final position = await AppScope.of(
        context,
      ).platform.getCurrentPosition();
      if (!mounted) return;
      final locations = await repository.fetchLocations(widget.user);
      if (!mounted) return;
      setState(() => _locating = false);
      final result = await showClockRadarSheet(
        context,
        user: widget.user,
        repository: repository,
        action: action == _AttendanceAction.clockIn
            ? OutOfAreaKind.clockIn
            : OutOfAreaKind.clockOut,
        position: position,
        locations: locations,
      );
      if (!mounted || result == null) return;
      await _load();
      if (!mounted) return;
      final isIn = action == _AttendanceAction.clockIn;
      final label = isIn ? 'Clock in' : 'Clock out';
      if (result.isRecorded) {
        final record = result.record!;
        final place = isIn ? record.clockInLocation : record.clockOutLocation;
        await showSuccessSheet(
          context,
          title: '$label tercatat',
          message:
              'Pukul ${DateFormatId.time(isIn ? record.clockIn! : record.clockOut!)}'
              '${place == null ? '.' : ' di $place.'}',
        );
      } else {
        unawaited(AppHaptics.success());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            width: MediaQuery.sizeOf(context).width >= 600 ? 420 : null,
            content: Text(
              'Pengajuan $label luar area pukul '
              '${DateFormatId.time(result.request!.requestedAt)} dikirim. '
              'Jam tercatat setelah disetujui Manager.',
            ),
          ),
        );
      }
    } on LocationUnavailableException catch (e) {
      if (mounted) {
        setState(() {
          _actionError = e.message;
          _canOpenSettings = e.canOpenSettings;
        });
      }
    } on AppException catch (e) {
      if (mounted) setState(() => _actionError = e.message);
    } catch (_) {
      if (mounted) setState(() => _actionError = _networkError);
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _locating = false;
        });
      }
    }
  }

  /// Banner pengajuan luar-area hari ini yang masih menunggu / ditolak.
  /// Yang disetujui sudah terlihat sebagai jam tercatat di kotak.
  List<Widget> _requestBanners() {
    final today = WorkCalendar.dateOnly(DateTime.now());
    final items = [
      for (final r in _outOfArea)
        if (WorkCalendar.isSameDay(r.date, today) &&
            r.status != RequestStatus.approved)
          r,
    ];
    if (items.isEmpty) return const [];
    return [
      for (final r in items) ...[
        Panel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  r.status == RequestStatus.pending
                      ? Icons.hourglass_bottom_outlined
                      : Icons.info_outline,
                  size: 18,
                  color: r.status == RequestStatus.pending
                      ? context.warning
                      : context.inkSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  r.status == RequestStatus.pending
                      ? 'Pengajuan ${r.kind.label} luar area pukul '
                            '${DateFormatId.time(r.requestedAt)} menunggu '
                            'persetujuan Manager.'
                      : 'Pengajuan ${r.kind.label} luar area '
                            '${r.status.label.toLowerCase()}'
                            '${r.reviewerNote == null ? '.' : ': “${r.reviewerNote}”'}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final record = _record;

    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: context.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 640;
          final pad = isWide ? 24.0 : 16.0;

          return Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Absensi hari ini',
                          style: textTheme.titleMedium,
                        ),
                      ),
                    ),
                    if (record != null) _StatusChip(status: record.status),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg + 4),
                if (_isLoading && record == null)
                  const LoadingRow(label: 'Memuat data absensi…')
                else if (_loadError != null && record == null) ...[
                  FormErrorBanner(message: _loadError!),
                  const SizedBox(height: AppSpacing.md),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Coba lagi'),
                    ),
                  ),
                ] else if (record != null) ...[
                  if (_actionError != null) ...[
                    FormErrorBanner(message: _actionError!),
                    if (_canOpenSettings)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () =>
                              AppScope.of(context).platform
                                  .openLocationSettings(),
                          icon: const Icon(Icons.settings_outlined, size: 18),
                          label: const Text('Buka pengaturan lokasi'),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                  ],
                  ..._requestBanners(),
                  _buildBody(record, isWide),
                  const SizedBox(height: AppSpacing.md),
                  _LocationLine(record: record, locating: _locating),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(),
                  const SizedBox(height: AppSpacing.md),
                  _DurationLine(record: record),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(AttendanceRecord record, bool isWide) {
    final tiles = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _AttendanceTile(
            label: 'Clock in',
            icon: Icons.login,
            recordedAt: record.clockIn,
            available: true,
            unavailableHint: '',
            isBusy: _busy == _AttendanceAction.clockIn,
            onPressed: _busy == null
                ? () => _openSheet(_AttendanceAction.clockIn)
                : null,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: _AttendanceTile(
            label: 'Clock out',
            icon: Icons.logout,
            recordedAt: record.clockOut,
            available: record.clockIn != null,
            unavailableHint: 'Menunggu clock in',
            isBusy: _busy == _AttendanceAction.clockOut,
            onPressed: _busy == null
                ? () => _openSheet(_AttendanceAction.clockOut)
                : null,
          ),
        ),
      ],
    );

    // Jam di tengah sebagai titik fokus, kotak Clock in/out di bawahnya.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: isWide ? 8 : 4),
          child: _LiveClock(large: isWide),
        ),
        SizedBox(height: isWide ? 28 : 20),
        tiles,
      ],
    );
  }
}

/// Jam berjalan (detik) + tanggal, rata tengah.
class _LiveClock extends StatelessWidget {
  const _LiveClock({required this.large});

  final bool large;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return NowBuilder(
      builder: (context, now) => Semantics(
        label:
            'Waktu sekarang ${DateFormatId.time(now)}, '
            '${DateFormatId.longDate(now)}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('WAKTU SEKARANG', style: textTheme.labelSmall),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                DateFormatId.timeWithSeconds(now),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: large ? 64 : 48,
                  height: 1.0,
                  fontWeight: FontWeight.w300,
                  letterSpacing: large ? -1.2 : -0.8,
                  color: context.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              DateFormatId.longDate(now),
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: context.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kotak Clock in / Clock out. Menampilkan jam tercatat atau tombol aksi.
class _AttendanceTile extends StatelessWidget {
  const _AttendanceTile({
    required this.label,
    required this.icon,
    required this.recordedAt,
    required this.available,
    required this.unavailableHint,
    required this.isBusy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final DateTime? recordedAt;

  /// false = belum bisa dipakai (mis. Clock out sebelum Clock in).
  final bool available;
  final String unavailableHint;
  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final recorded = recordedAt;
    final isRecorded = recorded != null;

    final String caption;
    if (isRecorded) {
      caption = 'Tercatat ${DateFormatId.timeWithSeconds(recorded)}';
    } else if (!available) {
      caption = unavailableHint;
    } else {
      caption = 'Belum tercatat';
    }

    return Semantics(
      container: true,
      label: isRecorded
          ? '$label tercatat pukul ${DateFormatId.time(recorded)}'
          : '$label belum tercatat',
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.panel),
          border: Border.all(color: context.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Row(
                children: [
                  Icon(icon, size: 15, color: context.inkSecondary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label.toUpperCase(),
                      style: textTheme.labelSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ExcludeSemantics(
              child: Text(
                isRecorded ? DateFormatId.time(recorded) : '--:--',
                style: TextStyle(
                  fontSize: 28,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.3,
                  color: isRecorded ? context.ink : context.inkTertiary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 4),
            ExcludeSemantics(
              child: SizedBox(
                // Tinggi tetap agar kedua kotak tetap sejajar.
                height: 18,
                child: FittedBox(
                  // Di layar sangat sempit teks mengecil, bukan terpotong.
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    caption,
                    style: textTheme.bodySmall?.copyWith(fontSize: 12.5),
                    maxLines: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: isRecorded
                  ? const _RecordedLabel()
                  : _buildButton(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context) {
    if (!available) {
      // Tombol nonaktif berwarna netral (bukan aksen) agar jelas belum bisa
      // dipakai.
      return FilledButton(
        onPressed: null,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          disabledBackgroundColor: context.border,
          disabledForegroundColor: context.inkTertiary,
        ),
        child: FittedBox(child: Text(label)),
      );
    }
    return FilledButton(
      onPressed: isBusy ? null : onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: isBusy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : FittedBox(child: Text(label)),
    );
  }
}

class _RecordedLabel extends StatelessWidget {
  const _RecordedLabel();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.successSubtle,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 16, color: context.success),
          const SizedBox(width: 6),
          Text(
            'Tercatat',
            style: TextStyle(
              color: context.success,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (status) {
      AttendanceStatus.notClockedIn => (
        'Belum clock in',
        context.surfaceMuted,
        context.inkSecondary,
      ),
      AttendanceStatus.working => (
        'Sedang bekerja',
        context.accentSubtle,
        context.accentText,
      ),
      AttendanceStatus.finished => (
        'Selesai',
        context.successSubtle,
        context.success,
      ),
    };

    return Semantics(
      label: 'Status absensi: $label',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: foreground,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationLine extends StatelessWidget {
  const _DurationLine({required this.record});

  final AttendanceRecord record;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;

    // Rata tengah, selaras dengan jam di atas.
    Widget line(String text) => Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 16,
            color: context.inkSecondary,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text, style: style, textAlign: TextAlign.center),
          ),
        ],
      ),
    );

    return switch (record.status) {
      AttendanceStatus.notClockedIn => line(
        'Durasi kerja akan dihitung setelah Anda clock in.',
      ),
      // Durasi berjalan diperbarui tiap detik hanya pada baris ini.
      AttendanceStatus.working => NowBuilder(
        builder: (context, now) => line(
          'Durasi kerja sejauh ini: '
          '${DateFormatId.duration(record.workedDuration(now)!)}',
        ),
      ),
      AttendanceStatus.finished => line(
        'Total durasi kerja hari ini: '
        '${DateFormatId.duration(record.workedDuration(DateTime.now())!)}',
      ),
    };
  }
}

/// Lokasi tempat absen tercatat, atau petunjuk bahwa lokasi akan dicek.
class _LocationLine extends StatelessWidget {
  const _LocationLine({required this.record, required this.locating});

  final AttendanceRecord record;
  final bool locating;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    final inPlace = record.clockInLocation;
    final outPlace = record.clockOutLocation;

    final String text;
    final IconData icon;
    if (locating) {
      text = 'Memeriksa lokasi Anda…';
      icon = Icons.my_location;
    } else if (inPlace != null) {
      icon = Icons.place_outlined;
      text = outPlace == null
          ? 'Clock in di $inPlace'
          : outPlace == inPlace
          ? 'Clock in & clock out di $inPlace'
          : 'Clock in di $inPlace · Clock out di $outPlace';
    } else {
      icon = Icons.place_outlined;
      text =
          'Di dalam area absen untuk clock langsung; di luar area tetap '
          'bisa lewat pengajuan. Pastikan lokasi (GPS) aktif.';
    }

    return Semantics(
      liveRegion: locating,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: locating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, size: 16, color: context.inkSecondary),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(text, style: style, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}
