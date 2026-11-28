import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:flutter/foundation.dart';
// Supabase has its own AuthState; ours (repositories.dart) is the app's login state.
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../core/errors/app_exception.dart';
import '../demo/demo_backend.dart';
import '../repositories/repositories.dart';

/// Patient login on Supabase (D-52, PRD F-01): "Continue with email" + a 6-digit email code,
/// then profile setup with a required phone that is NOT verified (one phone = one app account).
///
/// The account row (`public.users`) and the Self profile are created by the `create_profile`
/// Postgres function. Until the other repositories move to Supabase (phase 5), the signed-in
/// account is handed to the demo backend so clinics, tokens and family keep working
/// ([DemoBackend.attachAccount]), exactly as the Firebase login did.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._demo, {this.beforeSignOut, SupabaseClient? client})
      : _client = client ?? Supabase.instance.client {
    _authSub = _client.auth.onAuthStateChange.listen((e) => _onSession(e.session), onError: (Object e, StackTrace st) {
      AppLogger.error('Supabase auth stream error', e, st);
    });
  }

  /// Supabase email codes are valid 10 minutes (Auth → Email OTP expiration = 600 s).
  static const codeLifetime = Duration(minutes: 10);

  /// e.g. remove this phone's FCM token while still signed in.
  final Future<void> Function()? beforeSignOut;

  final DemoBackend _demo;
  final SupabaseClient _client;
  final _states = StreamController<AuthState>.broadcast();
  StreamSubscription<Object?>? _authSub;

  bool _resolved = false;
  AuthState _current = const AuthState(AuthStatus.signedOut);
  String? _pendingEmail;
  DateTime? _codeSentAt;
  int _loadGeneration = 0;

  void dispose() {
    _authSub?.cancel();
    _states.close();
  }

  // ---------------------------------------------------------------- state

  @override
  AuthState get current => _current;

  /// Emits nothing until Supabase has restored the session, so the router keeps the splash
  /// screen instead of flashing the login page.
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

  void _onSession(Session? session) {
    final gen = ++_loadGeneration;
    final user = session?.user;
    if (user == null) {
      _demo.detachAccount();
      _emit(_pendingEmail != null
          ? AuthState(AuthStatus.codeSent, pendingEmail: _pendingEmail)
          : const AuthState(AuthStatus.signedOut));
      return;
    }
    // A clinic or Super Admin login (role in app_metadata) never uses the patient app.
    final role = user.appMetadata['role'];
    if (role is String && role.isNotEmpty) {
      AppLogger.warn('Staff account signed in to the patient app; signing out');
      unawaited(_client.auth.signOut());
      return;
    }
    unawaited(_loadAccount(user, gen));
  }

  /// Reads public.users. No row yet = profile setup (needsProfile). A network error never sends a
  /// signed-up user to profile setup: it keeps the splash ("check your internet") and retries.
  Future<void> _loadAccount(User user, int gen) async {
    try {
      final row = await _client.from('users').select().eq('id', user.id).maybeSingle();
      if (gen != _loadGeneration) return;
      _pendingEmail = null;
      if (row == null) {
        _demo.detachAccount();
        _emit(AuthState(AuthStatus.needsProfile, user: AppUser(uid: user.id, phone: '', email: user.email ?? '', name: '')));
        return;
      }
      final appUser = _userFromRow(row);
      _demo.attachAccount(appUser, await _loadSelf(appUser));
      if (gen != _loadGeneration) return;
      _emit(AuthState(AuthStatus.signedIn, user: appUser));
    } catch (e, st) {
      AppLogger.error('Could not read the account, retrying', e, st);
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (gen == _loadGeneration && _client.auth.currentUser?.id == user.id) _loadAccount(user, gen);
      });
    }
  }

  static AppUser _userFromRow(Map<String, dynamic> r) => AppUser(
        uid: r['id'] as String,
        phone: (r['phone'] as String?) ?? '',
        email: (r['email'] as String?) ?? '',
        phoneVerified: (r['phone_verified'] as bool?) ?? false,
        name: Fmt.personName((r['name'] as String?) ?? ''),
        city: (r['city'] as String?) ?? 'Lahore',
        selfPatientId: r['self_patient_id'] as String?,
        consentAcceptedAt: DateTime.tryParse((r['consent_accepted_at'] as String?) ?? '') ?? DateTime.now(),
        consentVersion: r['consent_version'] as String?,
        queueAlertsEnabled: (r['queue_alerts_enabled'] as bool?) ?? true,
      );

  Future<Patient> _loadSelf(AppUser user) async {
    final id = user.selfPatientId;
    Map<String, dynamic>? p;
    if (id != null) {
      try {
        p = await _client.from('patients').select().eq('id', id).maybeSingle();
      } catch (e, st) {
        AppLogger.error('Could not read the Self profile', e, st);
      }
    }
    return Patient(
      id: id ?? 'self_${user.uid}',
      ownerUid: user.uid,
      phone: user.phone,
      name: Fmt.personName((p?['name'] as String?) ?? user.name),
      birthYear: (p?['birth_year'] as num?)?.toInt(),
      gender: Gender.parse(p?['gender']),
      relation: Relation.self,
      createdAt: DateTime.tryParse((p?['created_at'] as String?) ?? '') ?? DateTime.now(),
    );
  }

  Future<void> _reload() async {
    final user = _client.auth.currentUser;
    if (user != null) await _loadAccount(user, ++_loadGeneration);
  }

  // ---------------------------------------------------------------- email code

  @override
  Future<void> sendEmailOtp(String email) async {
    if (!EmailUtils.isValid(email)) throw AppException.invalidEmail;
    final clean = EmailUtils.normalize(email);
    try {
      await _client.auth.signInWithOtp(email: clean, shouldCreateUser: true);
    } catch (e) {
      throw _mapAuth(e);
    }
    _pendingEmail = clean;
    _codeSentAt = DateTime.now();
    if (_client.auth.currentUser == null) _emit(AuthState(AuthStatus.codeSent, pendingEmail: clean));
  }

  @override
  Future<void> verifyEmailOtp(String email, String code) async {
    if (!EmailUtils.isValid(email)) throw AppException.invalidEmail;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) throw AppException.wrongCode;
    try {
      await _client.auth.verifyOTP(email: EmailUtils.normalize(email), token: code, type: OtpType.email);
    } catch (e) {
      throw _mapAuth(e, verifying: true);
    }
    _codeSentAt = null;
    // onAuthStateChange (signedIn) loads the account and moves the router on.
  }

  @override
  void cancelLogin() {
    _pendingEmail = null;
    _codeSentAt = null;
    if (_client.auth.currentUser == null) _emit(const AuthState(AuthStatus.signedOut));
  }

  // ---------------------------------------------------------------- sign-up + account

  @override
  Future<void> createProfile({required String name, required int age, required Gender gender, required String phone}) async {
    if (_client.auth.currentUser == null) throw AppException.sessionExpired;
    if (!PhoneUtils.isValidLocal(phone)) throw AppException.invalidPhone;
    try {
      await _client.rpc('create_profile', params: {
        'p_name': name.trim().replaceAll(RegExp(r'\s+'), ' '),
        'p_age': age,
        'p_gender': gender.name,
        'p_phone': PhoneUtils.toE164(phone),
      });
    } catch (e) {
      throw _mapDb(e, 'Could not save your profile. Please try again.');
    }
    await _reload();
  }

  @override
  Future<void> updatePhone(String phone) async {
    if (!PhoneUtils.isValidLocal(phone)) throw AppException.invalidPhone;
    try {
      await _client.rpc('update_phone', params: {'p_phone': PhoneUtils.toE164(phone)});
    } catch (e) {
      throw _mapDb(e, 'Could not change your number. Please try again.');
    }
    await _reload();
  }

  @override
  Future<void> updateName(String name) async {
    final user = _current.user;
    if (user == null) return;
    final clean = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    try {
      await _client.from('users').update({'name': clean}).eq('id', user.uid);
      if (user.selfPatientId != null) {
        await _client.from('patients').update({'name': clean}).eq('id', user.selfPatientId!);
      }
    } catch (e) {
      throw _mapDb(e, 'Could not update your name. Please try again.');
    }
    await _reload();
  }

  @override
  Future<void> setCity(String city) => _updateUser({'city': city}, 'Could not change the city. Please try again.');

  @override
  Future<void> setQueueAlerts(bool enabled) =>
      _updateUser({'queue_alerts_enabled': enabled}, 'Could not change queue alerts. Please try again.');

  Future<void> _updateUser(Map<String, Object?> values, String fallback) async {
    final uid = _current.user?.uid;
    if (uid == null) return;
    try {
      await _client.from('users').update(values).eq('id', uid);
    } catch (e) {
      throw _mapDb(e, fallback);
    }
    await _reload();
  }

  @override
  Future<void> signOut() async {
    cancelLogin();
    try {
      await beforeSignOut?.call();
    } catch (e) {
      AppLogger.warn('beforeSignOut failed: $e');
    }
    await _client.auth.signOut();
  }

  /// PRD F-10: `delete_my_account()` cancels waiting tokens, anonymises the family's profiles and visit names,
  /// and deletes the login. Clinic visit records stay without personal data. Then this phone signs out.
  @override
  Future<void> deleteAccount() async {
    try {
      await _client.rpc('delete_my_account');
    } catch (e) {
      // Nothing was removed: the person stays signed in and keeps getting alerts.
      throw _mapDb(e, 'Could not delete your account. Please try again.');
    }
    try {
      await beforeSignOut?.call(); // this phone stops expecting alerts
    } catch (e) {
      AppLogger.warn('beforeSignOut failed: $e');
    }
    cancelLogin();
    await _client.auth.signOut().catchError((Object _) {});
  }

  // ---------------------------------------------------------------- errors

  static bool _isNetwork(Object e) {
    final s = e.toString();
    return e is AuthRetryableFetchException ||
        s.contains('SocketException') ||
        s.contains('ClientException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection refused') ||
        s.contains('XMLHttpRequest error');
  }

  AppException _mapAuth(Object e, {bool verifying = false}) {
    if (_isNetwork(e)) return AppException.noInternet;
    if (e is AuthException) {
      AppLogger.warn('AuthException: ${e.code} ${e.statusCode} ${e.message}');
      final code = e.code ?? '';
      if (e.statusCode == '429' || code.contains('rate_limit')) return AppException.tooManyAttempts;
      if (code == 'email_address_invalid' || code == 'validation_failed') return AppException.invalidEmail;
      if (verifying && (code == 'otp_expired' || e.statusCode == '403' || e.statusCode == '400')) {
        // Supabase answers "expired or invalid" for both; our own clock tells them apart.
        final sent = _codeSentAt;
        final old = sent != null && DateTime.now().difference(sent) > codeLifetime;
        return old ? AppException.codeExpired : AppException.wrongCode;
      }
      return AppException('auth-$code', kDebugMode ? 'Login failed ($code).' : AppException.generic.message);
    }
    AppLogger.error('Login error', e);
    return AppException.generic;
  }

  AppException _mapDb(Object e, String fallback) {
    if (_isNetwork(e)) return AppException.noInternet;
    if (e is PostgrestException) {
      AppLogger.warn('PostgrestException: ${e.code} ${e.message}');
      return switch (e.message) {
        'phone-taken' => AppException.phoneTaken,
        'invalid-phone' => AppException.invalidPhone,
        'unauthenticated' => AppException.sessionExpired,
        _ => AppException(e.code ?? 'unknown', kDebugMode ? '$fallback (${e.message})' : fallback),
      };
    }
    AppLogger.error('Database error', e);
    return AppException('unknown', fallback);
  }
}
