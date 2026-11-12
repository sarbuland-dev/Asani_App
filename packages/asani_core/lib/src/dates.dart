/// Date helpers. Queue day IDs are `yyyy-MM-dd` in clinic local time
/// (Asia/Karachi). The demo backend uses device time as clinic time.

/// Pakistan time now (UTC+5, no daylight saving), ARCHITECTURE.md §7.
/// The fields (year … minute) are the clock in Pakistan, whatever the phone's
/// time zone. Use this, never `DateTime.now()`, for "today", sessions and
/// booking dates, so the app and `bookToken` always agree.
DateTime pktNow([DateTime? utcNow]) {
  final u = (utcNow ?? DateTime.now()).toUtc().add(const Duration(hours: 5));
  return DateTime(u.year, u.month, u.day, u.hour, u.minute, u.second, u.millisecond);
}
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Schedule map keys: mon … sun.
const weekdayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
String weekdayKey(DateTime d) => weekdayKeys[d.weekday - 1];

/// "17:00" → minutes since midnight.
int hhmmToMinutes(String hhmm) {
  final p = hhmm.split(':');
  return int.parse(p[0]) * 60 + int.parse(p[1]);
}

String minutesToHhmm(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
