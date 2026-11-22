import 'package:asani_core/asani_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart';

import '../repositories/repositories.dart';

/// users/{uid}/notifications (PRD D-45): written by Cloud Functions with every
/// push; the app only reads it and stores `users/{uid}.notificationsSeenAt`.
class FirestoreNotificationRepository implements NotificationRepository {
  FirestoreNotificationRepository({FirebaseAuth? auth, fs.FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? fs.FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final fs.FirebaseFirestore _db;

  fs.DocumentReference<Map<String, dynamic>>? get _me {
    final uid = _auth.currentUser?.uid;
    return uid == null ? null : _db.collection('users').doc(uid);
  }

  static DateTime? _time(Object? v) => v is fs.Timestamp ? v.toDate() : null;

  @override
  Stream<List<AppNotification>> watchNotifications() {
    final me = _me;
    if (me == null) return Stream.value(const []);
    final since = fs.Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30)));
    return me
        .collection('notifications')
        .where('createdAt', isGreaterThan: since)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((q) => [
              for (final d in q.docs)
                AppNotification.fromMap(d.id, {...d.data(), 'createdAt': _time(d.data()['createdAt'])?.millisecondsSinceEpoch}),
            ]);
  }

  @override
  Stream<DateTime?> watchSeenAt() {
    final me = _me;
    if (me == null) return Stream.value(null);
    return me.snapshots().map((d) => _time(d.data()?['notificationsSeenAt']));
  }

  @override
  Future<void> markAllSeen() async {
    await _me?.update({'notificationsSeenAt': fs.FieldValue.serverTimestamp()});
  }
}
