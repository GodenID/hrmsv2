import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'initials_avatar.dart';

/// Avatar bulat: foto profil bila ada, selain itu inisial nama.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.photo, this.size = 34});

  final String name;

  /// Isi file foto (PNG / JPEG). null = tampilkan inisial.
  final Uint8List? photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bytes = photo;
    if (bytes == null) return InitialsAvatar(name: name, size: size);

    // Decode seukuran tampilan agar hemat memori.
    final cachePx = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        // Garis tipis agar foto berlatar terang tetap terlihat batasnya.
        foregroundDecoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: ClipOval(
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: cachePx,
            cacheHeight: cachePx,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => InitialsAvatar(name: name, size: size),
          ),
        ),
      ),
    );
  }
}
