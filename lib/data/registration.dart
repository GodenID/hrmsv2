import 'auth_repository.dart';

/// Model & aturan pendaftaran akun mandiri (halaman "Daftar").
///
/// Server WAJIB:
/// - selalu memberi role [UserRole.staff] pada akun hasil pendaftaran
///   (tidak ada input role dari klien); hanya Super Admin yang kemudian
///   menaikkan / menurunkan role lewat menu Karyawan,
/// - memvalidasi ulang semua data di bawah (jangan percaya validasi klien),
/// - menolak nomor HP yang sudah dipakai akun lain (bandingkan setelah
///   dirapikan via [PhoneNumbers.canonical]; karena endpoint ini publik,
///   pesannya tidak boleh menyebut pemilik nomor),
/// - menolak pendaftaran tanpa persetujuan privasi dan mencatat kapan
///   persetujuan diberikan (bukti consent UU PDP),
/// - menyimpan password dalam bentuk hash (mis. argon2id / bcrypt),
/// - membatasi laju (rate limit) & memakai CAPTCHA pada endpoint publik ini.

enum Gender {
  male('Laki-laki'),
  female('Perempuan');

  const Gender(this.label);

  final String label;
}

/// Divisi di Prasasti Group.
enum Division {
  financeAccounting('Finance & Accounting'),
  hrIt('HR & IT'),
  businessDevelopment('Business Development'),
  produksiPrasasti('Produksi Prasasti'),
  produksiMutiari('Produksi Mutiari');

  const Division(this.label);

  final String label;
}

/// Status kepegawaian — satu-satunya pilihan resmi (tidak ada status teks
/// bebas agar data & laporan konsisten).
enum EmploymentStatus {
  permanent('Perjanjian Kerja Waktu Tidak Tertentu'),
  contract('Perjanjian Kerja Waktu Tertentu'),
  internship('Internship atau Magang'),
  external('External Relations');

  const EmploymentStatus(this.label);

  final String label;

  /// Apakah status ini meminta isian durasi (bulan). Hanya PKWT dan
  /// magang; PKWTT (tetap) dan External Relations tidak.
  bool get requiresDuration =>
      this == EmploymentStatus.contract ||
      this == EmploymentStatus.internship;

  /// Durasi maksimal (bulan): kontrak PKWT 5 tahun (PP 35/2021), magang
  /// 1 tahun (Permenaker 6/2020).
  int get maxMonths => switch (this) {
    EmploymentStatus.permanent => 0,
    EmploymentStatus.contract => 60,
    EmploymentStatus.internship => 12,
    EmploymentStatus.external => 0,
  };

  /// Petunjuk pengisian durasi per status.
  String get durationHint => switch (this) {
    EmploymentStatus.permanent => '',
    EmploymentStatus.contract => 'Lama kontrak, maksimal 60 bulan (5 tahun)',
    EmploymentStatus.internship => 'Lama magang, maksimal 12 bulan',
    EmploymentStatus.external => '',
  };

  /// Label untuk tampil, mis. "Perjanjian Kerja Waktu Tertentu · 12 bulan".
  /// Status tanpa durasi (atau durasi null) tampil labelnya saja.
  String displayLabel(int? months) =>
      requiresDuration && months != null ? '$label · $months bulan' : label;
}

/// Hubungan kontak darurat dengan karyawan.
enum EmergencyRelation {
  parent('Orang tua'),
  spouse('Suami / istri'),
  sibling('Saudara kandung'),
  child('Anak'),
  relative('Kerabat'),
  friend('Teman'),
  other('Lainnya');

  const EmergencyRelation(this.label);

  final String label;
}

class EmergencyContact {
  const EmergencyContact({
    required this.name,
    required this.relation,
    required this.phone,
  });

  final String name;
  final EmergencyRelation relation;
  final String phone;
}

/// Isi formulir pendaftaran. Sengaja tanpa role: role ditentukan server.
class RegistrationDraft {
  const RegistrationDraft({
    required this.username,
    required this.password,
    required this.fullName,
    required this.nik,
    required this.birthPlace,
    required this.birthDate,
    required this.gender,
    required this.address,
    required this.email,
    required this.phone,
    required this.emergencyContact,
    required this.division,
    required this.employmentStatus,
    this.contractMonths,
    required this.privacyConsent,
  });

  final String username;
  final String password;
  final String fullName;
  final String nik;

  /// Tempat & tanggal lahir sesuai KTP.
  final String birthPlace;
  final DateTime birthDate;

  final Gender gender;
  final String address;
  final String email;
  final String phone;
  final EmergencyContact emergencyContact;
  final Division division;

  /// Status kepegawaian pilihan pendaftar.
  final EmploymentStatus employmentStatus;

  /// Durasi (bulan) untuk status yang membutuhkannya; null untuk External
  /// Relations.
  final int? contractMonths;

  /// Persetujuan pemrosesan data pribadi (UU PDP). Server wajib menolak
  /// pendaftaran bila false dan mencatat waktu persetujuan bila true.
  final bool privacyConsent;
}

/// Akun yang berhasil dibuat lewat pendaftaran.
class RegisteredAccount {
  const RegisteredAccount({
    required this.username,
    required this.fullName,
    required this.role,
    required this.division,
    required this.employmentStatus,
    this.contractMonths,
  });

  final String username;
  final String fullName;
  final UserRole role;
  final Division division;
  final EmploymentStatus employmentStatus;
  final int? contractMonths;
}

/// Bagian formulir yang menyebabkan pendaftaran ditolak server, agar
/// halaman bisa langsung membuka langkah yang perlu diperbaiki.
enum RegistrationField {
  username,
  password,
  fullName,
  nik,
  birthPlace,
  birthDate,
  address,
  email,
  phone,
  emergencyContact,
  employmentStatus,
}

class RegistrationException extends AuthException {
  const RegistrationException(super.message, {this.field});

  final RegistrationField? field;
}

/// Aturan validasi khusus pendaftaran (dipakai formulir & mock server).
/// Username, nama, NIK, email & telepon memakai `EmployeeRules`.
abstract final class RegistrationRules {
  static const int addressMaxLength = 200;

  static const int birthPlaceMaxLength = 60;

  /// Usia kerja minimum. Pendaftar wajib ber-NIK KTP, dan KTP diterbitkan
  /// pada usia 17 tahun.
  static const int minimumAgeYears = 17;

  static String? validateBirthPlace(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Tempat lahir wajib diisi';
    if (v.length < 2) return 'Minimal 2 karakter';
    if (v.length > birthPlaceMaxLength) {
      return 'Maksimal $birthPlaceMaxLength karakter';
    }
    return null;
  }

  /// [now] bisa diisi waktu server agar deterministik di pengujian.
  static String? validateBirthDate(DateTime? value, {DateTime? now}) {
    if (value == null) return 'Pilih tanggal lahir';
    final today = _dateOnly(now ?? DateTime.now());
    final birth = _dateOnly(value);
    if (birth.isAfter(today)) {
      return 'Tanggal lahir tidak boleh di masa depan';
    }
    if (ageOn(birth, today) < minimumAgeYears) {
      return 'Pendaftar minimal berusia $minimumAgeYears tahun';
    }
    return null;
  }

  static int ageOn(DateTime birth, DateTime on) {
    var age = on.year - birth.year;
    if (on.month < birth.month ||
        (on.month == birth.month && on.day < birth.day)) {
      age--;
    }
    return age;
  }

  /// Digit 7–12 NIK menyimpan tanggal lahir (DDMMYY; hari +40 untuk
  /// perempuan). Bila tidak cocok dengan tanggal lahir isian, salah
  /// satunya keliru. Tahun 2 digit diartikan ke abad yang tidak membuat
  /// tanggal lahir jatuh di masa depan.
  static String? birthDateMismatch(
    DateTime birth,
    String nik,
    Gender gender, {
    DateTime? now,
  }) {
    final digits = nik.replaceAll(RegExp(r'\D'), '');
    // NIK yang tidak valid ditangani aturannya sendiri.
    if (digits.length != 16) return null;
    final day = int.tryParse(digits.substring(6, 8));
    final month = int.tryParse(digits.substring(8, 10));
    final yy = int.tryParse(digits.substring(10, 12));
    if (day == null || month == null || yy == null) return null;
    var nikDay = day;
    if (gender == Gender.female) {
      if (nikDay < 41 || nikDay > 71) {
        return 'Tanggal lahir tidak sesuai dengan NIK. '
            'Periksa kembali keduanya.';
      }
      nikDay -= 40;
    }
    final today = now ?? DateTime.now();
    var year = 2000 + yy;
    if (year > today.year) year -= 100;
    final b = _dateOnly(birth);
    if (nikDay != b.day || month != b.month || year != b.year) {
      return 'Tanggal lahir tidak sesuai dengan NIK. '
          'Periksa kembali keduanya.';
    }
    return null;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Validasi isian durasi (bulan) untuk [status]. External Relations tidak
  /// memakai durasi sehingga selalu lolos.
  static String? validateContractMonths(
    String? value,
    EmploymentStatus? status,
  ) {
    if (status == null || !status.requiresDuration) return null;
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Isi durasi dalam bulan, mis. 3';
    final months = int.tryParse(v);
    if (months == null) return 'Isi angka bulan, mis. 3';
    if (months < 1) return 'Minimal 1 bulan';
    if (months > status.maxMonths) {
      return 'Maksimal ${status.maxMonths} bulan';
    }
    return null;
  }

  static String? validateAddress(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Alamat wajib diisi';
    if (v.length < 10) {
      return 'Tulis alamat lengkap: jalan, RT/RW, kelurahan, kota';
    }
    if (v.length > addressMaxLength) {
      return 'Maksimal $addressMaxLength karakter';
    }
    return null;
  }

  static String? validateEmergencyName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Nama kontak darurat wajib diisi';
    if (v.length < 2) return 'Minimal 2 karakter';
    return null;
  }

  /// Nomor kontak darurat harus berbeda dari nomor HP karyawan sendiri.
  static String? emergencyPhoneConflict(String emergency, String own) {
    final a = PhoneNumbers.canonical(emergency);
    if (a.isNotEmpty && a == PhoneNumbers.canonical(own)) {
      return 'Gunakan nomor orang lain, bukan nomor HP Anda sendiri';
    }
    return null;
  }
}

/// Bantuan nomor telepon Indonesia.
abstract final class PhoneNumbers {
  /// Merapikan nomor dari buku kontak / teks bebas, mis.
  /// "(0812) 3456-7890" -> "081234567890", "+62 812 3456" -> "+628123456".
  static String clean(String raw) {
    final trimmed = raw.trim();
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    return trimmed.startsWith('+') ? '+$digits' : digits;
  }

  /// Bentuk baku untuk membandingkan dua nomor: awalan +62 / 62 -> 0.
  static String canonical(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.startsWith('62') ? '0${digits.substring(2)}' : digits;
  }
}
