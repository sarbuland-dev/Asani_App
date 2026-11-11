import 'package:asani_core/asani_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patient_app/core/errors/app_exception.dart';
import 'package:patient_app/data/demo/demo_backend.dart';
import 'package:patient_app/data/repositories/repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Booking rules and queue behaviour of the demo backend (mirrors bookToken).
void main() {
  late DemoBackend backend;

  Future<void> signIn(String phone) async {
    await backend.sendCode(phone);
    await backend.verifyCode(DemoBackend.demoOtp);
    await backend.completeProfile(name: 'Ali Khan', age: 28, gender: Gender.male);
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    backend = await DemoBackend.create();
    await backend.update(backend.settings.copyWith(autoAdvanceQueue: false, notificationsAllowed: true, primerShown: true));
  });

  tearDown(() => backend.dispose());

  test('wrong OTP is rejected, correct OTP signs in', () async {
    await backend.sendCode('+923001112222');
    expect(() => backend.verifyCode('000000'), throwsA(isA<AppException>()));
    await backend.verifyCode(DemoBackend.demoOtp);
    expect(backend.current.status, AuthStatus.needsProfile);
    await backend.completeProfile(name: 'Sara', age: 31, gender: Gender.female);
    expect(backend.current.status, AuthStatus.signedIn);
  });

  test('demo account gets family and history', () async {
    await signIn('+923001234567');
    final patients = await backend.watchMyPatients().first;
    expect(patients.map((p) => p.name), containsAll(['Ali Khan', 'Shazia Begum', 'Ahmed']));
    expect(patients.first.isSelf, isTrue);
  });

  test('booking gives sequential numbers and blocks duplicates (BR-5, BR-7)', () async {
    await signIn('+923005556666');
    final self = (await backend.watchMyPatients().first).first;
    final today = dayKey(DateTime.now());
    final before = await backend.watchDay('d_ayesha', today).first;

    final t = await backend.bookToken(clinicId: 'c_alshifa', doctorId: 'd_ayesha', patientId: self.id, date: today);
    expect(t.number, before.lastTokenNumber + 1);
    expect(t.label, 'A-${before.lastTokenNumber + 1}');

    await expectLater(
      backend.bookToken(clinicId: 'c_alshifa', doctorId: 'd_ayesha', patientId: self.id, date: today),
      throwsA(predicate((e) => e is AppException && e.code == 'duplicate-token')),
    );

    final other = await backend.addPatient(name: 'Shazia Begum', age: 55, gender: Gender.female, relation: Relation.mother);
    final t2 = await backend.bookToken(clinicId: 'c_alshifa', doctorId: 'd_ayesha', patientId: other.id, date: today);
    expect(t2.number, t.number + 1);
  });

  test('doctor on leave and suspended clinic are refused (BR-1, BR-2)', () async {
    await signIn('+923007778888');
    final self = (await backend.watchMyPatients().first).first;
    final today = dayKey(DateTime.now());
    await expectLater(
      backend.bookToken(clinicId: 'c_alshifa', doctorId: 'd_kamran', patientId: self.id, date: today),
      throwsA(predicate((e) => e is AppException && e.code == 'doctor-unavailable')),
    );
    await expectLater(
      backend.bookToken(clinicId: 'c_rehman', doctorId: 'd_rehman', patientId: self.id, date: today),
      throwsA(predicate((e) => e is AppException && e.code == 'clinic-unavailable')),
    );
  });

  test('queue moves, sends 3-2-1 and "Your turn now", then completes', () async {
    await signIn('+923009990000');
    final self = (await backend.watchMyPatients().first).first;
    final today = dayKey(DateTime.now());
    final alerts = <QueueStep>[];
    final sub = backend.alerts.listen((a) => alerts.add(a.step));

    final t = await backend.bookToken(clinicId: 'c_dha', doctorId: 'd_bilal', patientId: self.id, date: today);
    for (var i = 0; i < 10; i++) {
      await backend.advanceQueue('d_bilal');
    }
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(alerts, [QueueStep.threeAhead, QueueStep.twoAhead, QueueStep.oneAhead, QueueStep.called]);
    final after = await backend.watchToken(t.id).first;
    expect(after!.status, TokenStatus.completed);
  });

  test('cancel removes the number from the queue', () async {
    await signIn('+923001110000');
    final self = (await backend.watchMyPatients().first).first;
    final today = dayKey(DateTime.now());
    final t = await backend.bookToken(clinicId: 'c_citycare', doctorId: 'd_imran', patientId: self.id, date: today);
    await backend.cancelToken(t.id);
    final day = await backend.watchDay('d_imran', today).first;
    expect(day.activeNumbers.contains(t.number), isFalse);
    expect((await backend.watchToken(t.id).first)!.status, TokenStatus.cancelled);
  });
}
