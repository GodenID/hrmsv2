import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/push_notifications.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/currency_format.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/form_widgets.dart';
import '../../core/widgets/initials_avatar.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../data/app_exception.dart';
import '../../data/event_repository.dart';
import '../shell/shell_routes.dart';
import 'event_presentation.dart';

/// Detail event + tim (siapa saja & bagian apa).
class EventDetailPage extends StatefulWidget {
  const EventDetailPage({super.key, required this.initial});

  /// Isi dari daftar, ditampilkan langsung sambil memuat data terbaru.
  final EventItem initial;

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  late EventRepository _repo;
  bool _initialized = false;

  late EventItem _event = widget.initial;
  EventThresholds? _thresholds;
  String? _error;
  bool _isLeaving = false;
  bool _isDeleting = false;

  bool get _busy => _isLeaving || _isDeleting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).events;
    _repo.changes.addListener(_onChanged);
    AppRefresh.events.addListener(_onChanged);
    _load();
  }

  @override
  void dispose() {
    _repo.changes.removeListener(_onChanged);
    AppRefresh.events.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    // Saat menghapus, event memang akan hilang — jangan tampilkan galat.
    if (mounted && !_isDeleting) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait([
        _repo.fetchEvent(SessionScope.userOf(context), id: widget.initial.id),
        _repo.fetchThresholds(),
      ]);
      if (!mounted) return;
      setState(() {
        _event = results[0] as EventItem;
        _thresholds = results[1] as EventThresholds;
      });
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Data event gagal dimuat. Coba lagi.');
      }
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context)
        .pushNamed<bool>(ShellRoutes.eventForm, arguments: _event);
    if (saved == true && mounted) showAppSnackBar(context, 'Event diperbarui.');
  }

  Future<void> _openCrewForm() async {
    final wasMember = _event.memberFor(SessionScope.userOf(context).username);
    final saved = await Navigator.of(context)
        .pushNamed<bool>(ShellRoutes.eventCrewForm, arguments: _event);
    if (saved == true && mounted) {
      showAppSnackBar(
        context,
        wasMember == null
            ? 'Anda terdaftar sebagai partisipan.'
            : 'Bagian Anda diperbarui.',
      );
    }
  }

  Future<void> _delete() async {
    final crewCount = _event.crew.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus event?'),
        content: Text(
          '"${_event.name}" akan dihapus permanen beserta daftar partisipasinya.'
          '${crewCount == 0 ? '' : ' $crewCount partisipan akan menerima '
                    'notifikasi bahwa event dibatalkan.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: context.inkSecondary,
            ),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 44),
              backgroundColor: context.danger,
              foregroundColor: context.isDark ? context.surface : Colors.white,
            ),
            child: const Text('Hapus event'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await _repo.deleteEvent(SessionScope.userOf(context), id: _event.id);
      if (mounted) Navigator.of(context).pop(true);
    } on AppException catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        showAppSnackBar(context, e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isDeleting = false);
        showAppSnackBar(context, 'Gagal menghapus event. Coba lagi.');
      }
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Batal ikut event?'),
        content: Text(
          'Nama Anda akan dihapus dari tim "${_event.name}". Anda bisa '
          'mendaftar lagi nanti.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: context.inkSecondary,
            ),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 44),
              backgroundColor: context.danger,
              foregroundColor: context.isDark ? context.surface : Colors.white,
            ),
            child: const Text('Batal ikut'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isLeaving = true);
    try {
      final updated = await _repo.leaveEvent(
        SessionScope.userOf(context),
        id: _event.id,
      );
      if (!mounted) return;
      setState(() => _event = updated);
      showAppSnackBar(
        context,
        'Anda sudah keluar dari daftar partisipan.',
      );
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Gagal memproses. Coba lagi.');
    } finally {
      if (mounted) setState(() => _isLeaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = SessionScope.userOf(context);
    final isWide = AppSpacing.isSidebarLayout(MediaQuery.sizeOf(context).width);
    final textTheme = Theme.of(context).textTheme;
    final e = _event;
    final me = e.memberFor(user.username);

    return PopScope(
      canPop: !_isDeleting,
      child: PageScaffold(
        title: 'Detail event',
        maxWidth: 720,
        busy: _busy,
        onRefresh: _load,
        actions: [
          if (user.role.canManageEvents) ...[
            isWide
                ? OutlinedButton.icon(
                    onPressed: _busy ? null : _delete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.danger,
                      side: const BorderSide(color: AppColors.dangerBorder),
                    ),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Hapus'),
                  )
                : IconButton(
                    tooltip: 'Hapus event',
                    onPressed: _busy ? null : _delete,
                    color: context.danger,
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
            if (isWide) const SizedBox(width: AppSpacing.sm),
            isWide
                ? OutlinedButton.icon(
                    onPressed: _busy ? null : _edit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit event'),
                  )
                : IconButton(
                    tooltip: 'Edit event',
                    onPressed: _busy ? null : _edit,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
          ],
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              FormErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      e.name,
                      style: textTheme.headlineSmall?.copyWith(height: 1.25),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: EventSizeChip(size: e.size, long: true),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
              child: Column(
                children: [
                  InfoRow(
                    label: 'Tanggal',
                    value: DateFormatId.dateRange(e.startDate, e.endDate),
                  ),
                  InfoRow(label: 'Perusahaan', value: e.company),
                  InfoRow(label: 'Kategori event', value: e.category.name),
                  InfoRow(label: 'Lokasi acara', value: e.location),
                  if (e.poValue != null)
                    InfoRow(
                      label: 'Nilai PO',
                      value: Rupiah.format(e.poValue!),
                      valueStyle: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  InfoRow(
                    label: 'Ukuran event',
                    value: _thresholds == null
                        ? e.size.label
                        : '${e.size == EventSize.overLimit ? 'Melebihi batas event besar' : 'Event ${e.size.label.toLowerCase()}'}'
                              ' (PO ${_thresholds!.rangeLabel(e.size)})',
                  ),
                  InfoRow(label: 'Dibuat oleh', value: e.createdBy),
                ],
              ),
            ),
            const SizedBox(height: 28),
            SectionLabel('Partisipan  ·  ${e.crew.length} orang'),
            _MyMembership(
              member: me,
              busy: _busy,
              onJoin: _openCrewForm,
              onEdit: _openCrewForm,
              onLeave: _leave,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (e.crew.isEmpty)
              const Panel(
                padding: EdgeInsets.zero,
                child: EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'Belum ada yang terdaftar',
                  message: 'Jadilah partisipan pertama event ini.',
                ),
              )
            else
              _CrewList(crew: e.crew, myUsername: user.username),
          ],
        ),
      ),
    );
  }
}

class _MyMembership extends StatelessWidget {
  const _MyMembership({
    required this.member,
    required this.busy,
    required this.onJoin,
    required this.onEdit,
    required this.onLeave,
  });

  final CrewMember? member;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onEdit;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final m = member;

    if (m == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: busy ? null : onJoin,
          icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('Jadi partisipan'),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: context.accentSubtle,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: const Color(0xFFC6DDDA)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.how_to_reg,
                size: 20,
                color: context.accentText,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    text: 'Anda terdaftar sebagai ',
                    children: [
                      TextSpan(
                        text: m.role.label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (m.note.isNotEmpty) TextSpan(text: ' · ${m.note}'),
                    ],
                  ),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.accentText,
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: busy ? null : onEdit,
                child: const Text('Ubah'),
              ),
              TextButton(
                onPressed: busy ? null : onLeave,
                style: TextButton.styleFrom(
                  foregroundColor: context.danger,
                ),
                child: const Text('Batal ikut'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Daftar tim dikelompokkan per bagian.
class _CrewList extends StatelessWidget {
  const _CrewList({required this.crew, required this.myUsername});

  final List<CrewMember> crew;
  final String myUsername;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final groups = [
      for (final role in CrewRole.values)
        (
          role,
          [
            for (final m in crew)
              if (m.role == role) m,
          ],
        ),
    ].where((g) => g.$2.isNotEmpty).toList();

    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var g = 0; g < groups.length; g++) ...[
            if (g > 0) const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Semantics(
                header: true,
                label: '${groups[g].$1.label}, ${groups[g].$2.length} orang',
                excludeSemantics: true,
                child: Text(
                  '${groups[g].$1.label.toUpperCase()}  ·  ${groups[g].$2.length}',
                  style: textTheme.labelSmall,
                ),
              ),
            ),
            for (final m in groups[g].$2)
              MergeSemantics(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Row(
                    children: [
                      InitialsAvatar(name: m.fullName, size: 32),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                text: m.fullName,
                                children: [
                                  if (m.username == myUsername)
                                    TextSpan(
                                      text: '  (Anda)',
                                      style: TextStyle(
                                        color: context.accentText,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              m.note.isEmpty
                                  ? m.role.label
                                  : '${m.role.label} · ${m.note}',
                              style: textTheme.bodySmall?.copyWith(
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }
}
