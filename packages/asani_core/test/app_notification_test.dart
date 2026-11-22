import 'package:asani_core/asani_core.dart';
import 'package:test/test.dart';

void main() {
  test('D-43: a notification is unread when newer than the last opening', () {
    final n = AppNotification.fromMap('n1', {
      'type': 'queue',
      'title': "You're next",
      'body': 'Token A-11',
      'route': '/token/t1',
      'tokenId': 't1',
      'createdAt': DateTime(2026, 11, 23, 10).millisecondsSinceEpoch,
    });
    expect(n.route, '/token/t1');
    expect(n.unreadSince(null), isTrue);
    expect(n.unreadSince(DateTime(2026, 11, 23, 9)), isTrue);
    expect(n.unreadSince(DateTime(2026, 11, 23, 11)), isFalse);
  });
}
