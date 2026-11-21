import 'package:asani_core/asani_core.dart';
import 'package:test/test.dart';

void main() {
  final doctor = Doctor(
    id: 'd1',
    clinicId: 'c1',
    name: 'Dr. K',
    speciality: 'GP',
    tokenPrefix: 'B',
    schedule: {for (final d in ['mon', 'tue', 'wed', 'thu', 'fri', 'sat']) d: const DaySchedule('10:00', '14:00')},
  );
  // Saturday 14 Nov 2026.
  DateTime at(int h, int m) => DateTime(2026, 11, 14, h, m);
  Token token(String date, TokenStatus s) => Token(
        id: 't1',
        clinicId: 'c1',
        doctorId: 'd1',
        date: date,
        number: 1,
        tokenPrefix: 'B',
        patientId: 'p1',
        patientSnapshot: const PatientSnapshot(name: 'Test', gender: Gender.male, relation: Relation.self, phone: '+923000000001'),
        bookedByUserId: 'u1',
        status: s,
        createdAt: DateTime(2026, 11, 14, 9),
      );

  test('D-27: today token is live until 1 h after the session end time', () {
    final t = token('2026-11-14', TokenStatus.called);
    expect(tokenIsLive(t, doctor: doctor, now: at(13, 0)), isTrue);
    expect(tokenIsLive(t, doctor: doctor, now: at(14, 59)), isTrue);
    expect(tokenIsLive(t, doctor: doctor, now: at(15, 0)), isFalse);
    expect(tokenIsLive(t, doctor: doctor, now: at(23, 37)), isFalse);
  });

  test('D-27: past days never live, future days always, closed statuses never', () {
    expect(tokenIsLive(token('2026-11-13', TokenStatus.booked), doctor: doctor, now: at(9, 0)), isFalse);
    expect(tokenIsLive(token('2026-11-16', TokenStatus.booked), doctor: doctor, now: at(23, 0)), isTrue);
    expect(tokenIsLive(token('2026-11-14', TokenStatus.completed), doctor: doctor, now: at(11, 0)), isFalse);
  });

  test('D-35: a Skipped token stays live today (paused), but not on a past day', () {
    expect(tokenIsLive(token('2026-11-14', TokenStatus.skipped), doctor: doctor, now: at(11, 0)), isTrue);
    expect(tokenIsLive(token('2026-11-14', TokenStatus.skipped), doctor: doctor, now: at(15, 0)), isFalse);
    expect(tokenIsLive(token('2026-11-13', TokenStatus.skipped), doctor: doctor, now: at(11, 0)), isFalse);
  });

  test('D-35: isNextUp only for a re-checked-in Skipped token', () {
    final t = token('2026-11-14', TokenStatus.arrived);
    expect(t.isNextUp, isFalse);
    final m = t.toMap()..['priorityAt'] = DateTime(2026, 11, 14, 11).millisecondsSinceEpoch;
    expect(Token.fromMap(m).isNextUp, isTrue);
    expect(Token.fromMap(m..['status'] = 'called').isNextUp, isFalse);
  });

  test('D-27: clinic open now only while some doctor session has not ended', () {
    expect(clinicOpenNow([doctor], at(13, 59)), isTrue);
    expect(clinicOpenNow([doctor], at(14, 0)), isFalse);
    expect(clinicOpenOn([doctor], at(14, 0)), isTrue); // still "works today"
  });
}
