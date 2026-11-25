import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/data/auth_repository.dart';

void main() {
  test('BOD bisa review dan lihat laporan', () {
    expect(UserRole.bod.canReviewRequests, isTrue);
    expect(UserRole.bod.canViewReports, isTrue);
    expect(UserRole.manager.canViewReports, isFalse);
    expect(UserRole.bod.canManageRole(UserRole.staff), isTrue);
    expect(UserRole.bod.canManageRole(UserRole.manager), isFalse);
  });
}
