import 'package:flutter/material.dart';

import '../../../core/app_scope.dart';
import '../../../core/theme/theme_colors.dart';
import '../../../data/notification_repository.dart';
import '../../shell/shell_controller.dart';

/// Tombol lonceng + jumlah notifikasi yang belum dibaca.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  late NotificationRepository _repo;
  bool _initialized = false;
  int _unread = 0;
  int _requestId = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repo = AppScope.of(context).notifications;
    _repo.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _repo.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    // Abaikan jawaban lama bila ada permintaan yang lebih baru.
    final id = ++_requestId;
    try {
      final count = await _repo.unreadCount(SessionScope.userOf(context));
      if (mounted && id == _requestId) setState(() => _unread = count);
    } catch (_) {
      // Lencana bersifat informatif; abaikan galat jaringan sesaat.
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _unread == 0
        ? 'Notifikasi'
        : 'Notifikasi, $_unread belum dibaca';

    return IconButton(
      tooltip: label,
      onPressed: () => ShellController.maybeOf(context)?.openNotifications(),
      icon: Badge(
        isLabelVisible: _unread > 0,
        backgroundColor: context.danger,
        textColor: context.isDark ? context.surface : Colors.white,
        label: Text(_unread > 99 ? '99+' : '$_unread'),
        child: Icon(
          _unread > 0 ? Icons.notifications : Icons.notifications_none,
          size: 22,
        ),
      ),
    );
  }
}
