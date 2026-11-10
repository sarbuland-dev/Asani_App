import 'package:asani_core/asani_core.dart';
import 'package:test/test.dart';

Doctor _doctor({List<String> leave = const []}) => Doctor(
      id: 'd1',
      clinicId: 'c1',
      name: 'Dr. Test',
      speciality: 'GP',
      tokenPrefix: 'A',
      maxTokensPerDay: 40,
      schedule: {
        for (final k in weekdayKeys) k: k == 'sun' ? null : const DaySchedule('17:00', '21:00'),
      },
      onLeaveDates: leave,
    );

void main() {
  group('patientsAhead', () {
    test('counts only lower active numbers', () {
      expect(patientsAhead([8, 9, 10, 12, 15], 12), 3);
      expect(patientsAhead([12, 15], 12), 0);
    });
    test('estimated wait', () => expect(estimatedWaitMinutes(3, 10), 30));
  });

  group('nextQueueNotification', () {
    test('sends 3, 2, 1 then called, once each', () {
      var notified = <QueueStep>{};
      final sent = <QueueStep>[];
      for (final (status, ahead) in [
        (TokenStatus.booked, 5),
        (TokenStatus.booked, 3),
        (TokenStatus.booked, 3),
        (TokenStatus.booked, 2),
        (TokenStatus.booked, 1),
        (TokenStatus.called, 0),
        (TokenStatus.called, 0),
      ]) {
        final r = nextQueueNotification(status: status, ahead: ahead, alreadyNotified: notified);
        notified = r.notified;
        if (r.send != null) sent.add(r.send!);
      }
      expect(sent, [QueueStep.threeAhead, QueueStep.twoAhead, QueueStep.oneAhead, QueueStep.called]);
    });

    test('queue jump sends only the latest step (N-3)', () {
      final r = nextQueueNotification(status: TokenStatus.booked, ahead: 1, alreadyNotified: {});
      expect(r.send, QueueStep.oneAhead);
      expect(r.notified, {QueueStep.threeAhead, QueueStep.twoAhead, QueueStep.oneAhead});
      final again = nextQueueNotification(status: TokenStatus.booked, ahead: 2, alreadyNotified: r.notified);
      expect(again.send, isNull);
    });

    test('no notification for cancelled tokens', () {
      final r = nextQueueNotification(status: TokenStatus.cancelled, ahead: 2, alreadyNotified: {});
      expect(r.send, isNull);
    });
  });

  group('availabilityFor', () {
    final friday = DateTime(2026, 11, 6);
    test('not started before session', () {
      expect(availabilityFor(doctor: _doctor(), date: friday, now: DateTime(2026, 11, 6, 15)),
          DoctorAvailability.notStarted);
    });
    test('available during session', () {
      expect(availabilityFor(doctor: _doctor(), date: friday, now: DateTime(2026, 11, 6, 18)),
          DoctorAvailability.available);
    });
    test('ended after end time (BR-3)', () {
      expect(availabilityFor(doctor: _doctor(), date: friday, now: DateTime(2026, 11, 6, 21, 5)),
          DoctorAvailability.ended);
    });
    test('no schedule on Sunday', () {
      expect(availabilityFor(doctor: _doctor(), date: DateTime(2026, 11, 8), now: friday),
          DoctorAvailability.notScheduled);
    });
    test('on leave', () {
      expect(availabilityFor(doctor: _doctor(leave: ['2026-11-09']), date: DateTime(2026, 11, 9), now: friday),
          DoctorAvailability.onLeave);
    });
    test('full (BR-4)', () {
      final day = const QueueDay(clinicId: 'c1', doctorId: 'd1', date: '2026-11-10', bookedCount: 40);
      expect(availabilityFor(doctor: _doctor(), date: DateTime(2026, 11, 10), day: day, now: friday),
          DoctorAvailability.full);
    });
  });

  test('models round-trip through maps', () {
    final t = Token(
      id: 't1',
      clinicId: 'c1',
      doctorId: 'd1',
      date: '2026-11-07',
      number: 11,
      tokenPrefix: 'A',
      patientId: 'p1',
      patientSnapshot: const PatientSnapshot(
          name: 'Shazia Begum', birthYear: 1971, gender: Gender.female, relation: Relation.mother, phone: '+923001234567'),
      bookedByUserId: 'u1',
      notified: {QueueStep.threeAhead},
      createdAt: DateTime(2026, 11, 7, 14, 14),
    );
    final back = Token.fromMap(t.toMap());
    expect(back.label, 'A-11');
    expect(back.notified, {QueueStep.threeAhead});
    expect(back.patientSnapshot.relation, Relation.mother);
  });
}
