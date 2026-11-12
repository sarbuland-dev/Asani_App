import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../core/config/firebase_setup.dart';
import '../../core/errors/app_exception.dart';
import '../../core/utils/logger.dart';
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

  bool _resolved = false;
  AuthState _current = const AuthState(AuthStatus.signedOut);

  // OTP flow
  String? _pendingPhone;
  String? _verificationId;
  int? _resendToken;
  ConfirmationResult? _webConfirmation; // web uses reCAPTCHA + ConfirmationResult

  void dispose() {
    _authSub?.cancel();
    _userSub?.cancel();
    _states.close();
  }

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
      _emit(_pendingPhone != null
          ? AuthState(AuthStatus.codeSent, pendingPhone: _pendingPhone)
          : const AuthState(AuthStatus.signedOut));
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
      AppLogger.error('users/${user.uid} listen failed', e, st);
      _emit(AuthState(AuthStatus.needsProfile, user: AppUser(uid: user.uid, phone: user.phoneNumber ?? '', name: '')));
    });
  }

  Future<void> _onUserDoc(User user, DocumentSnapshot<Map<String, dynamic>> snap) async {
    _pendingPhone = null;
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

  // ---------------------------------------------------------------- OTP

  @override
  Future<void> sendCode(String e164Phone) async {
    final isResend = e164Phone == _pendingPhone;
    if (kIsWeb) {
      try {
        _webConfirmation = await _auth.signInWithPhoneNumber(e164Phone);
      } on FirebaseAuthException catch (e) {
        throw _map(e);
      }
      _codeSent(e164Phone);
      return;
    }

    final done = Completer<void>();
    await _auth.verifyPhoneNumber(
      phoneNumber: e164Phone,
      timeout: const Duration(seconds: 60),
      forceResendingToken: isResend ? _resendToken : null,
      // Android only: SMS read automatically / instant verification.
      verificationCompleted: (credential) async {
        try {
          await _signIn(credential);
        } catch (e) {
          AppLogger.error('Auto verification failed', e);
        }
        if (!done.isCompleted) done.complete();
      },
      verificationFailed: (e) {
        if (!done.isCompleted) done.completeError(_map(e));
      },
      codeSent: (verificationId, resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        _codeSent(e164Phone);
        if (!done.isCompleted) done.complete();
      },
      codeAutoRetrievalTimeout: (_) {},
    );
    return done.future;
  }

  void _codeSent(String phone) {
    _pendingPhone = phone;
    if (_auth.currentUser == null) _emit(AuthState(AuthStatus.codeSent, pendingPhone: phone));
  }

  @override
  Future<void> verifyCode(String code) async {
    try {
      if (kIsWeb) {
        final confirmation = _webConfirmation;
        if (confirmation == null) throw _expired;
        await confirmation.confirm(code);
        _afterSignIn();
      } else {
        final id = _verificationId;
        if (id == null) throw _expired;
        await _signIn(PhoneAuthProvider.credential(verificationId: id, smsCode: code));
      }
    } on FirebaseAuthException catch (e) {
      throw _map(e);
    }
  }

  static const _expired = AppException('session-expired', 'This code has expired. Please request a new one.');

  Future<void> _signIn(PhoneAuthCredential credential) async {
    try {
      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _map(e);
    }
    _afterSignIn();
  }

  /// Background tasks; login must not fail if these fail.
  void _afterSignIn() {
    _verificationId = null;
    _webConfirmation = null;
    unawaited(_linkPatientProfiles());
    unawaited(_touchLastLogin());
  }

  /// Attaches profiles a clinic created earlier for this phone number.
  /// Safe to call before the Cloud Function is deployed.
  Future<void> _linkPatientProfiles() async {
    try {
      await _functions.httpsCallable('linkPatientProfiles').call<void>();
    } catch (e) {
      AppLogger.info('linkPatientProfiles skipped: $e');
    }
  }

  Future<void> _touchLastLogin() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _db.collection('users').doc(uid).update({
        'lastLoginAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // users doc doesn't exist yet (first login). Fine.
    }
  }

  @override
  void cancelLogin() {
    _pendingPhone = null;
    _verificationId = null;
    _resendToken = null;
    _webConfirmation = null;
    if (_auth.currentUser == null) _emit(const AuthState(AuthStatus.signedOut));
  }

  // ---------------------------------------------------------------- sign-up

  /// First login: creates users/{uid} and the "Self" patient in ONE batch
  /// (the security rules depend on this, docs/04 §5).
  @override
  Future<void> completeProfile({required String name, required int age, required Gender gender}) async {
    final user = _auth.currentUser;
    final phone = user?.phoneNumber;
    if (user == null || phone == null) {
      throw const AppException('session-expired', 'Session expired. Please log in again.');
    }
    final cleanName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final now = FieldValue.serverTimestamp();
    final userRef = _db.collection('users').doc(user.uid);
    final patientRef = _db.collection('patients').doc();

    final batch = _db.batch()
      ..set(patientRef, {
        'phone': phone,
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
        'phone': phone,
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

  AppException _map(FirebaseAuthException e) {
    AppLogger.warn('FirebaseAuthException: ${e.code} ${e.message}');
    return switch (e.code) {
      'invalid-phone-number' => const AppException('invalid-phone', 'This phone number is not valid.'),
      'invalid-verification-code' => AppException.wrongCode,
      'session-expired' || 'code-expired' => _expired,
      'too-many-requests' => AppException.tooManyAttempts,
      'quota-exceeded' => const AppException('quota', 'SMS limit reached. Please try again later.'),
      'network-request-failed' => const AppException('network', 'No internet connection.'),
      // SMS region not allowed, or project not on the Blaze plan (real SMS needs billing).
      'operation-not-allowed' || 'billing-not-enabled' =>
        const AppException('unavailable', 'Phone login is not available right now. Please try later.'),
      _ => AppException('auth-${e.code}', kDebugMode ? 'Login failed (${e.code}).' : AppException.generic.message),
    };
  }

  AppException _mapFirestore(FirebaseException e, String fallback) {
    AppLogger.warn('FirebaseException: ${e.code} ${e.message}');
    if (e.code == 'unavailable') return const AppException('network', 'No internet connection. Please try again.');
    return AppException(e.code, kDebugMode ? '$fallback (${e.code})' : fallback);
  }
}
