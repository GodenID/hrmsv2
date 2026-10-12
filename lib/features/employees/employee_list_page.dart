import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/widgets/initials_avatar.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/role_badge.dart';
import '../../core/widgets/segment_toggle.dart';
import '../../data/auth_repository.dart';
import '../../data/employee_repository.dart';
import '../shell/shell_routes.dart';
import 'widgets/registration_toggle_panel.dart';

/// Daftar karyawan (semua role dapat melihat) + pencarian.
/// Tambah / ubah hanya Super Admin.
class EmployeeListPage extends StatefulWidget {
  const EmployeeListPage({super.key});

  @override
  State<EmployeeListPage> createState() => _EmployeeListPageState();
}

class _EmployeeListPageState extends State<EmployeeListPage> {
  late EmployeeRepository _repo;
  bool _initialized = false;
  final _searchController = TextEditingController();

  List<EmployeeAccount>? _employees;
  bool _isLoading = false;
  String? _error;
  bool _showInactive = false;
  Division? _divisionFilter;
  UserRole? _roleFilter;

  /// Hanya tampilkan staff aktif yang belum punya atasan langsung
  /// (khas akun hasil daftar mandiri yang belum dilengkapi Super Admin).
  bool _noManagerOnly = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).employees;
    _repo.changes.addListener(_onChanged);
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _repo.changes.removeListener(_onChanged);
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
      final list = await _repo.fetchEmployees(SessionScope.userOf(context));
      if (mounted) setState(() => _employees = list);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Data karyawan gagal dimuat. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _create() async {
    final saved = await Navigator.of(context)
        .pushNamed<bool>(ShellRoutes.employeeForm);
    if (saved == true && mounted) {
      showAppSnackBar(context, 'Akun karyawan dibuat.');
    }
  }

  void _open(EmployeeAccount e) {
    Navigator.of(context).pushNamed(ShellRoutes.employeeDetail, arguments: e);
  }

  bool _matches(EmployeeAccount e, String q) {
    if (q.isNotEmpty &&
        ![
          e.fullName,
          e.username,
          e.employeeId,
          e.division.label,
          e.position,
        ].any((v) => v.toLowerCase().contains(q))) {
      return false;
    }
    if (_divisionFilter != null && e.division != _divisionFilter) {
      return false;
    }
    if (_roleFilter != null && e.role != _roleFilter) return false;
    if (_noManagerOnly && !isMissingManager(e)) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isWide = AppSpacing.isSidebarLayout(MediaQuery.sizeOf(context).width);
    final canAdd =
        SessionScope.userOf(context).role == UserRole.superadmin;

    return PageScaffold(
      title: 'Karyawan',
      onRefresh: _load,
      actions: [
        if (canAdd)
          if (isWide)
            FilledButton.icon(
              onPressed: _create,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Tambah karyawan'),
            )
          else
            TextButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Tambah'),
            ),
      ],
      child: AsyncBody(
        isLoading: _isLoading,
        error: _error,
        hasData: _employees != null,
        onRetry: _load,
        loadingLabel: 'Memuat karyawan…',
        builder: (context) => _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final all = _employees!;
    final active = all.where((e) => e.active).toList();
    final inactive = all.where((e) => !e.active).toList();
    final missingCount = active.where(isMissingManager).length;
    final q = _searchController.text.trim().toLowerCase();
    final isSuper =
        SessionScope.userOf(context).role == UserRole.superadmin;
    final shown = (_showInactive ? inactive : active)
        .where((e) => _matches(e, q))
        .toList();
    final filtering = q.isNotEmpty || _noManagerOnly;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (SessionScope.userOf(context).role.canManageRegistration) ...[
          const RegistrationTogglePanel(),
          const SizedBox(height: AppSpacing.lg),
        ],
        TextField(
          controller: _searchController,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Cari nama, username, ID, atau divisi',
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
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<Division?>(
                initialValue: _divisionFilter,
                items: [
                  const DropdownMenuItem<Division?>(
                    value: null,
                    child: Text('Semua divisi'),
                  ),
                  for (final d in Division.values)
                    DropdownMenuItem<Division?>(
                      value: d,
                      child: Text(d.label),
                    ),
                ],
                onChanged: (d) => setState(() => _divisionFilter = d),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.apartment_outlined, size: 20),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: DropdownButtonFormField<UserRole?>(
                initialValue: _roleFilter,
                items: [
                  const DropdownMenuItem<UserRole?>(
                    value: null,
                    child: Text('Semua role'),
                  ),
                  for (final r in UserRole.values)
                    if (isSuper || r != UserRole.superadmin)
                      DropdownMenuItem<UserRole?>(
                        value: r,
                        child: Text(r.label),
                      ),
                ],
                onChanged: (r) => setState(() => _roleFilter = r),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.badge_outlined, size: 20),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SegmentToggle(
          options: [
            'Aktif (${active.length})',
            'Nonaktif (${inactive.length})',
          ],
          selectedIndex: _showInactive ? 1 : 0,
          onSelect: (i) => setState(() => _showInactive = i == 1),
        ),
        if (missingCount > 0 && !_showInactive) ...[
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              label: Text('Belum ada atasan ($missingCount)'),
              avatar: const Icon(
                Icons.supervisor_account_outlined,
                size: 18,
              ),
              selected: _noManagerOnly,
              onSelected: (v) => setState(() => _noManagerOnly = v),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (shown.isEmpty)
          Panel(
            padding: EdgeInsets.zero,
            child: EmptyState(
              icon: Icons.people_outline,
              title: filtering
                  ? 'Tidak ada yang cocok'
                  : (_showInactive
                        ? 'Tidak ada akun nonaktif'
                        : 'Belum ada karyawan'),
              message: filtering
                  ? 'Coba kata kunci lain atau matikan filter.'
                  : (_showInactive
                        ? 'Akun yang dinonaktifkan akan muncul di sini.'
                        : (isSuper
                              ? 'Tambahkan karyawan lewat tombol Tambah.'
                              : 'Belum ada data karyawan.')),
            ),
          )
        else
          Panel(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0) const Divider(),
                  _EmployeeRow(
                    employee: shown[i],
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

/// Staff aktif tanpa atasan langsung = belum dilengkapi (khas akun hasil
/// daftar mandiri). Super Admin mengisinya lewat Ubah data karyawan.
bool isMissingManager(EmployeeAccount e) =>
    e.active && e.role == UserRole.staff && e.managerUsername == null;

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({required this.employee, required this.onTap});

  final EmployeeAccount employee;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final e = employee;

    return Semantics(
      button: true,
      label:
          '${e.fullName}, ${e.position}, ${e.division.label}. Role ${e.role.label}.'
          '${e.active ? '' : ' Nonaktif.'}'
          '${isMissingManager(e) ? ' Belum ada atasan.' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        hoverColor: context.surfaceMuted,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              InitialsAvatar(name: e.fullName, size: 36, muted: !e.active),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.fullName,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: e.active
                            ? context.ink
                            : context.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${e.position} · ${e.division.label}',
                      style: textTheme.bodySmall?.copyWith(fontSize: 12.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@${e.username}  ·  ${e.employeeId}',
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    if (isMissingManager(e)) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.warning.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Belum ada atasan',
                          style: textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: context.warning,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              RoleBadge(role: e.role),
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
