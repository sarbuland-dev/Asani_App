import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/config/firebase_setup.dart';
import '../../core/errors/app_exception.dart';
import '../repositories/repositories.dart';

/// Converts Firestore values to the shapes the shared models read:
/// Timestamps → epoch ms, `notified` map (DATABASE.md §7) → list of steps.
Map<String, Object?> _plain(fs.DocumentSnapshot<Map<String, dynamic>> doc) {
  final m = <String, Object?>{...doc.data()!, 'id': doc.id};
  for (final e in m.entries.toList()) {
    if (e.value is fs.Timestamp) m[e.key] = (e.value as fs.Timestamp).millisecondsSinceEpoch;
  }
  return m;
}

const _notifiedKeys = {
  'ahead3': QueueStep.threeAhead,
  'ahead2': QueueStep.twoAhead,
  'ahead1': QueueStep.oneAhead,
  'yourTurn': QueueStep.called,
};

Token? _token(fs.DocumentSnapshot<Map<String, dynamic>> doc) {
  if (!doc.exists) return null;
  try {
    final m = _plain(doc);
    // Server timestamp is null until the write is confirmed.
    m['createdAt'] ??= DateTime.now().millisecondsSinceEpoch;
    final notified = m['notified'];
    m['notified'] = notified is Map ? [for (final k in notified.keys) _notifiedKeys[k]?.name].whereType<String>().toList() : const <String>[];
    return Token.fromMap(m);
  } catch (e) {
    AppLogger.warn('Skipping token ${doc.id}: $e');
    return null;
  }
}

/// Tokens in Firestore `tokens/{tokenId}`; booking and cancelling go through
/// the `bookToken` / `cancelToken` Cloud Functions (AGENTS.md §4.6: the app
/// never writes a token number). DEMO_TO_FIREBASE.txt steps 5–7.
class FirestoreTokenRepository implements TokenRepository {
  FirestoreTokenRepository({Stream<QueueAlert>? alerts, FirebaseAuth? auth, fs.FirebaseFirestore? db, FirebaseFunctions? functions})
      : _alerts = alerts ?? const Stream.empty(),
        _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? fs.FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instanceFor(region: firebaseRegion);

  final Stream<QueueAlert> _alerts;
  final FirebaseAuth _auth;
  final fs.FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  fs.CollectionReference<Map<String, dynamic>> get _tokens => _db.collection('tokens');

  /// Tokens I booked (index: bookedByUserId + createdAt desc) plus walk-ins the
  /// clinic made for my family's profiles (PRD D-22, `patientOwnerUid`; two
  /// equality filters, so no extra index). Newest first.
  /// The provider restarts this stream when the signed-in user changes.
  @override
  Stream<List<Token>> watchMyTokens() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    final booked = _tokens.where('bookedByUserId', isEqualTo: uid).orderBy('createdAt', descending: true).limit(100).snapshots();
    final walkIns = _tokens.where('patientOwnerUid', isEqualTo: uid).where('source', isEqualTo: 'walkIn').limit(100).snapshots();
    return _combineLatest(booked, walkIns).map((pair) {
      final byId = <String, Token>{};
      for (final d in [...pair.$1.docs, ...pair.$2.docs]) {
        final t = _token(d);
        if (t != null) byId[t.id] = t;
      }
      return byId.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  @override
  Future<List<Token>> loadOlderTokens(DateTime before, {int limit = 50}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const [];
    final at = fs.Timestamp.fromDate(before);
    final res = await Future.wait([
      _tokens.where('bookedByUserId', isEqualTo: uid).where('createdAt', isLessThan: at).orderBy('createdAt', descending: true).limit(limit).get(),
      // DATABASE §9: patientOwnerUid + source + createdAt (walk-ins on my profiles, D-22).
      _tokens
          .where('patientOwnerUid', isEqualTo: uid)
          .where('source', isEqualTo: 'walkIn')
          .where('createdAt', isLessThan: at)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get(),
    ]);
    final byId = <String, Token>{};
    for (final d in [...res[0].docs, ...res[1].docs]) {
      final t = _token(d);
      if (t != null) byId[t.id] = t;
    }
    return (byId.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt))).take(limit).toList();
  }

  /// Emits once both streams have a value, then on every change of either.
  static Stream<(A, B)> _combineLatest<A, B>(Stream<A> a, Stream<B> b) {
    late StreamController<(A, B)> c;
    StreamSubscription<A>? sa;
    StreamSubscription<B>? sb;
    A? la;
    B? lb;
    var hasA = false, hasB = false;
    void emit() {
      if (hasA && hasB) c.add((la as A, lb as B));
    }

    c = StreamController<(A, B)>(
      onListen: () {
        sa = a.listen((v) {
          la = v;
          hasA = true;
          emit();
        }, onError: c.addError);
        sb = b.listen((v) {
          lb = v;
          hasB = true;
          emit();
        }, onError: c.addError);
      },
      onCancel: () async {
        await sa?.cancel();
        await sb?.cancel();
      },
    );
    return c.stream;
  }

  @override
  Stream<Token?> watchToken(String tokenId) => _tokens.doc(tokenId).snapshots().map(_token);

  /// FCM pushes that arrive while the app is open (PushService).
  @override
  Stream<QueueAlert> get alerts => _alerts;

  @override
  Future<Token> bookToken({
    required String clinicId,
    required String doctorId,
    required String patientId,
    required String date,
  }) async {
    final String tokenId;
    try {
      final res = await _functions.httpsCallable('bookToken').call<Map<String, dynamic>>({
        'clinicId': clinicId,
        'doctorId': doctorId,
        'patientId': patientId,
        'date': date,
      });
      tokenId = res.data['tokenId'] as String;
    } on FirebaseFunctionsException catch (e) {
      throw _bookingError(e);
    }
    final token = _token(await _tokens.doc(tokenId).get());
    if (token == null) throw AppException.bookingFailed;
    return token;
  }

  @override
  Future<void> cancelToken(String tokenId) async {
    try {
      await _functions.httpsCallable('cancelToken').call<Map<String, dynamic>>({'tokenId': tokenId});
    } on FirebaseFunctionsException catch (e) {
      AppLogger.warn('cancelToken ${e.code}: ${e.message}');
      if (e.code == 'unavailable') throw const AppException('network', 'No internet connection. Your token was not cancelled.');
      if (e.code == 'failed-precondition') {
        throw const AppException('cannot-cancel', 'This token can no longer be cancelled.');
      }
      throw AppException.generic;
    }
  }

  /// DESIGN.md §7: `details.code` from the function → the message to show.
  static AppException _bookingError(FirebaseFunctionsException e) {
    AppLogger.warn('bookToken ${e.code}: ${e.message}');
    final details = e.details is Map ? e.details as Map : const {};
    switch (details['code']) {
      case 'clinic-unavailable':
        return AppException.clinicUnavailable;
      case 'doctor-unavailable':
        return AppException.doctorUnavailable;
      case 'session-ended':
        return AppException.sessionEnded;
      case 'tokens-full':
        return AppException.tokensFull;
      case 'too-many-active':
        return AppException.tooManyActive;
      case 'duplicate-token':
        return AppException.duplicateToken('${details['name'] ?? 'This patient'}', '${details['label'] ?? ''}');
    }
    if (e.code == 'unavailable' || e.code == 'deadline-exceeded') return AppException.network;
    return AppException.bookingFailed;
  }
}

/// Queue day `doctors/{doctorId}/days/{date}` (DATABASE.md §6). Read-only:
/// numbers only, no personal data. Missing day = nothing booked yet.
class FirestoreQueueRepository implements QueueRepository {
  FirestoreQueueRepository({fs.FirebaseFirestore? db}) : _db = db ?? fs.FirebaseFirestore.instance;

  final fs.FirebaseFirestore _db;

  @override
  Stream<QueueDay> watchDay(String doctorId, String date) =>
      _db.collection('doctors').doc(doctorId).collection('days').doc(date).snapshots().map((doc) {
        if (!doc.exists) return QueueDay.empty('', doctorId, date);
        try {
          return QueueDay.fromMap(_plain(doc));
        } catch (e) {
          AppLogger.warn('Bad queue day ${doc.id}: $e');
          return QueueDay.empty('', doctorId, date);
        }
      });
}

/// Follow-ups in Firestore `followUps/{id}` (PRD F-09, DATABASE.md §8).
/// Read-only for the app: staff (Phase 2) or the admin script create them, and
/// `bookToken` marks them booked.
class FirestoreFollowUpRepository implements FollowUpRepository {
  FirestoreFollowUpRepository({FirebaseAuth? auth, fs.FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? fs.FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final fs.FirebaseFirestore _db;

  /// Mine, soonest first. The provider restarts this when the user changes.
  @override
  Stream<List<FollowUp>> watchMyFollowUps() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return Stream.value(const []);
    return _db.collection('followUps').where('ownerUid', isEqualTo: uid).snapshots().map((s) {
      final list = <FollowUp>[];
      for (final d in s.docs) {
        try {
          list.add(FollowUp.fromMap(_plain(d)));
        } catch (e) {
          AppLogger.warn('Skipping follow-up ${d.id}: $e');
        }
      }
      return list..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    });
  }
}
