import 'package:prasasti_server/leave_handlers.dart';
import 'package:test/test.dart';

void main() {
  test('normalizedDivision mengenali berbagai penulisan Produksi Mutiari', () {
    expect(normalizedDivision('produksiMutiari'), 'produksimutiari');
    expect(normalizedDivision(' Produksi Mutiari '), 'produksimutiari');
    expect(normalizedDivision('hrIt'), 'hrit');
  });
}
