import 'package:intl/intl.dart';

/// Extra formatting used only on the clinic web.
abstract final class WebFmt {
  static final _money = NumberFormat.decimalPattern('en_PK');

  /// 4500 → "Rs 4,500"
  static String money(num amount) => 'Rs ${_money.format(amount)}';

  /// "2026-11" → "Nov 2026"
  static String month(String yyyyMm) => DateFormat('MMM y').format(DateTime.parse('$yyyyMm-01'));

  /// "12 Nov 2026"
  static String date(DateTime d) => DateFormat('d MMM y').format(d);

  /// "2h ago", "3d ago", "just now"
  static String ago(DateTime d, {DateTime? now}) {
    final diff = (now ?? DateTime.now()).difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return date(d);
  }

  /// 4 → "4th"
  static String ordinal(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 13) return '${n}th';
    return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
  }

  /// Minutes as "18 min" / "1 hr 5 min"; null → "—".
  static String minutes(num? m) {
    if (m == null) return '—';
    final v = m.round();
    if (v < 60) return '$v min';
    return v % 60 == 0 ? '${v ~/ 60} hr' : '${v ~/ 60} hr ${v % 60} min';
  }
}
