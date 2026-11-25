import 'dart:async';
import 'dart:convert';

import 'package:asani_core/asani_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

import '../../core/errors/app_exception.dart';
import '../repositories/repositories.dart';
import 'rows.dart';

/// Patient app data on Supabase (D-52, phase 5). Reads are Realtime streams (`.stream()`), which
/// apply the same Row Level Security as normal reads: a patient only ever receives their own tokens,
/// profiles, follow-ups and notifications. Every important write goes through a Postgres function
/// (`book_token`, `cancel_token`); the app never writes a token number (AGENTS.md §4.6).
///
/// Realtime filters on uuid columns (`booked_by_user_id`, `owner_uid`, `user_id`) and on `id` never fire
/// (found 2026-11-25, tools/db-test/client-smoke.js); filters on `clinic_id`, `doctor_id`, `city` and `active` do.
/// Streams that would need a broken filter use NO filter and pick rows in the app: RLS alone limits them to the
/// signed-in user's own rows (tokens, profiles, follow-ups, notifications), and clinics / doctors are public
/// to every signed-in user anyway.

SupabaseClient get _db => Supabase.instance.client;
String? get _uid => _db.auth.currentUser?.id;

bool _isNetwork(Object e) {
  final s = e.toString();
  return s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed host lookup') ||
      s.contains('Connection refused') ||
      s.contains('XMLHttpRequest error') ||
      e is TimeoutException;
}

// ==================================================================== clinics + doctors

/// Clinics (PRD F-02, DATABASE §4) and doctors (§5). Patients see pilot, active and grace clinics;
/// suspended ones only under Recent.
class SupabaseClinicRepository implements ClinicRepository {
  SupabaseClinicRepository(this._tokens);

  final TokenRepository _tokens;

  static const visibleStatuses = {'pilot', 'active', 'grace'};

  Stream<List<Clinic>> _allClinics() => _db
      .from('clinics')
      .stream(primaryKey: ['id'])
      .map((rows) => Rows.parseAll(rows, Rows.clinic, 'clinic'));

  @override
  Stream<List<String>> watchCities() => _allClinics().map((list) =>
      (list.where((c) => visibleStatuses.contains(c.status.name)).map((c) => c.city).toSet().toList())..sort());

  @override
  Stream<List<Clinic>> watchClinics(String city) => _db
      .from('clinics')
      .stream(primaryKey: ['id'])
      .eq('city', city)
      .map((rows) => Rows.parseAll(rows, Rows.clinic, 'clinic').where((c) => visibleStatuses.contains(c.status.name)).toList()
        ..sort((a, b) => a.name.compareTo(b.name)));

  @override
  Stream<Clinic?> watchClinic(String clinicId) => _db
      .from('clinics')
      .stream(primaryKey: ['id'])
      .map((rows) => Rows.parseAll(rows.where((r) => r['id'] == clinicId), Rows.clinic, 'clinic').firstOrNull);

  /// Clinics the user booked before, latest first, max 5 (PRD F-02); suspended ones included.
  @override
  Stream<List<Clinic>> watchRecentClinics() =>
      _tokens.watchMyTokens().map(_recentIds).distinct((a, b) => a.join(',') == b.join(',')).asyncMap((ids) async {
        if (ids.isEmpty) return const <Clinic>[];
        final rows = await _db.from('clinics').select().inFilter('id', ids);
        final byId = {for (final c in Rows.parseAll(rows, Rows.clinic, 'clinic')) c.id: c};
        return [for (final id in ids) ?byId[id]];
      });

  static List<String> _recentIds(List<Token> tokens) {
    final sorted = [...tokens]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final ids = <String>[];
    for (final t in sorted) {
      if (!ids.contains(t.clinicId)) ids.add(t.clinicId);
    }
    return ids.take(5).toList();
  }

  @override
  Stream<List<Doctor>> watchDoctors(String clinicId) => _db
      .from('doctors')
      .stream(primaryKey: ['id'])
      .eq('clinic_id', clinicId)
      .map((rows) => Rows.parseAll(rows, Rows.doctor, 'doctor').where((d) => d.active).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)));

  @override
  Stream<Doctor?> watchDoctor(String doctorId) => _db
      .from('doctors')
      .stream(primaryKey: ['id'])
      .map((rows) => Rows.parseAll(rows.where((r) => r['id'] == doctorId), Rows.doctor, 'doctor').firstOrNull);

  /// Active doctors grouped by clinic (clinic cards, Doctors search).
  @override
  Stream<Map<String, List<Doctor>>> watchDoctorsByClinic() => _db
      .from('doctors')
      .stream(primaryKey: ['id'])
      .eq('active', true)
      .map((rows) {
        final byClinic = <String, List<Doctor>>{};
        for (final d in Rows.parseAll(rows, Rows.doctor, 'doctor')) {
          byClinic.putIfAbsent(d.clinicId, () => []).add(d);
        }
        for (final list in byClinic.values) {
          list.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        }
        return byClinic;
      });
}

// ==================================================================== queue day

/// `queue_days` (DATABASE §6): numbers only, no personal data. Missing = nothing booked yet.
class SupabaseQueueRepository implements QueueRepository {
  @override
  Stream<QueueDay> watchDay(String doctorId, String date) => _db
      .from('queue_days')
      .stream(primaryKey: ['doctor_id', 'date'])
      .eq('doctor_id', doctorId)
      .map((rows) {
        final row = rows.where((r) => r['date'] == date).firstOrNull;
        if (row == null) return QueueDay.empty('', doctorId, date);
        try {
          return Rows.queueDay(row);
        } catch (e) {
          AppLogger.warn('Bad queue day $doctorId/$date: $e');
          return QueueDay.empty('', doctorId, date);
        }
      });
}

// ==================================================================== tokens

class SupabaseTokenRepository implements TokenRepository {
  SupabaseTokenRepository({Stream<QueueAlert>? alerts}) : _alerts = alerts ?? const Stream.empty();

  final Stream<QueueAlert> _alerts;

  /// Tokens I booked plus walk-ins the clinic made for my family's profiles (D-22), newest first,
  /// the latest 100 of each. The provider restarts this when the signed-in user changes.
  @override
  Stream<List<Token>> watchMyTokens() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    // RLS returns exactly: tokens I booked + tokens on my family's profiles (walk-ins, D-22).
    return _db.from('tokens').stream(primaryKey: ['id']).order('created_at', ascending: false).limit(150).map((rows) {
      final mine = rows.where((r) => r['booked_by_user_id'] == uid || (r['patient_owner_uid'] == uid && r['source'] == 'walkIn'));
      return Rows.parseAll(mine, Rows.token, 'token')..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
  }

  /// My Tokens → Past "Load older" (beyond the live 100).
  @override
  Future<List<Token>> loadOlderTokens(DateTime before, {int limit = 50}) async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      final rows = await _db
          .from('tokens')
          .select()
          .or('booked_by_user_id.eq.$uid,and(patient_owner_uid.eq.$uid,source.eq.walkIn)')
          .lt('created_at', before.toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(limit);
      return Rows.parseAll(rows, Rows.token, 'token');
    } catch (e) {
      if (_isNetwork(e)) throw AppException.noInternet;
      rethrow;
    }
  }

  /// Live token screen: one of my tokens (RLS), changes pushed by Realtime.
  @override
  Stream<Token?> watchToken(String tokenId) => _db
      .from('tokens')
      .stream(primaryKey: ['id'])
      .map((rows) => Rows.parseAll(rows.where((r) => r['id'] == tokenId), Rows.token, 'token').firstOrNull);

  /// FCM pushes that arrive while the app is open (PushService).
  @override
  Stream<QueueAlert> get alerts => _alerts;

  @override
  Future<Token> bookToken({required String clinicId, required String doctorId, required String patientId, required String date}) async {
    final String tokenId;
    try {
      final res = await _db.rpc('book_token', params: {
        'p_clinic_id': clinicId,
        'p_doctor_id': doctorId,
        'p_patient_id': patientId,
        'p_date': date,
      });
      tokenId = (res as Map)['tokenId'] as String;
    } catch (e) {
      throw _bookingError(e);
    }
    try {
      final row = await _db.from('tokens').select().eq('id', tokenId).single();
      return Rows.token(row);
    } catch (e) {
      AppLogger.error('Booked $tokenId but could not read it back', e);
      throw AppException.bookingFailed;
    }
  }

  @override
  Future<void> cancelToken(String tokenId) async {
    try {
      await _db.rpc('cancel_token', params: {'p_token_id': tokenId});
    } catch (e) {
      if (_isNetwork(e)) throw const AppException('network', 'No internet connection. Your token was not cancelled.');
      if (e is PostgrestException && e.message == 'cannot-cancel') {
        throw const AppException('cannot-cancel', 'This token can no longer be cancelled.');
      }
      AppLogger.warn('cancel_token failed: $e');
      throw AppException.generic;
    }
  }

  /// DESIGN.md §7: the function's error code (the exception message) → the message to show.
  static AppException _bookingError(Object e) {
    if (_isNetwork(e)) return AppException.network;
    if (e is! PostgrestException) {
      AppLogger.error('book_token failed', e);
      return AppException.bookingFailed;
    }
    AppLogger.warn('book_token ${e.code}: ${e.message}');
    switch (e.message) {
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
        Map<String, dynamic> d = const {};
        try {
          d = jsonDecode(e.details?.toString() ?? '{}') as Map<String, dynamic>;
        } catch (_) {}
        return AppException.duplicateToken('${d['name'] ?? 'This patient'}', '${d['label'] ?? ''}');
      case 'unauthenticated':
        return AppException.sessionExpired;
    }
    return AppException.bookingFailed;
  }
}

// ==================================================================== family profiles

/// `patients` (PRD F-07). The app may add / edit / soft-delete its own family profiles directly;
/// the database fills owner, phone and status itself and refuses a second Self (RLS + trigger).
class SupabasePatientRepository implements PatientRepository {
  static String _clean(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ');

  static AppException _map(Object e, String fallback) {
    if (_isNetwork(e)) return const AppException('offline', 'No internet connection. Please try again.');
    AppLogger.warn('patients write failed: $e');
    return AppException('patient-write', fallback);
  }

  /// Self first, then in the order they were added.
  @override
  Stream<List<Patient>> watchMyPatients() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db.from('patients').stream(primaryKey: ['id']).map((rows) {
      return Rows.parseAll(rows.where((r) => r['owner_uid'] == uid && r['status'] == 'active'), Rows.patient, 'patient')
        ..sort((a, b) {
          if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
          return a.createdAt.compareTo(b.createdAt);
        });
    });
  }

  @override
  Future<Patient> addPatient({required String name, int? age, required Gender gender, required Relation relation, String? patientPhone}) async {
    if (_uid == null) throw AppException.sessionExpired;
    if (age == null) throw const AppException('age-required', 'Please enter the age.');
    try {
      final row = await _db
          .from('patients')
          .insert({
            'name': _clean(name),
            'birth_year': DateTime.now().year - age,
            'gender': gender.name,
            'relation': relation.name,
            'patient_phone': patientPhone,
          })
          .select()
          .single();
      return Rows.patient(row);
    } catch (e) {
      throw _map(e, 'Could not add this profile. Please try again.');
    }
  }

  /// Editing Self also renames the account (users.name).
  @override
  Future<void> updatePatient(Patient patient, {int? age}) async {
    final uid = _uid;
    if (uid == null) throw AppException.sessionExpired;
    final clean = _clean(patient.name);
    try {
      await _db.from('patients').update({
        'name': clean,
        'birth_year': age == null ? patient.birthYear : DateTime.now().year - age,
        'gender': patient.gender.name,
        'relation': patient.relation.name,
        'patient_phone': patient.patientPhone,
      }).eq('id', patient.id);
      if (patient.isSelf) await _db.from('users').update({'name': clean}).eq('id', uid);
    } catch (e) {
      throw _map(e, 'Could not save changes. Please try again.');
    }
  }

  /// Soft delete (PRD F-07). Self cannot be removed (also refused by the database).
  @override
  Future<void> removePatient(String patientId) async {
    try {
      final row = await _db.from('patients').select('relation').eq('id', patientId).maybeSingle();
      if (row == null || row['relation'] == 'self') throw const AppException('cannot-remove', 'This profile cannot be removed.');
      await _db.from('patients').update({'status': 'deleted'}).eq('id', patientId);
    } on AppException {
      rethrow;
    } catch (e) {
      throw _map(e, 'Could not remove this profile. Please try again.');
    }
  }
}

// ==================================================================== follow-ups

class SupabaseFollowUpRepository implements FollowUpRepository {
  /// Mine, soonest first.
  @override
  Stream<List<FollowUp>> watchMyFollowUps() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db.from('follow_ups').stream(primaryKey: ['id']).map((rows) =>
        Rows.parseAll(rows.where((r) => r['owner_uid'] == uid), Rows.followUp, 'follow-up')..sort((a, b) => a.dueDate.compareTo(b.dueDate)));
  }
}

// ==================================================================== notifications list (D-45)

class SupabaseNotificationRepository implements NotificationRepository {
  /// Newest first, last 30 days (the nightly clean-up deletes older ones).
  @override
  Stream<List<AppNotification>> watchNotifications() {
    final uid = _uid;
    if (uid == null) return Stream.value(const []);
    return _db
        .from('notifications')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(100)
        .map((rows) {
          final since = DateTime.now().subtract(const Duration(days: 30));
          return Rows.parseAll(rows, Rows.notification, 'notification').where((n) => n.createdAt.isAfter(since)).toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        });
  }

  @override
  Stream<DateTime?> watchSeenAt() {
    final uid = _uid;
    if (uid == null) return Stream.value(null);
    return _db.from('users').stream(primaryKey: ['id']).map((rows) {
      final v = rows.where((r) => r['id'] == uid).firstOrNull?['notifications_seen_at'];
      return v is String ? DateTime.tryParse(v) : null;
    });
  }

  @override
  Future<void> markAllSeen() async {
    final uid = _uid;
    if (uid == null) return;
    await _db.from('users').update({'notifications_seen_at': DateTime.now().toUtc().toIso8601String()}).eq('id', uid);
  }
}
