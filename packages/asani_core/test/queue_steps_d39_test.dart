import 'package:asani_core/asani_core.dart';
import 'package:test/test.dart';

void main() {
  test('D-39: 0 ahead with someone at the doctor gets "You\'re next" once', () {
    final r = nextQueueNotification(status: TokenStatus.booked, ahead: 0, alreadyNotified: {}, someoneWithDoctor: true);
    expect(r.send?.ahead, 1);
    final again = nextQueueNotification(status: TokenStatus.booked, ahead: 0, alreadyNotified: r.notified, someoneWithDoctor: true);
    expect(again.send, isNull);
    expect(nextQueueNotification(status: TokenStatus.booked, ahead: 0, alreadyNotified: {}).send, isNull);
    expect(nextQueueNotification(status: TokenStatus.onHold, ahead: 0, alreadyNotified: {}, someoneWithDoctor: true).send, isNull);
  });
}
