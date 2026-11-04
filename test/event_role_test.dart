import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_app/data/event_repository.dart';

void main() {
  test('bagian event bawaan lengkap dan unik', () {
    expect(
      CrewRole.defaults.map((r) => r.code).toList(),
      ['crew', 'pic', 'pm', 'sla', 'slb', 'slc', 'design'],
    );
    expect(CrewRole.defaults.map((r) => r.code).toSet().length,
        CrewRole.defaults.length);
  });

  test('PIC wajib keterangan, bagian lain tidak', () {
    expect(CrewRole.pic.requiresNote, isTrue);
    expect(CrewRole.crew.requiresNote, isFalse);
  });

  test('bagian dari server sama dengan bawaan bila kodenya sama', () {
    const parsed = CrewRole(
      id: 'uuid-baru',
      code: 'pic',
      label: 'PIC',
      noteHint: 'keterangan',
      requiresNote: true,
    );
    expect(parsed, CrewRole.pic);
  });
}
