import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/firebase_setup.dart';
import '../../core/errors/app_exception.dart';
import '../demo/demo_backend.dart';
import '../repositories/repositories.dart';

/// Phone OTP login on Firebase Auth + the users/{uid} document and "Self"
/// patient profile in Firestore (PRD F-01, docs/04 §2).
///
/// Ported from the asani_auth package. Until the other repositories move to
/// Firebase, the signed-in account is handed to the demo backend so clinics,
/// tokens and family keep working ([DemoBackend.attachAccount]).
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._demo,
      {this.beforeSignOut, FirebaseAuth? auth, FirebaseFirestore? db, FirebaseFunctions? functions})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instanceFor(region: firebaseRegion) {
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
  }

  static const consentVersion = '2026-11-v1';

  /// e.g. remove this phone's FCM token while still signed in.
  final Future<void> Function()? beforeSignOut;

  final DemoBackend _demo;
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final _states = StreamController<AuthState>.broadcast();
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  void dispose() {
    _authSub?.cancel();
    _userSub?.cancel();
    _states.close();
  }

  bool _resolved = false;
  AuthState _current = const AuthState(AuthStatus.signedOut);

  // ---------------------------------------------------------------- state

  @override
  AuthState get current => _current;

  /// Emits nothing until Firebase has answered, so the router keeps showing
  /// the splash screen instead of flashing the login page.
  @override
  Stream<AuthState> watchAuth() async* {
    if (_resolved) yield _current;
    yield* _states.stream;
  }

  void _emit(AuthState s) {
    _current = s;
    _resolved = true;
    if (!_states.isClosed) _states.add(s);
  }

  void _onAuthChanged(User? user) {
    _userSub?.cancel();
    if (user == null) {
      _demo.detachAccount();
      _emit(const AuthState(AuthStatus.signedOut));
      return;
    }
    // Ignore an empty cached snapshot so a returning user never flashes the
    // sign-up screen while the server answer is loading.
    _userSub = _db
        .collection('users')
        .doc(user.uid)
        .snapshots(includeMetadataChanges: true)
        .where((s) => s.exists || !s.metadata.isFromCache)
        .listen((snap) => _onUserDoc(user, snap), onError: (Object e, StackTrace st) {
      // Never send a signed-up user to "Tell us about you" because of a network
      // error: keep the splash screen and try again (it says "check your internet").
      AppLogger.error('users/${user.uid} listen failed, retrying', e, st);
      _userSub?.cancel();
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (_auth.currentUser?.uid == user.uid) _onAuthChanged(user);
      });
    });
  }

  Future<void> _onUserDoc(User user, DocumentSnapshot<Map<String, dynamic>> snap) async {
    final data = snap.data();
    if (!snap.exists || data == null) {
      _demo.detachAccount();
      _emit(AuthState(AuthStatus.needsProfile, user: AppUser(uid: user.uid, phone: user.phoneNumber ?? '', name: '')));
      return;
    }
    final appUser = AppUser(
      uid: user.uid,
      phone: (data['phone'] as String?) ?? user.phoneNumber ?? '',
      name: (data['name'] as String?) ?? '',
      city: (data['city'] as String?) ?? 'Lahore',
      selfPatientId: data['selfPatientId'] as String?,
      consentAcceptedAt: (data['consentAcceptedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      consentVersion: data['consentVersion'] as String?,
      queueAlertsEnabled: (data['queueAlertsEnabled'] as bool?) ?? true,
    );
    _demo.attachAccount(appUser, await _loadSelf(appUser));
    _emit(AuthState(AuthStatus.signedIn, user: appUser));
  }

  Future<Patient> _loadSelf(AppUser user) async {
    final id = user.selfPatientId;
    Map<String, dynamic>? p;
    if (id != null) {
      try {
        p = (await _db.collection('patients').doc(id).get()).data();
      } catch (e, st) {
        AppLogger.error('Could not read Self profile', e, st);
      }
    }
    return Patient(
      id: id ?? 'self_${user.uid}',
      ownerUid: user.uid,
      phone: user.phone,
      name: (p?['name'] as String?) ?? user.name,
      birthYear: (p?['birthYear'] as num?)?.toInt(),
      gender: Gender.parse(p?['gender']),
      relation: Relation.self,
      createdAt: (p?['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  // ---------------------------------------------------------------- login (D-52)

  /// D-52: patients log in with an email code on Supabase. The Firebase backend only keeps an
  /// existing phone session working until it is removed (docs/10 phase 8).
  static const _needsSupabase =
      AppException('unavailable', 'Email login needs the Supabase backend (--dart-define=BACKEND=supabase).');

  @override
  Future<void> sendEmailOtp(String email) async => throw _needsSupabase;

  @override
  Future<void> verifyEmailOtp(String email, String code) async => throw _needsSupabase;

  @override
  Future<void> updatePhone(String phone) async => throw _needsSupabase;

  @override
  void cancelLogin() {
    if (_auth.currentUser == null) _emit(const AuthState(AuthStatus.signedOut));
  }

  // ---------------------------------------------------------------- sign-up

  /// First login: creates users/{uid} and the "Self" patient in ONE batch
  /// (the security rules depend on this, docs/04 §5).
  @override
  Future<void> createProfile({required String name, required int age, required Gender gender, required String phone}) async {
    final user = _auth.currentUser;
    final phoneE164 = user?.phoneNumber;
    if (user == null || phoneE164 == null) throw AppException.sessionExpired;
    final cleanName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final now = FieldValue.serverTimestamp();
    final userRef = _db.collection('users').doc(user.uid);
    final patientRef = _db.collection('patients').doc();

    final batch = _db.batch()
      ..set(patientRef, {
        'phone': phoneE164,
        'ownerUid': user.uid,
        'name': cleanName,
        'nameLower': cleanName.toLowerCase(),
        'birthYear': DateTime.now().year - age,
        'gender': gender.name,
        'relation': 'self',
        'patientPhone': null,
        'status': 'active',
        'mergedInto': null,
        'personId': null,
        'createdBy': 'app',
        'createdAt': now,
        'updatedAt': now,
      })
      ..set(userRef, {
        'phone': phoneE164,
        'name': cleanName,
        'role': 'patient',
        'city': 'Lahore',
        'consentAcceptedAt': now,
        'consentVersion': consentVersion,
        'selfPatientId': patientRef.id,
        'queueAlertsEnabled': true,
        'createdAt': now,
        'updatedAt': now,
        'lastLoginAt': now,
      });
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      throw _mapFirestore(e, 'Could not save your profile. Please try again.');
    }
  }

  // ---------------------------------------------------------------- account

  @override
  Future<void> updateName(String name) async {
    final user = _current.user;
    if (user == null) return;
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    try {
      final batch = _db.batch()
        ..update(_db.collection('users').doc(user.uid), {'name': clean, 'updatedAt': FieldValue.serverTimestamp()});
      if (user.selfPatientId != null) {
        batch.update(_db.collection('patients').doc(user.selfPatientId), {
          'name': clean,
          'nameLower': clean.toLowerCase(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      throw _mapFirestore(e, 'Could not update your name. Please try again.');
    }
  }

  @override
  Future<void> setCity(String city) async {
    final uid = _current.user?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).update({'city': city, 'updatedAt': FieldValue.serverTimestamp()});
    } on FirebaseException catch (e) {
      throw _mapFirestore(e, 'Could not change the city. Please try again.');
    }
  }

  @override
  Future<void> setQueueAlerts(bool enabled) async {
    final uid = _current.user?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).update({'queueAlertsEnabled': enabled, 'updatedAt': FieldValue.serverTimestamp()});
    } on FirebaseException catch (e) {
      throw _mapFirestore(e, 'Could not change queue alerts. Please try again.');
    }
  }

  @override
  Future<void> signOut() async {
    cancelLogin();
    await beforeSignOut?.call();
    await _auth.signOut();
  }

  /// Runs the `deleteAccount` Cloud Function (PRD F-10), then signs out.
  @override
  Future<void> deleteAccount() async {
    try {
      await _functions.httpsCallable('deleteAccount').call<void>();
    } on FirebaseFunctionsException catch (e) {
      AppLogger.error('deleteAccount failed: ${e.code}', e);
      throw e.code == 'not-found' || e.code == 'unavailable' || e.code == 'unimplemented'
          ? const AppException('unavailable', "Account deletion isn't available yet. Please contact support.")
          : AppException.generic;
    }
    await signOut();
  }

  // ---------------------------------------------------------------- errors

  AppException _mapFirestore(FirebaseException e, String fallback) {
    AppLogger.warn('FirebaseException: ${e.code} ${e.message}');
    if (e.code == 'unavailable') return const AppException('network', 'No internet connection. Please try again.');
    return AppException(e.code, kDebugMode ? '$fallback (${e.code})' : fallback);
  }
}
