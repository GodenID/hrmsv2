import 'dart:typed_data';

/// GIF animasi diawali "GIF87a" atau "GIF89a".
bool isGifBytes(Uint8List bytes) =>
    bytes.length >= 6 &&
    bytes[0] == 0x47 &&
    bytes[1] == 0x49 &&
    bytes[2] == 0x46;
