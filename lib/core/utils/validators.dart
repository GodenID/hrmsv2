/// Aturan kekuatan password yang ditampilkan langsung ke pengguna.
class PasswordRule {
  const PasswordRule(this.label, this.test);

  final String label;
  final bool Function(String value) test;
}

final List<PasswordRule> passwordRules = [
  PasswordRule('Minimal 8 karakter', (v) => v.length >= 8),
  PasswordRule(
    'Huruf besar dan huruf kecil',
    (v) => RegExp(r'[A-Z]').hasMatch(v) && RegExp(r'[a-z]').hasMatch(v),
  ),
  PasswordRule('Minimal satu angka', (v) => RegExp(r'\d').hasMatch(v)),
];

/// Tingkat kekuatan password untuk indikator pendaftaran.
enum PasswordStrength {
  weak('Lemah'),
  medium('Sedang'),
  strong('Kuat');

  const PasswordStrength(this.label);

  final String label;

  bool operator >=(PasswordStrength other) => index >= other.index;
}

/// Kriteria penilaian kekuatan password.
class PasswordCriterion {
  const PasswordCriterion(this.label, this.test, {required this.mandatory});

  final String label;
  final bool Function(String password, String username) test;

  /// true = wajib (tanpa ini password "Lemah").
  /// false = syarat tambahan agar password "Kuat".
  final bool mandatory;
}

final List<PasswordCriterion> passwordCriteria = [
  for (final rule in passwordRules)
    PasswordCriterion(rule.label, (p, _) => rule.test(p), mandatory: true),
  PasswordCriterion('Tidak memuat username', (p, u) {
    final name = u.trim().toLowerCase();
    return name.length < 3 || !p.toLowerCase().contains(name);
  }, mandatory: true),
  PasswordCriterion(
    'Simbol, mis. @ # ! ?',
    (p, _) => RegExp(r'[^A-Za-z0-9\s]').hasMatch(p),
    mandatory: false,
  ),
  PasswordCriterion(
    '12 karakter atau lebih',
    (p, _) => p.length >= 12,
    mandatory: false,
  ),
];

/// - Lemah  : ada kriteria wajib yang belum terpenuhi.
/// - Sedang : semua kriteria wajib terpenuhi.
/// - Kuat   : semua kriteria wajib + tambahan terpenuhi.
PasswordStrength passwordStrength(String password, {String username = ''}) {
  bool passes(PasswordCriterion c) => c.test(password, username);
  if (!passwordCriteria.where((c) => c.mandatory).every(passes)) {
    return PasswordStrength.weak;
  }
  return passwordCriteria.where((c) => !c.mandatory).every(passes)
      ? PasswordStrength.strong
      : PasswordStrength.medium;
}

/// Validator formulir. Mengembalikan pesan galat (Bahasa Indonesia) atau null.
abstract final class Validators {
  static final RegExp _nikPattern = RegExp(r'^\d{16}$');

  static String? username(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Username wajib diisi';
    if (v.length < 3) return 'Username minimal 3 karakter';
    return null;
  }

  static String? loginPassword(String? value) {
    if (value == null || value.isEmpty) return 'Password wajib diisi';
    return null;
  }

  static String? nik(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'NIK wajib diisi';
    if (!_nikPattern.hasMatch(v)) {
      return 'NIK harus 16 digit angka (saat ini ${v.length} digit)';
    }
    return null;
  }

  /// Kekuatan minimum password untuk SEMUA titik: pendaftaran, ganti, dan
  /// atur ulang. Ganti ke [PasswordStrength.strong] bila hanya password
  /// "Kuat" yang diterima.
  static const PasswordStrength minimumPasswordStrength =
      PasswordStrength.medium;

  /// Validator password baru (ganti & atur ulang): mistar yang sama dengan
  /// pendaftaran, termasuk larangan memuat username.
  static String? Function(String?) newPassword(String Function() username) {
    return (value) {
      final v = value ?? '';
      if (v.isEmpty) return 'Password baru wajib diisi';
      if (!(passwordStrength(v, username: username()) >=
          minimumPasswordStrength)) {
        return 'Password masih lemah. Penuhi semua ketentuan wajib.';
      }
      return null;
    };
  }

  static String? Function(String?) registrationPassword(
    String Function() username,
  ) {
    return (value) {
      final v = value ?? '';
      if (v.isEmpty) return 'Password wajib diisi';
      final strength = passwordStrength(v, username: username());
      if (!(strength >= minimumPasswordStrength)) {
        return minimumPasswordStrength == PasswordStrength.strong
            ? 'Password harus berstatus Kuat'
            : 'Password masih lemah. Penuhi semua ketentuan wajib.';
      }
      return null;
    };
  }

  static String? Function(String?) confirmPassword(String Function() original) {
    return (value) {
      final v = value ?? '';
      if (v.isEmpty) return 'Konfirmasi password wajib diisi';
      if (v != original()) return 'Konfirmasi tidak sama dengan password baru';
      return null;
    };
  }
}
