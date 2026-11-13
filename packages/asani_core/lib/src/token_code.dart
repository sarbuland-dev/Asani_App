/// Token codes as people type them at reception (PRD-CLINIC-WEB D-16):
/// "A-11", "a11", " A 11 " → letter "A", number 11; "11" → no letter.
abstract final class TokenCode {
  /// Null when the text is not a token code.
  static ({String letter, int number})? parse(String code) {
    final clean = code.trim().toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    final m = RegExp(r'^([A-Z]*)(\d+)$').firstMatch(clean);
    if (m == null) return null;
    return (letter: m.group(1)!, number: int.parse(m.group(2)!));
  }

  /// "A" + 11 → "A-11" (PRD D-13).
  static String label(String letter, int number) => '$letter-$number';
}
