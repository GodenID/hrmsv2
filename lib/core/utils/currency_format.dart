import 'package:flutter/services.dart';

/// Format Rupiah tanpa dependensi: 8450000 -> "Rp 8.450.000".
abstract final class Rupiah {
  static String format(int amount) {
    final negative = amount < 0;
    return '${negative ? '-' : ''}Rp ${group(amount.abs())}';
  }

  /// 8450000 -> "8.450.000"
  static String group(int amount) {
    final digits = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// "50.000.000" -> 50000000; null bila kosong/tidak valid.
  static int? parse(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }
}

/// Input nominal Rupiah: hanya angka, otomatis diberi titik ribuan.
/// Maksimal 13 digit (aman untuk web, di bawah 2^53).
class RupiahInputFormatter extends TextInputFormatter {
  static const int maxDigits = 13;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return TextEditingValue.empty;
    if (digits.length > maxDigits) return oldValue;
    digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final formatted = Rupiah.group(int.parse(digits));
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
