import 'package:asani_core/asani_core.dart';
import 'package:test/test.dart';

void main() {
  test('parses typed token codes', () {
    expect(TokenCode.parse('A-11'), (letter: 'A', number: 11));
    expect(TokenCode.parse(' a 11 '), (letter: 'A', number: 11));
    expect(TokenCode.parse('11'), (letter: '', number: 11));
    expect(TokenCode.parse('B-'), isNull);
    expect(TokenCode.parse('hello'), isNull);
  });

  test('label', () => expect(TokenCode.label('C', 5), 'C-5'));
}
