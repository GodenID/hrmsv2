import 'package:flutter/widgets.dart';

/// Menu utama di dalam shell. Profil tidak termasuk: dibuka dari menu akun
/// (avatar di kanan atas).
enum ShellTab {
  dashboard,
  attendance,
  leave,
  events,
  approvals,
  employees,
  locations,
  reports,
  warnings,
  broadcast,
  masterData,
}

/// Aksi navigasi tingkat shell yang bisa dipanggil dari halaman mana pun
/// (mis. notifikasi membuka menu Cuti).
class ShellController extends InheritedWidget {
  const ShellController({
    super.key,
    required this.openTab,
    required this.openNotifications,
    required this.openProfile,
    required this.openLink,
    required super.child,
  });

  /// Pindah ke menu [tab] dan kembali ke halaman utamanya. Diabaikan bila
  /// menu tersebut tidak tersedia untuk role pengguna.
  final ValueChanged<ShellTab> openTab;

  /// Membuka halaman notifikasi di menu yang sedang aktif.
  final VoidCallback openNotifications;

  /// Membuka halaman Profil di menu yang sedang aktif.
  final VoidCallback openProfile;

  /// Membuka tujuan notifikasi: halaman detail bila refType/refId-nya ketemu,
  /// selain itu menu tujuan sesuai jenisnya.
  final Future<void> Function(String kind, String? refType, String? refId)
  openLink;

  static ShellController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellController>();

  @override
  bool updateShouldNotify(ShellController oldWidget) => false;
}
