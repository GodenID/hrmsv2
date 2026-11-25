import 'package:prasasti_server/authz.dart';
import 'package:test/test.dart';

void main() {
  test('BOD setara Manager, ditambah hak laporan', () {
    expect(isManagerLike('bod'), isTrue);
    expect(canViewReports('bod'), isTrue);
    expect(canViewReports('manager'), isFalse);
    expect(canViewReports('superadmin'), isTrue);
  });

  test('BOD hanya mengelola staff', () {
    expect(canManageRole('bod', 'staff'), isTrue);
    expect(canManageRole('bod', 'manager'), isFalse);
    expect(canManageRole('bod', 'bod'), isFalse);
  });
}
