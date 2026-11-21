import 'package:asani_core/asani_core.dart';
import 'package:test/test.dart';

void main() {
  test('parseLatLng: typed numbers and Google Maps links', () {
    GeoPoint? p(String s) => parseLatLng(s);
    expect(p('31.4697, 74.2728')?.lat, 31.4697);
    expect(p('31.4697 74.2728')?.lng, 74.2728);
    expect(p('https://www.google.com/maps/place/X/@31.4697,74.2728,17z/data=!3d31.4698!4d74.2729')?.lat, 31.4698);
    expect(p('https://www.google.com/maps/@31.5102,74.3511,15z')?.lng, 74.3511);
    expect(p('https://maps.google.com/?q=31.4835,74.3239')?.lat, 31.4835);
    expect(p(''), isNull);
    expect(p('Johar Town'), isNull);
    expect(p('120, 74'), isNull);
  });

  test('inPakistan catches swapped numbers', () {
    expect(inPakistan(const GeoPoint(31.47, 74.27)), isTrue);
    expect(inPakistan(const GeoPoint(74.27, 31.47)), isFalse);
    expect(formatLatLng(const GeoPoint(31.4697, 74.2728)), '31.46970, 74.27280');
  });
}
