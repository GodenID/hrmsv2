import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../core/app_scope.dart';
import '../../core/widgets/user_avatar.dart';
import '../../data/auth_repository.dart';
import '../../data/profile_repository.dart';

/// Foto profil pengguna yang sedang login. Satu sumber untuk semua avatar
/// miliknya (header, menu akun, halaman Profil), jadi foto baru langsung
/// tampil di semua tempat tanpa memuat ulang.
class ProfilePhotoController extends ChangeNotifier {
  ProfilePhotoController({required this.repository, required this.user});

  final ProfileRepository repository;
  final AuthUser user;
  bool _disposed = false;

  Uint8List? _photo;
  Uint8List? get photo => _photo;

  void _set(Uint8List? photo) {
    if (_disposed) return;
    _photo = photo;
    notifyListeners();
  }

  /// Memuat foto dari server. Galat diabaikan: avatar inisial tetap tampil.
  Future<void> load() async {
    try {
      _set(await repository.fetchPhoto(user));
    } catch (_) {}
  }

  /// Melempar [AppException] bila ditolak server.
  Future<void> upload(Uint8List bytes) async {
    await repository.updatePhoto(user, bytes: bytes);
    _set(bytes);
  }

  Future<void> remove() async {
    await repository.removePhoto(user);
    _set(null);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class ProfilePhotoScope extends InheritedNotifier<ProfilePhotoController> {
  const ProfilePhotoScope({
    super.key,
    required ProfilePhotoController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Membangun ulang pemanggil saat foto berubah.
  static ProfilePhotoController? watch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProfilePhotoScope>()?.notifier;

  /// Tanpa mendaftarkan dependensi (aman dipanggil dari callback).
  static ProfilePhotoController? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ProfilePhotoScope>()?.notifier;
}

/// Avatar pengguna yang sedang login (foto profil atau inisial).
class CurrentUserAvatar extends StatelessWidget {
  const CurrentUserAvatar({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return UserAvatar(
      name: SessionScope.userOf(context).fullName,
      photo: ProfilePhotoScope.watch(context)?.photo,
      size: size,
    );
  }
}
