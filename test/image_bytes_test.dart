import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:hrms_app/core/utils/image_bytes.dart';

void main() {
  test('kenali GIF animasi', () {
    expect(isGifBytes(Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])), isTrue);
    expect(isGifBytes(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])), isFalse);
    expect(isGifBytes(Uint8List.fromList([0x47, 0x49])), isFalse);
  });
}
