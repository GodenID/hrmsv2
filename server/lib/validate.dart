// Cerminan aturan validasi Flutter (EmployeeRules, RegistrationRules,
// Validators). Server memvalidasi ulang semuanya.

final RegExp usernameRe = RegExp(r'^[a-z][a-z0-9._]{2,29}$');
final RegExp nikRe = RegExp(r'^\d{16}$');
final RegExp emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
final RegExp phoneRe = RegExp(r'^\+?[\d\s-]{9,20}$');

String? validateUsername(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return 'Username wajib diisi';
  if (!usernameRe.hasMatch(s)) {
    return '3–30 karakter: huruf kecil, angka, titik, atau garis bawah; diawali huruf';
  }
  return null;
}

String? validateFullName(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return 'Nama lengkap wajib diisi';
  if (s.length < 3) return 'Minimal 3 karakter';
  return null;
}

String? validateNik(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return 'NIK wajib diisi';
  if (!nikRe.hasMatch(s)) return 'NIK harus 16 digit angka (saat ini ${s.length} digit)';
  return null;
}

String? validateEmail(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return 'Email wajib diisi';
  if (!emailRe.hasMatch(s)) return 'Format email tidak valid';
  return null;
}

String? validatePhone(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return 'Nomor telepon wajib diisi';
  final digits = s.replaceAll(RegExp(r'\D'), '').length;
  if (!phoneRe.hasMatch(s) || digits < 9 || digits > 15) {
    return 'Nomor telepon 9–15 digit, mis. 0812-3456-7890';
  }
  return null;
}

String canonicalPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.startsWith('62') ? '0${digits.substring(2)}' : digits;
}

/// Aturan password: sama dengan Flutter — semua kriteria wajib terpenuhi
/// (8+ karakter, besar+kecil, angka, tidak memuat username).
bool passwordOk(String password, String username) {
  if (password.length < 8) return false;
  if (!RegExp(r'[A-Z]').hasMatch(password)) return false;
  if (!RegExp(r'[a-z]').hasMatch(password)) return false;
  if (!RegExp(r'\d').hasMatch(password)) return false;
  final name = username.trim().toLowerCase();
  if (name.length >= 3 && password.toLowerCase().contains(name)) return false;
  return true;
}

const Set<String> divisions = {
  'financeAccounting',
  'hrIt',
  'businessDevelopment',
  'produksiPrasasti',
  'produksiMutiari',
};

const Set<String> employmentStatuses = {
  'permanent',
  'contract',
  'internship',
  'external',
};

const Set<String> genders = {'male', 'female'};

const Set<String> emergencyRelations = {
  'parent',
  'spouse',
  'sibling',
  'child',
  'relative',
  'friend',
  'other',
};
