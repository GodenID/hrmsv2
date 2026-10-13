import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/push_notifications.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/segment_toggle.dart';
import '../../data/auth_repository.dart';
import '../../data/warning_repository.dart';
import '../shell/shell_routes.dart';

/// Daftar surat peringatan.
/// - Staff: hanya miliknya sendiri.
/// - Manager: tim yang boleh dikelolanya (baca saja).
/// - Super Admin: semua + tombol terbitkan.
class WarningsPage extends StatefulWidget {
  const WarningsPage({super.key});

  @override
  State<WarningsPage> createState() => _WarningsPageState();
}

class _WarningsPageState extends State<WarningsPage> {
  late WarningRepository _repo;
  bool _initialized = false;

  List<WarningLetterDetail>? _items;
  bool _isLoading = false;
  String? _error;
  final _searchController = TextEditingController();
  int _segment = 0; // 0 aktif, 1 kedaluwarsa, 2 semua

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).warnings;
    _repo.changes.addListener(_onChanged);
    AppRefresh.warnings.addListener(_onChanged);
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _repo.changes.removeListener(_onChanged);
    AppRefresh.warnings.removeListener(_onChanged);
    _searchController.dispose();
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
      final user = SessionScope.userOf(context);
      final items = user.role == UserRole.staff
          ? await _repo.fetchMyLetters(user)
          : await _repo.fetchLetters(user);
      if (mounted) setState(() => _items = items);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Daftar peringatan gagal dimuat. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _open(WarningLetterDetail item) async {
    final changed = await Navigator.of(
      context,
    ).pushNamed<bool>(ShellRoutes.warningDetail, arguments: item);
    if (changed == true && mounted) _load();
  }

  Future<void> _create() async {
    final created = await Navigator.of(
      context,
    ).pushNamed<bool>(ShellRoutes.warningForm);
    if (created == true && mounted) {
      _load();
      showAppSnackBar(context, 'Surat peringatan diterbitkan.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = SessionScope.userOf(context);
    final isSuperAdmin = user.role == UserRole.superadmin;
    final now = DateTime.now();
    final items = _items;
    final q = _searchController.text.trim().toLowerCase();

    var active = 0;
    var expired = 0;
    final shown = <WarningLetterDetail>[];
    if (items != null) {
      for (final d in items) {
        final isActive = d.letter.isActive(now);
        if (isActive) {
          active++;
        } else {
          expired++;
        }
        if (_segment == 0 && !isActive) continue;
        if (_segment == 1 && isActive) continue;
        if (q.isNotEmpty &&
            !'${d.employee.fullName} ${d.letter.violationName} '
                    '${d.letter.levelLabel}'
                .toLowerCase()
                .contains(q)) {
          continue;
        }
        shown.add(d);
      }
    }
    final filtering = q.isNotEmpty || _segment != 0;

    return PageScaffold(
      title: 'Peringatan',
      maxWidth: 720,
      onRefresh: _load,
      actions: [
        if (isSuperAdmin)
          TextButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.gavel_outlined, size: 18),
            label: const Text('Buat SP'),
          ),
      ],
      child: AsyncBody(
        isLoading: _isLoading,
        error: _error,
        hasData: items != null,
        onRetry: _load,
        loadingLabel: 'Memuat peringatan…',
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cari nama atau pelanggaran',
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
                'Aktif ($active)',
                'Kedaluwarsa ($expired)',
                'Semua (${items?.length ?? 0})',
              ],
              selectedIndex: _segment,
              onSelect: (i) => setState(() => _segment = i),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (shown.isEmpty)
              Panel(
                padding: EdgeInsets.zero,
                child: EmptyState(
                  icon: Icons.gavel_outlined,
                  title: filtering
                      ? 'Tidak ada yang cocok'
                      : 'Belum ada surat peringatan',
                  message: filtering
                      ? 'Coba kata kunci lain atau tampilkan semua.'
                      : isSuperAdmin
                      ? 'Terbitkan SP pertama dari tombol "Buat SP".'
                      : 'Bagus — tidak ada SP atas nama Anda.',
                ),
              )
            else
              Panel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < shown.length; i++) ...[
                      if (i > 0) const Divider(),
                      _WarningRow(
                        detail: shown[i],
                        showName: user.role != UserRole.staff,
                        isMine:
                            shown[i].employee.username == user.username,
                        now: now,
                        onTap: () => _open(shown[i]),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _WarningRow extends StatelessWidget {
  const _WarningRow({
    required this.detail,
    required this.showName,
    required this.isMine,
    required this.now,
    required this.onTap,
  });

  final WarningLetterDetail detail;
  final bool showName;
  final bool isMine;
  final DateTime now;
  final VoidCallback onTap;

  Color _levelColor(BuildContext context, int level) => switch (level) {
    1 => context.warning,
    2 => Colors.deepOrange,
    _ => context.danger,
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final letter = detail.letter;
    final isActive = letter.isActive(now);
    final needsSign = isMine && !letter.signed;

    return Semantics(
      button: true,
      label:
          '${letter.levelLabel} untuk ${detail.employee.fullName}, '
          '${letter.violationName}. ${isActive ? 'Aktif' : 'Kedaluwarsa'}'
          '${needsSign ? '. Perlu ditandatangani' : ''}',
      excludeSemantics: true,
      child: Material(
        color: needsSign
            ? context.warning.withValues(alpha: 0.12)
            : context.surface,
        child: InkWell(
          onTap: onTap,
          hoverColor: context.surfaceMuted,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: _levelColor(
                      context,
                      letter.level,
                    ).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    letter.levelLabel,
                    style: textTheme.labelLarge?.copyWith(
                      color: _levelColor(context, letter.level),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showName)
                        Text(
                          detail.employee.fullName,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      Text(
                        letter.violationName,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: showName
                              ? FontWeight.w500
                              : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isActive
                            ? 'Aktif s/d ${DateFormatId.shortDate(letter.expiresAt)}'
                            : 'Kedaluwarsa ${DateFormatId.shortDate(letter.expiresAt)}',
                        style: textTheme.bodySmall?.copyWith(
                          color: context.inkSecondary,
                        ),
                      ),
                      if (needsSign) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Perlu ditandatangani',
                          style: textTheme.bodySmall?.copyWith(
                            color: context.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (detail.letter.appealPending) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Disanggah — menunggu respons',
                          style: textTheme.bodySmall?.copyWith(
                            color: context.danger,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      if (detail.letter.voided) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Dicabut',
                          style: textTheme.bodySmall?.copyWith(
                            color: context.inkSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: context.inkSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
