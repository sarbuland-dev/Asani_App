import 'package:asani_core/asani_core.dart';
import 'package:test/test.dart';

void main() {
  test('D-50: alert sent times survive toMap / fromMap', () {
    final at = DateTime(2026, 11, 23, 18, 5);
    final t = Token(
      id: 't1',
      clinicId: 'c1',
      doctorId: 'd1',
      date: '2026-11-23',
      number: 11,
      tokenPrefix: 'A',
      patientId: 'p1',
      patientSnapshot: const PatientSnapshot(name: 'Test', gender: Gender.male, relation: Relation.self, phone: '+923000000001'),
      bookedByUserId: 'u1',
      notified: {QueueStep.threeAhead, QueueStep.twoAhead},
      notifiedAt: {QueueStep.threeAhead: at},
      createdAt: DateTime(2026, 11, 23, 17),
    );
    final back = Token.fromMap(t.toMap());
    expect(back.notifiedAt[QueueStep.threeAhead], at);
    expect(back.notifiedAt.containsKey(QueueStep.twoAhead), isFalse); // marked done without a push (N-3)
  });
}
