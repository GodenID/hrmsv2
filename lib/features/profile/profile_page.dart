import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/app_scope.dart';
import '../../core/platform_services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/theme_colors.dart';
import '../../core/utils/date_format_id.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/panel.dart';
import '../../core/widgets/role_badge.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/app_exception.dart';
import '../../data/profile_repository.dart';
import '../shell/shell_routes.dart';
import 'photo_editor.dart';
import 'profile_photo.dart';

/// Profil karyawan + foto profil + ubah data kontak sendiri + ganti
/// password. Data identitas & kepegawaian hanya bisa dilihat (dikelola HR).
/// Dibuka dari menu akun (avatar kanan atas); Keluar juga ada di sana.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  /// Batas file asli sebelum diedit (foto kamera HP umumnya 2–12 MB).
  static const int _maxSourceBytes = 20 * 1024 * 1024;

  bool _initialized = false;
  EmployeeProfile? _profile;
  bool _isLoading = false;
  String? _error;
  bool _photoBusy = false;
  bool _signingOutOthers = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final p = await AppScope.of(context).profile
          .fetchProfile(SessionScope.userOf(context));
      if (mounted) setState(() => _profile = p);
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Profil gagal dimuat. Coba lagi.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changePassword() async {
    final changed = await Navigator.of(context)
        .pushNamed<bool>(ShellRoutes.changePassword);
    if (changed == true && mounted) {
      showAppSnackBar(context, 'Password berhasil diganti.');
    }
  }

  /// Mencabut semua sesi milik pengguna kecuali di HP ini.
  Future<void> _logoutOthers() async {
    if (_signingOutOthers) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari perangkat lain?'),
        content: const Text(
          'Sesi di HP ini tetap masuk. Semua perangkat lain harus masuk '
          'ulang dengan username dan password.',
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
            ),
            child: const Text('Keluarkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final user = SessionScope.userOf(context);
    setState(() => _signingOutOthers = true);
    try {
      final deps = AppScope.of(context);
      final token = await deps.sessionStorage.readToken();
      if (token == null) {
        throw const AppException(
          'Sesi tidak ditemukan. Masuk ulang lalu coba lagi.',
        );
      }
      await deps.auth.logoutOthers(user, currentToken: token);
      if (mounted) {
        showAppSnackBar(context, 'Perangkat lain sudah dikeluarkan.');
      }
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Gagal memproses. Coba lagi.');
    } finally {
      if (mounted) setState(() => _signingOutOthers = false);
    }
  }

  Future<void> _editContact() async {
    final profile = _profile;
    if (profile == null) return;
    final updated = await Navigator.of(
      context,
    ).pushNamed<EmployeeProfile>(ShellRoutes.editContact, arguments: profile);
    if (updated != null && mounted) {
      setState(() => _profile = updated);
      showAppSnackBar(context, 'Data kontak diperbarui.');
    }
  }

  Future<void> _changePhoto() async {
    final photos = ProfilePhotoScope.read(context);
    if (photos == null || _photoBusy) return;

    final PickedImage? picked;
    try {
      picked = await AppScope.of(context).platform.pickImage();
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, 'Pemilih foto tidak dapat dibuka.');
      }
      return;
    }
    if (picked == null || !mounted) return;
    if (picked.bytes.length > _maxSourceBytes) {
      showAppSnackBar(context, 'Ukuran file foto maksimal 20 MB.');
      return;
    }

    final Uint8List? edited;
    try {
      edited = await showPhotoEditor(context, picked.bytes);
    } on PhotoDecodeException {
      if (mounted) {
        showAppSnackBar(
          context,
          'Foto tidak dapat dibuka. Pilih file JPG, PNG, atau WebP.',
        );
      }
      return;
    }
    if (edited == null || !mounted) return;

    setState(() => _photoBusy = true);
    try {
      await photos.upload(edited);
      if (mounted) showAppSnackBar(context, 'Foto profil diperbarui.');
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Foto gagal disimpan. Coba lagi.');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _removePhoto() async {
    final photos = ProfilePhotoScope.read(context);
    if (photos == null || _photoBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus foto profil?'),
        content: const Text(
          'Avatar Anda akan kembali menampilkan inisial nama.',
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
              backgroundColor: context.danger,
              foregroundColor: context.isDark ? context.surface : Colors.white,
              minimumSize: const Size(96, 44),
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _photoBusy = true);
    try {
      await photos.remove();
      if (mounted) showAppSnackBar(context, 'Foto profil dihapus.');
    } on AppException catch (e) {
      if (mounted) showAppSnackBar(context, e.message);
    } catch (_) {
      if (mounted) showAppSnackBar(context, 'Foto gagal dihapus. Coba lagi.');
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = ProfilePhotoScope.watch(context)?.photo;
    return PageScaffold(
      title: 'Profil',
      maxWidth: 720,
      onRefresh: _load,
      busy: _photoBusy,
      child: AsyncBody(
        isLoading: _isLoading,
        error: _error,
        hasData: _profile != null,
        onRetry: _load,
        loadingLabel: 'Memuat profil…',
        builder: (context) => _ProfileBody(
          profile: _profile!,
          photo: photo,
          photoBusy: _photoBusy,
          onChangePhoto: _changePhoto,
          onRemovePhoto: _removePhoto,
          onChangePassword: _changePassword,
          onEditContact: _editContact,
          onLogoutOthers: _logoutOthers,
          signingOutOthers: _signingOutOthers,
        ),
      ),
    );
  }
}

class _ProfileBody extends StatelessWidget {
  const _ProfileBody({
    required this.profile,
    required this.photo,
    required this.photoBusy,
    required this.onChangePhoto,
    required this.onRemovePhoto,
    required this.onChangePassword,
    required this.onEditContact,
    required this.onLogoutOthers,
    required this.signingOutOthers,
  });

  final EmployeeProfile profile;
  final Uint8List? photo;
  final bool photoBusy;
  final VoidCallback onChangePhoto;
  final VoidCallback onRemovePhoto;
  final VoidCallback onChangePassword;
  final VoidCallback onEditContact;
  final VoidCallback onLogoutOthers;
  final bool signingOutOthers;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final p = profile;
    final ec = p.emergencyContact;
    final missingContact = p.address == null || ec == null;
    final hasPhoto = photo != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EditableAvatar(
                name: p.fullName,
                photo: photo,
                busy: photoBusy,
                onTap: onChangePhoto,
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.fullName,
                      style: textTheme.titleMedium?.copyWith(fontSize: 20),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${p.position} · ${p.division.label}',
                      style: textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        RoleBadge(role: p.role),
                        Text(
                          p.employeeId,
                          style: textTheme.bodySmall?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Geser kiri agar teks tombol sejajar dengan teks di atas.
                    Transform.translate(
                      offset: const Offset(-8, 0),
                      child: Wrap(
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: photoBusy ? null : onChangePhoto,
                            icon: const Icon(
                              Icons.photo_camera_outlined,
                              size: 18,
                            ),
                            label: Text(
                              hasPhoto ? 'Ganti foto' : 'Unggah foto',
                            ),
                          ),
                          if (hasPhoto)
                            TextButton.icon(
                              onPressed: photoBusy ? null : onRemovePhoto,
                              style: TextButton.styleFrom(
                                foregroundColor: context.danger,
                              ),
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Hapus foto'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Panel(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Kepegawaian'),
              InfoRow(label: 'ID karyawan', value: p.employeeId),
              InfoRow(label: 'Jabatan', value: p.position),
              InfoRow(label: 'Divisi', value: p.division.label),
              InfoRow(label: 'Atasan langsung', value: p.managerName ?? '—'),
              InfoRow(
                label: 'Status',
                value: p.employmentStatus.displayLabel(p.contractMonths),
              ),
              InfoRow(
                label: 'Bergabung sejak',
                value: DateFormatId.dayMonthYear(p.joinDate),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Panel(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Identitas'),
              InfoRow(label: 'Username', value: p.username),
              InfoRow(
                label: 'NIK',
                value: p.nikMasked,
                valueStyle: textTheme.bodyMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              _OptionalRow(label: 'Jenis kelamin', value: p.gender?.label),
              _OptionalRow(label: 'Tempat lahir', value: p.birthPlace),
              _OptionalRow(
                label: 'Tanggal lahir',
                value: p.birthDate == null
                    ? null
                    : DateFormatId.dayMonthYear(p.birthDate!),
              ),
              InfoRow(label: 'Email', value: p.email),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Data identitas & kepegawaian dikelola oleh Tim HR. Hubungi HR bila '
          'ada yang perlu diperbarui.',
          style: textTheme.bodySmall?.copyWith(height: 1.5),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (missingContact) ...[
          _CompleteContactNote(onTap: onEditContact),
          const SizedBox(height: AppSpacing.lg),
        ],
        Panel(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel('Kontak', trailing: _EditButton(onEditContact)),
              InfoRow(label: 'Nomor HP', value: p.phone),
              _OptionalRow(label: 'Alamat', value: p.address),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Panel(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionLabel(
                'Kontak darurat',
                trailing: _EditButton(onEditContact),
              ),
              if (ec == null)
                const _OptionalRow(label: 'Kontak darurat', value: null)
              else ...[
                InfoRow(label: 'Nama', value: ec.name),
                InfoRow(label: 'Hubungan', value: ec.relation.label),
                InfoRow(label: 'Nomor HP', value: ec.phone),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Panel(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Password',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gunakan password yang kuat dan tidak dipakai di '
                      'aplikasi lain.',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              OutlinedButton(
                onPressed: onChangePassword,
                child: const Text('Ganti password'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Panel(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sesi perangkat',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tetap masuk di HP ini, keluarkan semua perangkat '
                      'lain.',
                      style: textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              OutlinedButton(
                onPressed: signingOutOthers ? null : onLogoutOthers,
                child: signingOutOthers
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Keluarkan lainnya'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Avatar besar di Profil; diketuk = ganti foto.
class _EditableAvatar extends StatelessWidget {
  const _EditableAvatar({
    required this.name,
    required this.photo,
    required this.busy,
    required this.onTap,
  });

  final String name;
  final Uint8List? photo;
  final bool busy;
  final VoidCallback onTap;

  static const double _size = 76;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: !busy,
      label: photo == null ? 'Unggah foto profil' : 'Ganti foto profil',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Ganti foto',
        child: InkWell(
          onTap: busy ? null : onTap,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: _size,
            child: Stack(
              children: [
                UserAvatar(name: name, photo: photo, size: _size),
                if (busy)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                      child: const Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.photo_camera,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Baris info yang bisa kosong: tampil "Belum diisi" dengan warna redup.
class _OptionalRow extends StatelessWidget {
  const _OptionalRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return InfoRow(
      label: label,
      value: v ?? 'Belum diisi',
      valueStyle: v == null
          ? Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: context.inkTertiary)
          : null,
    );
  }
}

class _EditButton extends StatelessWidget {
  const _EditButton(this.onPressed);

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      icon: const Icon(Icons.edit_outlined, size: 16),
      label: const Text('Ubah'),
    );
  }
}

/// Ajakan melengkapi alamat & kontak darurat (akun lama buatan Manager).
class _CompleteContactNote extends StatelessWidget {
  const _CompleteContactNote({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: context.accentSubtle,
        borderRadius: BorderRadius.circular(AppRadius.panel),
        border: Border.all(color: const Color(0xFFC6DDDA)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.health_and_safety_outlined,
            size: 20,
            color: context.accentText,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Lengkapi alamat dan kontak darurat agar Tim HR bisa '
              'menghubungi keluarga Anda saat darurat.',
              style: textTheme.bodySmall?.copyWith(
                color: context.ink,
                height: 1.45,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          TextButton(onPressed: onTap, child: const Text('Lengkapi')),
        ],
      ),
    );
  }
}
