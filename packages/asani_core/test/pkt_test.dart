import 'package:asani_core/asani_core.dart';
import 'package:test/test.dart';

void main() {
  test('pktNow is UTC+5 whatever the phone time zone', () {
    // 2026-11-11 20:30 UTC = 2026-11-12 01:30 in Pakistan (a new day).
    final p = pktNow(DateTime.utc(2026, 11, 11, 20, 30));
    expect(dayKey(p), '2026-11-12');
    expect(p.hour, 1);
    expect(p.minute, 30);
    expect(weekdayKey(p), 'thu');
  });
}
