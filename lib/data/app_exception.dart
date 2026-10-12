/// Galat yang pesannya aman & layak ditampilkan langsung ke pengguna.
class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Aksi ditolak karena role pengguna tidak memiliki hak akses.
class PermissionDeniedException extends AppException {
  const PermissionDeniedException([
    super.message = 'Anda tidak memiliki akses untuk melakukan aksi ini.',
  ]);
}
