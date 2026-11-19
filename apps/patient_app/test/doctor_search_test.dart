import 'package:asani_core/asani_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/data/demo/demo_backend.dart';
import 'package:patient_app/data/providers.dart';
import 'package:patient_app/features/doctor_search/doctor_search_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// D-31 / D-32 on the demo data: one card for the linked Dr. Ayesha, nearest first.
void main() {
  test('Doctors tab cards from demo data', () async {
    SharedPreferences.setMockInitialValues({});
    final backend = await DemoBackend.create();
    final c = ProviderContainer(overrides: [backendProvider.overrideWithValue(backend)]);
    addTearDown(() {
      c.dispose();
      backend.dispose();
    });

    // Keep the stream providers alive and wait until the cards are built.
    final sub = c.listen(doctorCardsProvider(Speciality.generalPhysician), (_, _) {});
    for (var i = 0; i < 50 && !sub.read().hasValue; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final cards = sub.read().requireValue;

    final ayesha = cards.where((x) => x.main.doctor.name == 'Dr. Ayesha Malik').toList();
    expect(ayesha, hasLength(1), reason: 'linked records make one card');
    expect(ayesha.single.alsoAt, hasLength(1));
    expect(ayesha.single.main.clinic.id, 'c_alshifa', reason: 'Al-Shifa is nearest to the demo location');
    expect(cards.every((x) => x.main.clinic.city == 'Lahore'), isTrue);

    final heart = c.listen(doctorCardsProvider(Speciality.heart), (_, _) {}).read().value ?? const [];
    expect(heart.map((x) => x.main.doctor.name), contains('Dr. Asif Khan'));
  });
}
