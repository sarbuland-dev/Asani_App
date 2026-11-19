import 'package:asani_core/asani_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/location_service.dart';
import '../../data/providers.dart';

/// Doctors tab cards for one speciality in the selected city (PRD F-13, F-14).
/// Built from the clinic list + doctors already loaded for Home, so it works
/// with the demo and the Firebase backend without new queries.
final doctorCardsProvider = Provider.family<AsyncValue<List<DoctorCard>>, Speciality>((ref, speciality) {
  final city = ref.watch(selectedCityProvider);
  final clinicsAsync = ref.watch(clinicsProvider(city));
  final byClinicAsync = ref.watch(doctorsByClinicProvider);
  final location = ref.watch(userLocationProvider);
  if (clinicsAsync.hasError) return AsyncValue.error(clinicsAsync.error!, clinicsAsync.stackTrace!);
  if (byClinicAsync.hasError) return AsyncValue.error(byClinicAsync.error!, byClinicAsync.stackTrace!);
  if (!clinicsAsync.hasValue || !byClinicAsync.hasValue || location.isLoading) return const AsyncValue.loading();

  final now = ref.watch(clockProvider).value ?? pktNow();
  final today = dayKey(now);
  final me = location.value;
  final items = <DoctorAtClinic>[];
  for (final clinic in clinicsAsync.value!) {
    for (final d in byClinicAsync.value![clinic.id] ?? const <Doctor>[]) {
      if (!d.active || d.specialityEnum != speciality) continue;
      final day = ref.watch(queueDayProvider((doctorId: d.id, date: today))).value;
      items.add(DoctorAtClinic(
        doctor: d,
        clinic: clinic,
        availability: availabilityFor(doctor: d, date: now, day: day, now: now),
        km: me == null || clinic.location == null ? null : distanceKm(me, clinic.location!),
      ));
    }
  }
  return AsyncValue.data(buildDoctorCards(items, userLocation: me));
});

/// Number of doctors per speciality in the city, for the chip labels.
final specialityCountsProvider = Provider<Map<Speciality, int>>((ref) {
  final city = ref.watch(selectedCityProvider);
  final clinics = ref.watch(clinicsProvider(city)).value ?? const <Clinic>[];
  final byClinic = ref.watch(doctorsByClinicProvider).value ?? const {};
  final counts = <Speciality, int>{};
  for (final c in clinics) {
    for (final d in byClinic[c.id] ?? const <Doctor>[]) {
      if (d.active) counts.update(d.specialityEnum, (n) => n + 1, ifAbsent: () => 1);
    }
  }
  return counts;
});
