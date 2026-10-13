import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/push_notifications.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/currency_format.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/utils/work_calendar.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/segment_toggle.dart';
import '../../data/app_exception.dart';
import '../../data/event_repository.dart';
import '../shell/shell_routes.dart';
import 'event_presentation.dart';

/// Daftar event: mendatang / selesai.
/// Manager & Super Admin: "Buat event" & "Pengaturan event".
class EventListPage extends StatefulWidget {
  const EventListPage({super.key});

  @override
  State<EventListPage> createState() => _EventListPageState();
}

class _EventListPageState extends State<EventListPage> {
  late EventRepository _repo;
  bool _initialized = false;
  final _searchController = TextEditingController();

  List<EventItem>? _events;
  bool _isLoading = false;
  String? _error;
  bool _showPast = false;

  /// Bulan kalender yang tampil (1–akhir bulan). Default bulan ini.
  late DateTime _month;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).events;
    _repo.changes.addListener(_onChanged);
    AppRefresh.events.addListener(_onChanged);
    _searchController.addListener(() => setState(() {}));
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  /// Event bersinggungan dengan bulan tampil (multi-hari tampil di
  /// semua bulan yang dilaluinya).
  bool _inMonth(EventItem e) {
    final first = DateTime(_month.year, _month.month);
    final last = DateTime(_month.year, _month.month + 1, 0);
    final start = WorkCalendar.dateOnly(e.startDate);
    final end = WorkCalendar.dateOnly(e.endDate);
    return !end.isBefore(first) && !start.isAfter(last);
  }

  @override
  void dispose() {
    _repo.changes.removeListener(_onChanged);
    AppRefresh.events.removeListener(_onChanged);
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(EventItem e, String q) {
    if (q.isEmpty) return true;
    return [
      e.name,
      e.company,
      e.location,
      e.category.name,
    ].any((v) => v.toLowerCase().contains(q));
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
      final events = await _repo.fetchEvents(SessionScope.userOf(context));
      if (!mounted) return;
      setState(() {
        _events = events;
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Event gagal dimuat. Coba lagi.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _create() async {
    final saved = await Navigator.of(context)
        .pushNamed<bool>(ShellRoutes.eventForm);
    if (saved == true && mounted) showAppSnackBar(context, 'Event dibuat.');
  }

  Future<void> _openThresholds() async {
    final saved = await Navigator.of(context)
        .pushNamed<bool>(ShellRoutes.eventThresholds);
    if (saved == true && mounted) {
      showAppSnackBar(context, 'Pengaturan event disimpan.');
    }
  }

  Future<void> _open(EventItem event) async {
    final deleted = await Navigator.of(context)
        .pushNamed<bool>(ShellRoutes.eventDetail, arguments: event);
    if (deleted == true && mounted) {
      showAppSnackBar(context, 'Event "${event.name}" dihapus.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = SessionScope.userOf(context);
    final isWide = AppSpacing.isSidebarLayout(MediaQuery.sizeOf(context).width);

    return PageScaffold(
      title: 'Event',
      onRefresh: _load,
      actions: [
        if (user.role.canManageEventThresholds)
          isWide
              ? OutlinedButton.icon(
                  onPressed: _openThresholds,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Pengaturan event'),
                )
              : IconButton(
                  tooltip: 'Pengaturan event',
                  onPressed: _openThresholds,
                  icon: const Icon(Icons.tune, size: 20),
                ),
        if (user.role.canManageEvents)
          isWide
              ? FilledButton.icon(
                  onPressed: _create,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Buat event'),
                )
              : TextButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Buat'),
                ),
      ],
      child: AsyncBody(
        isLoading: _isLoading,
        error: _error,
        hasData: _events != null,
        onRetry: _load,
        loadingLabel: 'Memuat event…',
        builder: (context) => _buildContent(user.username),
      ),
    );
  }

  Widget _buildContent(String username) {
    final textTheme = Theme.of(context).textTheme;
    final today = WorkCalendar.dateOnly(DateTime.now());
    final q = _searchController.text.trim().toLowerCase();
    final inMonth = [for (final e in _events!) if (_inMonth(e)) e];
    // Berlangsung (termasuk multi-hari yang sudah mulai) = mendatang.
    final upcoming = [
      for (final e in inMonth)
        if (!e.endDate.isBefore(today) && _matches(e, q)) e,
    ];
    final past = [
      for (final e in inMonth.reversed)
        if (e.endDate.isBefore(today) && _matches(e, q)) e,
    ];
    final shown = _showPast ? past : upcoming;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormatId.monthYear(_month),
                style: textTheme.titleMedium?.copyWith(fontSize: 18),
              ),
            ),
            if (!_isCurrentMonth) ...[
              TextButton(
                onPressed: () {
                  final now = DateTime.now();
                  setState(() => _month = DateTime(now.year, now.month));
                },
                child: const Text('Bulan ini'),
              ),
              const SizedBox(width: 4),
            ],
            IconButton.outlined(
              tooltip: 'Bulan sebelumnya',
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
              icon: const Icon(Icons.chevron_left, size: 20),
            ),
            const SizedBox(width: 6),
            IconButton.outlined(
              tooltip: 'Bulan berikutnya',
              onPressed: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1),
              ),
              icon: const Icon(Icons.chevron_right, size: 20),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Cari nama, perusahaan, lokasi, atau kategori',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Hapus pencarian',
                    onPressed: _searchController.clear,
                    icon: const Icon(Icons.close, size: 18),
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SegmentToggle(
          options: [
            'Mendatang (${upcoming.length})',
            'Selesai (${past.length})',
          ],
          selectedIndex: _showPast ? 1 : 0,
          onSelect: (i) => setState(() => _showPast = i == 1),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (shown.isEmpty)
          Panel(
            padding: EdgeInsets.zero,
            child: EmptyState(
              icon: Icons.festival_outlined,
              title: q.isNotEmpty
                  ? 'Tidak ada yang cocok'
                  : (!_isCurrentMonth
                        ? 'Tidak ada event bulan ini'
                        : (_showPast
                              ? 'Belum ada event selesai'
                              : 'Belum ada event')),
              message: q.isNotEmpty
                  ? 'Coba kata kunci lain.'
                  : (!_isCurrentMonth
                        ? 'Pindah bulan untuk melihat event lain.'
                        : (_showPast
                              ? 'Event yang sudah lewat akan muncul di sini.'
                              : 'Event mendatang akan muncul di sini.')),
            ),
          )
        else
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const Divider(),
                  _EventRow(
                    event: shown[i],
                    mine: shown[i].memberFor(username),
                    onTap: () => _open(shown[i]),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.event,
    required this.mine,
    required this.onTap,
  });

  final EventItem event;
  final CrewMember? mine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final e = event;
    final today = WorkCalendar.dateOnly(DateTime.now());
    final happening =
        !e.startDate.isAfter(today) && !e.endDate.isBefore(today);
    final myRole = mine == null
        ? null
        : (mine!.note.isEmpty
              ? mine!.role.label
              : '${mine!.role.label} ${mine!.note}');

    return Semantics(
      button: true,
      label:
          '${e.name}, ${e.company}. '
          '${DateFormatId.dateRange(e.startDate, e.endDate)}. '
          '${e.location}. ${e.category.name}. '
          '${e.crew.length} partisipan. Ukuran ${e.size.label}.'
          '${myRole == null ? '' : ' Anda terdaftar sebagai $myRole.'}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        hoverColor: context.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormatId.monthShort(e.startDate).toUpperCase(),
                      style: textTheme.labelSmall?.copyWith(
                        color: happening ? context.accentText : null,
                      ),
                    ),
                    Text(
                      '${e.startDate.day}',
                      style: TextStyle(
                        fontSize: 20,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: happening ? context.accentText : context.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.name,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.business_outlined,
                          size: 14,
                          color: context.inkSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${e.company} · ${e.category.name}',
                            style: textTheme.bodySmall?.copyWith(
                              fontSize: 12.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.place_outlined,
                          size: 14,
                          color: context.inkSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            e.isMultiDay
                                ? '${e.location} · ${DateFormatId.dateRange(e.startDate, e.endDate)}'
                                : e.location,
                            style: textTheme.bodySmall?.copyWith(
                              fontSize: 12.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        text: '${e.crew.length} partisipan',
                        children: [
                          if (e.poValue != null)
                            TextSpan(
                              text: '  ·  PO ${Rupiah.format(e.poValue!)}',
                            ),
                          if (myRole != null)
                            TextSpan(
                              text: '  ·  Anda: $myRole',
                              style: TextStyle(
                                color: context.accentText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 12.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: EventSizeChip(size: e.size),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: context.inkTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
