import 'package:asani_core/asani_core.dart';
import 'package:intl/intl.dart';

/// Display formatting for dates, times and phone numbers.
abstract final class Fmt {
  /// "Today, 7 Nov" / "Tomorrow, 8 Nov" / "Mon, 10 Nov"
  static String relativeDay(String key, {DateTime? now}) {
    final date = parseDayKey(key);
    final today = dateOnly(now ?? DateTime.now());
    final diff = date.difference(today).inDays;
    final dm = DateFormat('d MMM').format(date);
    if (diff == 0) return 'Today, $dm';
    if (diff == 1) return 'Tomorrow, $dm';
    return DateFormat('EEE, d MMM').format(date);
  }

  /// "Fri, 7 Nov 2026"
  static String longDay(String key) => DateFormat('EEE, d MMM y').format(parseDayKey(key));

  /// "Wed, 12 Nov"
  static String shortDay(String key) => DateFormat('EEE, d MMM').format(parseDayKey(key));

  /// "17:00" → "5:00 PM"
  static String time(String hhmm) {
    final m = hhmmToMinutes(hhmm);
    return DateFormat('h:mm a').format(DateTime(2000, 1, 1, m ~/ 60, m % 60));
  }

  /// "5:00 – 9:00 PM" style range.
  static String timeRange(DaySchedule s) => '${time(s.start)} – ${time(s.end)}';

  /// Compact "5–9 PM" when both are on the hour and same half of day.
  static String timeRangeShort(DaySchedule s) {
    final a = hhmmToMinutes(s.start), b = hhmmToMinutes(s.end);
    final samePeriod = (a < 720) == (b < 720);
    if (a % 60 == 0 && b % 60 == 0 && samePeriod) {
      int h12(int m) => ((m ~/ 60) + 11) % 12 + 1;
      return '${h12(a)}–${h12(b)} ${b < 720 ? 'AM' : 'PM'}';
    }
    return timeRange(s);
  }

  /// "7 Nov, 2:14 PM"
  static String dateTime(DateTime d) => DateFormat('d MMM, h:mm a').format(d);

  static String clock(DateTime d) => DateFormat('h:mm a').format(d);

  /// "~ 40 min" / "~ 1 hr 10 min"
  static String wait(int minutes) {
    if (minutes <= 0) return 'Any moment';
    if (minutes < 60) return '~ $minutes min';
    final h = minutes ~/ 60, m = minutes % 60;
    return m == 0 ? '~ $h hr' : '~ $h hr $m min';
  }

  /// "+923001234567" → "+92 300 1234567"
  static String phone(String e164) {
    final d = e164.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length == 12 && d.startsWith('92')) return '+92 ${d.substring(2, 5)} ${d.substring(5)}';
    return e164;
  }

  static String initials(String name) {
    final parts = name.replaceAll('Dr.', '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  static String greeting([DateTime? now]) {
    final h = (now ?? DateTime.now()).hour;
    if (h < 12) return 'Good morning,';
    if (h < 17) return 'Good afternoon,';
    return 'Good evening,';
  }
}

/// Pakistani mobile numbers (PRD F-01): +92 then 10 digits starting with 3.
abstract final class PhoneUtils {
  static String digits(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

  /// Accepts "3001234567", "03001234567", "923001234567", "+92 300 1234567"
  /// and returns the 10 local digits ("3001234567"), possibly incomplete.
  static String normalizeLocal(String input) {
    var d = digits(input);
    if (d.startsWith('92') && d.length > 10) d = d.substring(2);
    while (d.startsWith('0')) {
      d = d.substring(1);
    }
    return d.length > 10 ? d.substring(0, 10) : d;
  }

  static bool isValidLocal(String input) => RegExp(r'^3\d{9}$').hasMatch(normalizeLocal(input));

  static String toE164(String local) => '+92${normalizeLocal(local)}';

  /// "3001234567" → "300 1234567"
  static String formatLocal(String input) {
    final d = digits(input);
    if (d.length <= 3) return d;
    return '${d.substring(0, 3)} ${d.substring(3, d.length.clamp(3, 10))}';
  }
}
