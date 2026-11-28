// D-68: a suspended clinic is read-only, except that it can still cancel tokens.
// (The database has the same rule: supabase/tests/database/06_suspended_today.test.sql.)
import 'package:asani_core/asani_core.dart';
import 'package:clinic_web/core/errors/app_exception.dart';
import 'package:clinic_web/data/demo_clinic_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a suspended clinic cannot change doctors or settings', () async {
    final repo = DemoClinicRepository(simulate: false);
    addTearDown(repo.dispose);
    await repo.signIn('clinic@rehmanclinic.pk', 'asani123');
    final doctor = repo.doctors('c_rehman').first;
    final suspended = throwsA(isA<AppException>().having((e) => e.code, 'code', 'suspended'));

    await expectLater(repo.setDoctorActive(doctor.id, false), suspended);
    await expectLater(repo.addLeave(doctor.id, dayKey(pktNow())), suspended);
    await expectLater(repo.removeLeave(doctor.id, dayKey(pktNow())), suspended);
    await expectLater(repo.saveDoctor('c_rehman', doctor), suspended);
    await expectLater(repo.updateClinicSettings('c_rehman', phone: '042-0000000'), suspended);

    // Cancelling is still possible (it is not refused as suspended).
    expect(await repo.cancelTokensOn(doctor.id, dayKey(pktNow()), 'Clinic closed'), greaterThanOrEqualTo(0));
  });
}
