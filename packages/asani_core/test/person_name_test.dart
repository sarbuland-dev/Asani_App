import 'package:asani_core/asani_core.dart';
import 'package:test/test.dart';

void main() {
  test('personName capitalises the first letter of each part only', () {
    expect(Fmt.personName('ali khan'), 'Ali Khan');
    expect(Fmt.personName('m.ali al-hassan'), 'M.Ali Al-Hassan');
    expect(Fmt.personName('ahmed (son)'), 'Ahmed (Son)');
    expect(Fmt.personName('Sara McKay'), 'Sara McKay');
    expect(Fmt.personName(''), '');
  });
}
