import 'package:flutter_test/flutter_test.dart';
import 'package:asani_core/asani_core.dart';

void main() {
  test('accepts common Pakistani mobile formats', () {
    for (final input in ['3001234567', '03001234567', '923001234567', '+92 300 1234567', '0300-1234567']) {
      expect(PhoneUtils.isValidLocal(input), isTrue, reason: input);
      expect(PhoneUtils.toE164(input), '+923001234567', reason: input);
    }
  });

  test('rejects non-mobile and incomplete numbers', () {
    for (final input in ['', '300123456', '4001234567', '04235761234', '12345']) {
      expect(PhoneUtils.isValidLocal(input), isFalse, reason: input);
    }
  });

  test('formats as 3XX XXXXXXX', () {
    expect(PhoneUtils.formatLocal(PhoneUtils.normalizeLocal('03001234567')), '300 1234567');
  });
}
