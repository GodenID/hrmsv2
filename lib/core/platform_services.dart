import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:geolocator/geolocator.dart';

import '../data/app_exception.dart';
import '../data/attendance_location.dart';

/// Lokasi perangkat tidak bisa dipakai (GPS mati, izin ditolak, dsb.).
class LocationUnavailableException extends AppException {
  const LocationUnavailableException(
    super.message, {
    this.canOpenSettings = false,
  });

  /// true = arahkan pengguna ke pengaturan aplikasi / lokasi.
  final bool canOpenSettings;
}

/// File yang dipilih pengguna.
class PickedFile {
  const PickedFile({
    required this.name,
    required this.sizeBytes,
    required this.extension,
    this.bytes,
  });

  final String name;
  final int sizeBytes;
  final String? extension;

  /// Isi file, hanya bila diminta via `withData: true`.
  final Uint8List? bytes;
}

/// Gambar yang dipilih pengguna, isinya sudah dibaca.
class PickedImage {
  const PickedImage({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// Kontak (nama + satu nomor) yang dipilih dari buku kontak perangkat.
class PickedContact {
  const PickedContact({required this.name, required this.phone});

  final String name;

  /// Nomor apa adanya dari perangkat (belum dirapikan).
  final String phone;
}

/// Pembungkus plugin platform (pilih file, pilih kontak), agar halaman tidak
/// bergantung langsung pada plugin dan mudah diuji.
class PlatformServices {
  const PlatformServices();

  /// Mengembalikan null bila pengguna membatalkan.
  Future<PickedFile?> pickFile({
    required List<String> allowedExtensions,
    bool withData = false,
  }) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedFile(
      name: file.name,
      sizeBytes: await file.length() ?? bytes.length,
      extension: file.extension?.toLowerCase().replaceFirst('.', ''),
      bytes: withData ? bytes : null,
    );
  }

  /// Membuka galeri (HP) / pemilih file (web & desktop) untuk memilih satu
  /// gambar. Tidak butuh izin galeri: sistem hanya memberikan foto yang
  /// dipilih. Mengembalikan null bila dibatalkan.
  Future<PickedImage?> pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return null;
    return PickedImage(name: file.name, bytes: await file.readAsBytes());
  }

  /// Pemilih kontak bawaan sistem hanya ada di aplikasi Android & iOS
  /// (tidak di web / desktop).
  bool get supportsContactPicker =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Membuka pemilih kontak sistem untuk memilih satu nomor telepon.
  /// Tidak membutuhkan izin baca kontak: aplikasi hanya menerima kontak
  /// yang dipilih pengguna. Mengembalikan null bila dibatalkan.
  Future<PickedContact?> pickContactPhone() async {
    final contact = await FlutterNativeContactPicker().selectPhoneNumber();
    if (contact == null) return null;
    final phone =
        contact.selectedPhoneNumber ??
        (contact.phoneNumbers?.isNotEmpty == true
            ? contact.phoneNumbers!.first
            : '');
    return PickedContact(name: contact.fullName?.trim() ?? '', phone: phone);
  }

  /// Posisi perangkat saat ini untuk validasi area absen. Meminta izin
  /// lokasi bila belum diberikan. Melempar [LocationUnavailableException]
  /// dengan pesan yang bisa langsung ditampilkan.
  Future<GeoPoint> getCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const LocationUnavailableException(
          'Layanan lokasi (GPS) perangkat mati. Aktifkan lokasi lalu coba '
          'lagi.',
          canOpenSettings: true,
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const LocationUnavailableException(
          'Izin lokasi ditolak. Absen membutuhkan lokasi Anda untuk '
          'memastikan Anda berada di area kantor.',
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw const LocationUnavailableException(
          'Izin lokasi diblokir. Buka pengaturan, izinkan akses lokasi untuk '
          'Prasasti Connect, lalu coba lagi.',
          canOpenSettings: true,
        );
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return GeoPoint(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
        isMocked: p.isMocked,
      );
    } on LocationUnavailableException {
      rethrow;
    } on TimeoutException {
      throw const LocationUnavailableException(
        'Lokasi belum didapat dalam 20 detik. Pindah ke area terbuka atau '
        'dekat jendela, lalu coba lagi.',
      );
    } catch (_) {
      throw const LocationUnavailableException(
        'Lokasi perangkat tidak dapat dibaca. Pastikan izin & layanan lokasi '
        'aktif, lalu coba lagi.',
      );
    }
  }

  /// Membuka pengaturan izin aplikasi (atau pengaturan lokasi bila izin
  /// sudah diberikan tetapi GPS mati).
  Future<void> openLocationSettings() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
      } else {
        await Geolocator.openLocationSettings();
      }
    } catch (_) {
      // Tidak semua platform (mis. web) punya halaman pengaturan.
    }
  }
}
