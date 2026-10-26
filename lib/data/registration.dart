// Model data diri karyawan & aturan validasinya.
// Server menegakkan ulang semua aturan ini.

enum Gender {
  male('Laki-laki'),
  female('Perempuan');

  const Gender(this.label);

  final String label;
}

/// Divisi di Prasasti Group.
///
/// Daftar resmi kini berupa master data di server (dikelola Super Admin),
/// jadi kelas ini hanya membawa kode + label. Kode bersifat tetap karena
/// dipakai data karyawan dan penargetan pengumuman.
class Division {
  const Division({required this.code, required this.label});

  /// Kode unik (mis. `produksiPrasasti`).
  final String code;

  /// Nama tampilan (mis. `Produksi Prasasti`).
  final String label;

  /// Dipakai bila server mengirim kode lama tanpa label.
  static const Division unknown = Division(code: 'hrIt', label: 'HR & IT');

  /// Membaca pasangan `division` + `divisionLabel` dari JSON.
  factory Division.fromJson(Object? code, [Object? label]) {
    final c = (code ?? '').toString();
    if (c.isEmpty) return unknown;
    final l = (label ?? '').toString();
    return Division(code: c, label: l.isEmpty ? c : l);
  }

  @override
  bool operator ==(Object other) => other is Division && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => label;
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

/// Aturan validasi data diri karyawan (dipakai formulir; server menegakkan ulang).
/// Username, nama, NIK, email & telepon memakai `EmployeeRules`.
abstract final class RegistrationRules {
  static const int addressMaxLength = 200;

  static const int birthPlaceMaxLength = 60;

  static String? validateBirthPlace(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Tempat lahir wajib diisi';
    if (v.length < 2) return 'Minimal 2 karakter';
    if (v.length > birthPlaceMaxLength) {
      return 'Maksimal $birthPlaceMaxLength karakter';
    }
    return null;
  }

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
