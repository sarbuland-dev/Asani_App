import 'package:asani_core/asani_core.dart';
import 'package:test/test.dart';

void main() {
  test('speciality keys, old free text and unknown values', () {
    expect(Speciality.resolve('heart'), Speciality.heart);
    expect(Speciality.resolve('Cardiologist'), Speciality.heart);
    expect(Speciality.resolve('General Physician'), Speciality.generalPhysician);
    expect(Speciality.resolve('ENT Specialist'), Speciality.ent);
    expect(Speciality.resolve('Pediatrician'), Speciality.child);
    expect(Speciality.resolve('Gynecologist'), Speciality.womensHealth);
    expect(Speciality.fromLegacy('Astrologer'), isNull);
    expect(Speciality.resolve('Astrologer'), Speciality.other);
    expect(Speciality.heart.display, 'Heart (Cardiologist)');
    expect(Speciality.physio.display, 'Physiotherapy');
  });

  test('distance, PMDC and name key', () {
    final johar = const GeoPoint(31.4697, 74.2728);
    final dha = const GeoPoint(31.4625, 74.4086);
    expect(distanceKm(johar, johar), 0);
    expect(distanceKm(johar, dha), closeTo(12.9, 1));
    expect(isValidPmdc('12345'), isTrue);
    expect(isValidPmdc(' 12345-p '), isTrue);
    expect(normalisePmdc(' 12345-p '), '12345-P');
    expect(isValidPmdc('abc'), isFalse);
    expect(isValidPmdc('12-34-5'), isFalse);
    expect(doctorNameKey('Dr. Ayesha  Malik.'), 'ayesha malik');
    expect(doctorNameKey('dr ayesha malik'), 'ayesha malik');
  });

  group('buildDoctorCards', () {
    Clinic clinic(String id, String area, GeoPoint? at) =>
        Clinic(id: id, name: id, area: area, city: 'Lahore', address: '', phone: '', location: at);
    Doctor doctor(String id, String clinicId, {String? group}) =>
        Doctor(id: id, clinicId: clinicId, name: 'Dr $id', speciality: 'heart', tokenPrefix: 'A', schedule: const {}, doctorGroupId: group);
    final near = clinic('near', 'Johar Town', const GeoPoint(31.47, 74.27));
    final far = clinic('far', 'DHA', const GeoPoint(31.46, 74.41));
    final noLoc = clinic('noloc', 'Gulberg', null);
    const me = GeoPoint(31.47, 74.27);
    DoctorAtClinic at(Doctor d, Clinic c, {bool open = true}) => DoctorAtClinic(
          doctor: d,
          clinic: c,
          availability: open ? DoctorAvailability.available : DoctorAvailability.onLeave,
          km: c.location == null ? null : distanceKm(me, c.location!),
        );

    test('nearest first, no location next, not available last', () {
      final cards = buildDoctorCards([
        at(doctor('x', 'far'), far),
        at(doctor('y', 'noloc'), noLoc),
        at(doctor('z', 'near'), near, open: false),
        at(doctor('w', 'near'), near),
      ], userLocation: me);
      expect(cards.map((c) => c.main.doctor.id), ['w', 'x', 'y', 'z']);
    });

    test('linked doctors make one card, nearest clinic is main', () {
      final cards = buildDoctorCards([
        at(doctor('a1', 'far', group: 'g'), far),
        at(doctor('a2', 'near', group: 'g'), near),
        at(doctor('b', 'far'), far),
      ], userLocation: me);
      expect(cards.length, 2);
      expect(cards.first.main.doctor.id, 'a2');
      expect(cards.first.alsoAt.single.doctor.id, 'a1');
    });

    test('without location: same area first, then area A–Z', () {
      DoctorAtClinic plain(Doctor d, Clinic c) => DoctorAtClinic(doctor: d, clinic: c, availability: DoctorAvailability.available);
      final cards = buildDoctorCards([
        plain(doctor('x', 'near'), near),
        plain(doctor('y', 'noloc'), noLoc),
        plain(doctor('z', 'far'), far),
      ], userArea: 'Gulberg');
      expect(cards.map((c) => c.main.doctor.id), ['y', 'z', 'x']);
    });
  });
}
