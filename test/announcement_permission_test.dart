import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/auth_repository.dart';

void main() {
  test('manager dan superadmin dapat mengelola pengumuman', () {
    expect(UserRole.manager.canManageAnnouncements, isTrue);
    expect(UserRole.superadmin.canManageAnnouncements, isTrue);
    expect(UserRole.staff.canManageAnnouncements, isFalse);
  });
}
