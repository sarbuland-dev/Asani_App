import 'models.dart';

/// Rough Pakistan box, to catch swapped or mistyped numbers (D-31).
bool inPakistan(GeoPoint p) => p.lat >= 23.5 && p.lat <= 37.5 && p.lng >= 60.5 && p.lng <= 77.5;

/// Reads a clinic location typed or pasted in the clinic web (C-13, A-04):
/// "31.4697, 74.2728", a Google Maps link with "@31.46,74.27", "?q=31.46,74.27"
/// or "!3d31.46!4d74.27". Null when nothing usable is found.
GeoPoint? parseLatLng(String input) {
  final t = input.trim();
  if (t.isEmpty) return null;
  final patterns = [
    RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)'),
    RegExp(r'@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)'),
    RegExp(r'[?&](?:q|query|ll)=(-?\d+(?:\.\d+)?)(?:,|%2C)\s*(-?\d+(?:\.\d+)?)'),
    RegExp(r'^(-?\d+(?:\.\d+)?)\s*[, ]\s*(-?\d+(?:\.\d+)?)$'),
  ];
  for (final p in patterns) {
    final m = p.firstMatch(t);
    if (m == null) continue;
    final lat = double.tryParse(m.group(1)!), lng = double.tryParse(m.group(2)!);
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) return null;
    return GeoPoint(lat, lng);
  }
  return null;
}

/// "31.46970, 74.27280" for showing a saved location in a form.
String formatLatLng(GeoPoint p) => '${p.lat.toStringAsFixed(5)}, ${p.lng.toStringAsFixed(5)}';
