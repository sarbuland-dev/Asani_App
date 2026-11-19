import 'dart:math' as math;

import 'availability.dart';
import 'models.dart';

/// Straight-line distance in km (haversine).
double distanceKm(GeoPoint a, GeoPoint b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// PMDC number as stored: trimmed, upper case, no spaces (D-32).
String normalisePmdc(String raw) => raw.replaceAll(RegExp(r'\s+'), '').toUpperCase();

/// Loose check: 3–7 digits, optional "-" + 1–2 letters, e.g. 12345-P.
bool isValidPmdc(String raw) => RegExp(r'^\d{3,7}(-[A-Z]{1,2})?$').hasMatch(normalisePmdc(raw));

/// Normalised name for the weak match: "Dr. Ayesha  Malik." → "ayesha malik".
String doctorNameKey(String name) {
  var s = name.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  s = s.replaceFirst(RegExp(r'^(dr|doctor) '), '');
  return s;
}

/// One doctor at one clinic, with what the Doctors tab shows.
class DoctorAtClinic {
  const DoctorAtClinic({required this.doctor, required this.clinic, required this.availability, this.km});
  final Doctor doctor;
  final Clinic clinic;
  final DoctorAvailability availability;

  /// Null when the user's or the clinic's location is unknown.
  final double? km;
}

/// One card in the Doctors tab: the main clinic plus "Also sits at" (D-32, D-33).
class DoctorCard {
  const DoctorCard({required this.main, this.alsoAt = const []});
  final DoctorAtClinic main;
  final List<DoctorAtClinic> alsoAt;
}

/// Groups linked doctors into one card and sorts the cards (PRD F-13, D-33):
/// bookable today with a distance (nearest first) → bookable, clinic without a
/// location → not available today. Without the user's location: same area
/// first, then by area A–Z. [items] are one city's doctors of one speciality.
List<DoctorCard> buildDoctorCards(List<DoctorAtClinic> items, {GeoPoint? userLocation, String? userArea}) {
  int tier(DoctorAtClinic x) {
    if (!x.availability.canBook) return 2;
    if (userLocation != null && x.clinic.location == null) return 1;
    return 0;
  }

  int compare(DoctorAtClinic a, DoctorAtClinic b) {
    final t = tier(a).compareTo(tier(b));
    if (t != 0) return t;
    if (a.km != null && b.km != null) {
      final d = a.km!.compareTo(b.km!);
      if (d != 0) return d;
    } else if (a.km != null || b.km != null) {
      return a.km != null ? -1 : 1;
    }
    if (userLocation == null && userArea != null) {
      final sa = a.clinic.area == userArea ? 0 : 1;
      final sb = b.clinic.area == userArea ? 0 : 1;
      if (sa != sb) return sa.compareTo(sb);
    }
    final area = a.clinic.area.compareTo(b.clinic.area);
    return area != 0 ? area : a.doctor.name.compareTo(b.doctor.name);
  }

  final groups = <String, List<DoctorAtClinic>>{};
  final cards = <DoctorCard>[];
  for (final x in items) {
    final g = x.doctor.doctorGroupId;
    if (g == null) {
      cards.add(DoctorCard(main: x));
    } else {
      (groups[g] ??= []).add(x);
    }
  }
  for (final list in groups.values) {
    list.sort(compare);
    cards.add(DoctorCard(main: list.first, alsoAt: list.sublist(1)));
  }
  cards.sort((a, b) => compare(a.main, b.main));
  return cards;
}
