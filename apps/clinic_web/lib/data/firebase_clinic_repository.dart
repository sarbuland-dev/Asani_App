import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/config/firebase_setup.dart';
import '../core/errors/app_exception.dart';
import 'clinic_repository.dart';
import 'models.dart';

/// Real backend (PRD-CLINIC-WEB §10–11): Firebase Auth (email + password,
/// custom-claim roles), Firestore listeners for reads, callable functions for
/// every write (BW-1). Same Firebase project as the patient app, so an app
/// booking shows here within seconds and Next moves the patient's phone.
class FirebaseClinicRepository implements ClinicRepository {
  FirebaseClinicRepository._();

  /// Restores a saved session (stays logged in until Log out, §5.4).
  static Future<FirebaseClinicRepository> create() async {
    final repo = FirebaseClinicRepository._();
    final user = _auth.currentUser ?? await _auth.authStateChanges().first.timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (user != null) {
      try {
        await repo._startSession(user, touch: false);
      } catch (e) {
        AppLogger.warn('Saved session not usable: $e');
        await _auth.signOut();
      }
    }
    _auth.authStateChanges().listen((u) {
      if (u == null && repo._user != null) repo._stopSession(); // disabled / signed out elsewhere
    });
    return repo;
  }

  static FirebaseAuth get _auth => FirebaseAuth.instance;
  static fs.FirebaseFirestore get _db => fs.FirebaseFirestore.instance;
  static FirebaseFunctions get _fn => FirebaseFunctions.instanceFor(region: firebaseRegion);

  final _changes = StreamController<void>.broadcast();
  final _subs = <String, StreamSubscription<dynamic>>{};
  Timer? _notifyTimer;

  UserAccount? _user;
  String _today = dayKey(pktNow());

  // ---- cache ----
  final _clinicDocs = <String, Map<String, dynamic>>{};
  final _billing = <String, Map<String, dynamic>>{};
  final _doctors = <String, Doctor>{};
  final _addedAt = <String, DateTime>{};
  final _hasPmdc = <String>{}; // doctors with a PMDC number on file (D-33: never the number)
  final _suggestions = <String, LinkSuggestion>{}; // D-32, Super Admin only
  final _pmdc = <String, String>{}; // doctorId → PMDC, Super Admin only
  final _days = <String, QueueDay>{}; // doctorId|date
  final _undoAt = <String, DateTime>{}; // doctorId → last Next
  final _tokens = <String, QueueToken>{};
  final _byClinicDate = <String, Set<String>>{}; // clinicId|date → ids
  final _loadedDates = <String>{}; // clinicId|date loaded (listener or one-shot)
  final _patients = <String, Patient>{};
  final _patientHistory = <String, List<String>>{}; // clinicId|patientId → token ids
  final _loadingPatients = <String>{};
  final _searches = <String, List<String>>{}; // clinicId|query → patient ids
  final _lookups = <String, PhoneLookup>{}; // clinicId|phone → D-22 lookup
  final _followUps = <String, FollowUp>{};
  final _logins = <String, UserAccount>{}; // clinicId → login
  final _invoices = <String, Invoice>{};
  final _activity = <ActivityLog>[];
  final _stats = <String, (int, int)>{}; // clinicId → this month (app, walk-in)
  AdminSettings _settings = const AdminSettings();

  void _notify() {
    // Coalesce bursts of snapshot events into one rebuild.
    _notifyTimer ??= Timer(const Duration(milliseconds: 40), () {
      _notifyTimer = null;
      if (!_changes.isClosed) _changes.add(null);
    });
  }

  void _watch<T>(String key, Stream<T> stream, void Function(T) onData) {
    if (_subs.containsKey(key)) return;
    _subs[key] = stream.listen(onData, onError: (Object e) {
      AppLogger.warn('listener $key: $e');
      _subs.remove(key);
    });
  }

  void _unwatch(String key) => _subs.remove(key)?.cancel();

  // ===================================================================
  // Mapping Firestore → models
  // ===================================================================

  static DateTime? _date(Object? v) => v is fs.Timestamp ? v.toDate() : (v is DateTime ? v : null);

  /// Timestamps → epoch ms, so the shared models' fromMap can read them.
  static Object? _plain(Object? v) {
    if (v is fs.Timestamp) return v.millisecondsSinceEpoch;
    if (v is fs.GeoPoint) return {'lat': v.latitude, 'lng': v.longitude};
    if (v is Map) return {for (final e in v.entries) e.key as String: _plain(e.value)};
    if (v is List) return v.map(_plain).toList();
    return v;
  }

  static Map<String, Object?> _map(fs.DocumentSnapshot<Map<String, dynamic>> d) =>
      {...(_plain(d.data() ?? {}) as Map<String, Object?>), 'id': d.id};

  static Clinic _clinicFrom(String id, Map<String, dynamic> raw) {
    final m = _plain(raw) as Map<String, Object?>;
    return Clinic.fromMap({
      'id': id,
      'name': m['name'] ?? '',
      'area': m['area'] ?? '',
      'city': m['city'] ?? '',
      'address': m['address'] ?? '',
      'phone': m['phone'] ?? '',
      'location': m['location'],
      'status': m['status'],
      'doctorCount': (m['doctorCount'] as num?)?.toInt() ?? 0,
    });
  }

  static Plan _plan(Object? v) => Plan.values.where((p) => p.name == v).firstOrNull ?? Plan.pilot;
  static PrintFormat _print(Object? v) => PrintFormat.values.where((p) => p.name == v).firstOrNull ?? PrintFormat.thermal80;

  ClinicAccount? _account(String id) {
    final c = _clinicDocs[id];
    if (c == null) return null;
    final b = _billing[id] ?? const {};
    final login = _logins[id];
    return ClinicAccount(
      clinic: _clinicFrom(id, c),
      email: (b['email'] as String?) ?? login?.email ?? '',
      ownerName: (b['ownerName'] as String?) ?? login?.name ?? '',
      ownerPhone: (b['ownerPhone'] as String?) ?? '',
      plan: _plan(b['plan']),
      planAfterPilot: b['planAfterPilot'] == 'premium' ? Plan.premium : Plan.basic,
      monthlyFee: (b['monthlyFee'] as num?)?.toInt() ?? 0,
      billingDay: (b['billingDay'] as num?)?.toInt() ?? 1,
      paidUntil: _date(b['paidUntil']),
      pilotEndsAt: _date(b['pilotEndsAt']),
      printFormat: _print(c['printFormat']),
      createdAt: _date(c['createdAt']) ?? DateTime(2026),
      nextDoctorLetter: (c['nextDoctorLetter'] as num?)?.toInt() ?? 0,
    );
  }

  static Doctor _doctorFrom(fs.DocumentSnapshot<Map<String, dynamic>> d) {
    final m = _map(d);
    return Doctor.fromMap({
      ...m,
      'name': m['name'] ?? '',
      'speciality': m['speciality'] ?? '',
      'clinicId': m['clinicId'] ?? '',
      'avgConsultMinutes': (m['avgConsultMinutes'] as num?)?.toInt(),
      'maxTokensPerDay': (m['maxTokensPerDay'] as num?)?.toInt(),
      'bookingWindowDays': (m['bookingWindowDays'] as num?)?.toInt(),
      'sortOrder': (m['sortOrder'] as num?)?.toInt(),
    });
  }

  static QueueDay _dayFrom(String clinicId, String doctorId, String date, Map<String, dynamic>? raw) {
    if (raw == null) return QueueDay.empty(clinicId, doctorId, date);
    final m = _plain(raw) as Map<String, Object?>;
    return QueueDay(
      clinicId: clinicId,
      doctorId: doctorId,
      date: date,
      sessionStatus: SessionStatus.parse(m['sessionStatus']),
      currentToken: (m['currentToken'] as num?)?.toInt() ?? 0,
      lastTokenNumber: (m['lastTokenNumber'] as num?)?.toInt() ?? 0,
      activeNumbers: ((m['activeNumbers'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
      bookedCount: (m['bookedCount'] as num?)?.toInt() ?? 0,
    );
  }

  static QueueToken _tokenFrom(fs.DocumentSnapshot<Map<String, dynamic>> d) {
    final raw = d.data() ?? {};
    final m = _map(d);
    final snap = Map<String, Object?>.from((m['patientSnapshot'] as Map?) ?? const {});
    final token = Token.fromMap({
      ...m,
      'number': (m['number'] as num?)?.toInt() ?? 0,
      'patientSnapshot': {...snap, 'name': snap['name'] ?? '', 'phone': snap['phone'] ?? '', 'birthYear': (snap['birthYear'] as num?)?.toInt()},
      'notified': const <String>[], // the clinic never needs the notification steps
    });
    return QueueToken(
      token: token,
      source: raw['source'] == 'walkIn' ? TokenSource.walkIn : TokenSource.app,
      arrivedAt: _date(raw['arrivedAt']),
      cancelReason: raw['cancelReason'] as String?,
      history: [
        for (final h in (raw['history'] as List?) ?? const [])
          if (h is Map) TokenEvent('${h['action'] ?? ''}', '${h['by'] ?? ''}', _date(h['at']) ?? DateTime.now(), note: h['note'] as String?),
      ],
    );
  }

  static Patient _patientFrom(fs.DocumentSnapshot<Map<String, dynamic>> d) {
    final m = _map(d);
    return Patient.fromMap({...m, 'phone': m['phone'] ?? '', 'name': m['name'] ?? '', 'birthYear': (m['birthYear'] as num?)?.toInt()});
  }

  static FollowUp _followUpFrom(fs.DocumentSnapshot<Map<String, dynamic>> d) {
    final m = _map(d);
    return FollowUp.fromMap({...m, 'ownerUid': m['ownerUid'] ?? ''});
  }

  static UserAccount _loginFrom(fs.DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    return UserAccount(
      uid: d.id,
      name: (m['name'] as String?) ?? '',
      email: (m['email'] as String?) ?? '',
      role: UserRole.clinic,
      clinicId: m['clinicId'] as String?,
      status: LoginStatus.values.where((s) => s.name == m['status']).firstOrNull ?? LoginStatus.invited,
      createdAt: _date(m['createdAt']) ?? DateTime.now(),
      invitedAt: _date(m['invitedAt']),
      lastLoginAt: _date(m['lastLoginAt']),
      passwordChangedAt: _date(m['passwordChangedAt']),
    );
  }

  static Invoice _invoiceFrom(fs.DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final p = m['payment'] as Map?;
    return Invoice(
      id: d.id,
      clinicId: (m['clinicId'] as String?) ?? '',
      month: (m['month'] as String?) ?? '',
      amount: (m['amount'] as num?)?.toInt() ?? 0,
      dueDate: _date(m['dueDate']) ?? DateTime.now(),
      status: InvoiceStatus.values.where((s) => s.name == m['status']).firstOrNull ?? InvoiceStatus.unpaid,
      waiveReason: m['waiveReason'] as String?,
      payment: p == null
          ? null
          : Payment(
              amount: (p['amount'] as num?)?.toInt() ?? 0,
              method: PaymentMethod.values.where((x) => x.name == p['method']).firstOrNull ?? PaymentMethod.cash,
              reference: p['reference'] as String?,
              date: _date(p['date']) ?? DateTime.now(),
              recordedBy: (p['recordedBy'] as String?) ?? '',
            ),
    );
  }

  static ActivityLog _logFrom(fs.DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? {};
    final a = (m['actor'] as Map?) ?? const {};
    return ActivityLog(
      id: d.id,
      clinicId: m['clinicId'] as String?,
      actorName: (a['name'] as String?) ?? 'System',
      actorRole: a['role'] == 'clinic' ? UserRole.clinic : UserRole.superAdmin,
      action: (m['action'] as String?) ?? '',
      target: (m['target'] as String?) ?? '',
      at: _date(m['at']) ?? DateTime.now(),
    );
  }

  static AdminSettings _settingsFrom(Map<String, dynamic>? m) {
    if (m == null) return const AdminSettings();
    final p = (m['prices'] as Map?) ?? const {};
    int n(Object? v, int d) => (v as num?)?.toInt() ?? d;
    const def = AdminSettings();
    return AdminSettings(
      prices: {for (final plan in Plan.values) plan: n(p[plan.name], def.prices[plan] ?? 0)},
      pilotDays: n(m['pilotDays'], def.pilotDays),
      billingDay: n(m['billingDay'], def.billingDay),
      dueDays: n(m['dueDays'], def.dueDays),
      graceDays: n(m['graceDays'], def.graceDays),
      suspendDays: n(m['suspendDays'], def.suspendDays),
      paymentInstructions: (m['paymentInstructions'] as String?) ?? def.paymentInstructions,
    );
  }

  // ===================================================================
  // Session
  // ===================================================================

  Future<void> _startSession(User user, {required bool touch}) async {
    final claims = (await user.getIdTokenResult(true)).claims ?? const {};
    final role = claims['role'];
    if (role == 'clinic' && claims['clinicId'] is String) {
      final clinicId = claims['clinicId'] as String;
      final acc = await _db.collection('clinicAccounts').doc(user.uid).get();
      final login = _loginFrom(acc);
      if (login.status == LoginStatus.disabled) throw AppException.disabled;
      _user = UserAccount(
        uid: user.uid,
        name: login.name,
        email: user.email ?? login.email,
        role: UserRole.clinic,
        clinicId: clinicId,
        status: LoginStatus.active,
        createdAt: login.createdAt,
        lastLoginAt: DateTime.now(),
        passwordChangedAt: login.passwordChangedAt,
      );
      _watchClinic(clinicId, own: true);
      if (touch) unawaited(_call('clinicLoginTouch', const {}).then((_) {}, onError: (Object _) {}));
    } else if (role == 'superAdmin') {
      _user = UserAccount(uid: user.uid, name: user.displayName ?? 'Super Admin', email: user.email ?? '', role: UserRole.superAdmin, createdAt: DateTime.now());
      final admin = await _db.collection('adminUsers').doc(user.uid).get();
      final name = admin.data()?['name'] as String?;
      if (name != null) _user = UserAccount(uid: user.uid, name: name, email: user.email ?? '', role: UserRole.superAdmin, createdAt: DateTime.now());
      _watchAdmin();
    } else {
      throw const AppException('no-access', "This account doesn't have clinic access.");
    }
    _notify();
  }

  void _stopSession() {
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    for (final m in <Map<dynamic, dynamic>>[_clinicDocs, _billing, _doctors, _addedAt, _days, _undoAt, _tokens, _byClinicDate, _patients, _patientHistory, _searches, _lookups, _followUps, _logins, _invoices, _stats]) {
      m.clear();
    }
    _loadedDates.clear();
    _activity.clear();
    _user = null;
    _notify();
  }

  /// Live data a clinic needs (own clinic), or a read-only view for the admin.
  void _watchClinic(String clinicId, {bool own = false}) {
    final clinicRef = _db.collection('clinics').doc(clinicId);
    _watch('clinic/$clinicId', clinicRef.snapshots(), (d) {
      if (d.data() != null) _clinicDocs[clinicId] = d.data()!;
      _notify();
    });
    _watch('billing/$clinicId', clinicRef.collection('private').doc('billing').snapshots(), (d) {
      if (d.data() != null) _billing[clinicId] = d.data()!;
      _notify();
    });
    _watch('doctors/$clinicId', _db.collection('doctors').where('clinicId', isEqualTo: clinicId).snapshots(), (q) {
      _doctors.removeWhere((_, d) => d.clinicId == clinicId);
      for (final d in q.docs) {
        _doctors[d.id] = _doctorFrom(d);
        if (d.data()['hasPmdc'] == true) {
          _hasPmdc.add(d.id);
        } else {
          _hasPmdc.remove(d.id);
        }
        final at = _date(d.data()['createdAt']);
        if (at != null) _addedAt[d.id] = at;
      }
      _watchToday(clinicId);
      _notify();
    });
    _watchToday(clinicId);
    if (!own) return;
    _watch('followUps/$clinicId', _db.collection('followUps').where('clinicId', isEqualTo: clinicId).snapshots(), (q) {
      _followUps
        ..clear()
        ..addEntries(q.docs.map((d) => MapEntry(d.id, _followUpFrom(d))));
      _notify();
    });
    _watch('invoices/$clinicId', _db.collection('invoices').where('clinicId', isEqualTo: clinicId).snapshots(), (q) {
      _invoices
        ..clear()
        ..addEntries(q.docs.map((d) => MapEntry(d.id, _invoiceFrom(d))));
      _notify();
    });
    _watch('activity/$clinicId', _db.collection('activityLogs').where('clinicId', isEqualTo: clinicId).orderBy('at', descending: true).limit(200).snapshots(), (q) {
      _activity
        ..clear()
        ..addAll(q.docs.map(_logFrom));
      _notify();
    });
    _watch('settings', _db.collection('settings').doc('billing').snapshots(), (d) {
      _settings = _settingsFrom(d.data());
      _notify();
    });
    _watch('login/${_user!.uid}', _db.collection('clinicAccounts').doc(_user!.uid).snapshots(), (d) {
      _logins[clinicId] = _loginFrom(d);
      _notify();
    });
  }

  /// Today's tokens + each doctor's queue day for a clinic (live).
  void _watchToday(String clinicId) {
    final today = dayKey(pktNow());
    if (today != _today) {
      // Midnight PKT: move every "today" listener to the new date.
      for (final k in _subs.keys.where((k) => k.startsWith('today/') || k.startsWith('day/')).toList()) {
        _unwatch(k);
      }
      _loadedDates.removeWhere((k) => k.endsWith('|$_today'));
      _today = today;
    }
    final key = '$clinicId|$today';
    _loadedDates.add(key);
    _watch('today/$clinicId', _db.collection('tokens').where('clinicId', isEqualTo: clinicId).where('date', isEqualTo: today).snapshots(), (q) {
      _putTokens(key, q.docs);
    });
    for (final d in _doctors.values.where((d) => d.clinicId == clinicId)) {
      _watch('day/${d.id}', _db.collection('doctors').doc(d.id).collection('days').doc(today).snapshots(), (s) {
        _days['${d.id}|$today'] = _dayFrom(clinicId, d.id, today, s.data());
        final undo = s.data()?['undo'] as Map?;
        final at = _date(undo?['at']);
        if (at != null) {
          _undoAt[d.id] = at;
        } else {
          _undoAt.remove(d.id);
        }
        _notify();
      });
    }
  }

  void _putTokens(String key, List<fs.QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final ids = _byClinicDate.putIfAbsent(key, () => <String>{});
    for (final id in ids) {
      _tokens.remove(id);
    }
    ids.clear();
    for (final d in docs) {
      _tokens[d.id] = _tokenFrom(d);
      ids.add(d.id);
    }
    _notify();
  }

  void _watchAdmin() {
    _watch('clinics', _db.collection('clinics').snapshots(), (q) {
      _clinicDocs
        ..clear()
        ..addEntries(q.docs.map((d) => MapEntry(d.id, d.data())));
      final month = dayKey(pktNow()).substring(0, 7);
      for (final c in q.docs) {
        _watch('billing/${c.id}', c.reference.collection('private').doc('billing').snapshots(), (d) {
          if (d.data() != null) _billing[c.id] = d.data()!;
          _notify();
        });
        _watch('stats/${c.id}/$month', c.reference.collection('stats').doc(month).snapshots(), (d) {
          final m = d.data() ?? const {};
          _stats[c.id] = ((m['app'] as num?)?.toInt() ?? 0, (m['walkIn'] as num?)?.toInt() ?? 0);
          _notify();
        });
      }
      _notify();
    });
    _watch('doctors', _db.collection('doctors').snapshots(), (q) {
      _doctors.clear();
      for (final d in q.docs) {
        _doctors[d.id] = _doctorFrom(d);
        if (d.data()['hasPmdc'] == true) {
          _hasPmdc.add(d.id);
        } else {
          _hasPmdc.remove(d.id);
        }
        final at = _date(d.data()['createdAt']);
        if (at != null) _addedAt[d.id] = at;
      }
      _notify();
    });
    _watch('logins', _db.collection('clinicAccounts').snapshots(), (q) {
      _logins.clear();
      for (final d in q.docs) {
        final l = _loginFrom(d);
        if (l.clinicId != null) _logins[l.clinicId!] = l;
      }
      _notify();
    });
    _watch('invoices', _db.collection('invoices').snapshots(), (q) {
      _invoices
        ..clear()
        ..addEntries(q.docs.map((d) => MapEntry(d.id, _invoiceFrom(d))));
      _notify();
    });
    _watch('activity', _db.collection('activityLogs').orderBy('at', descending: true).limit(500).snapshots(), (q) {
      _activity
        ..clear()
        ..addAll(q.docs.map(_logFrom));
      _notify();
    });
    _watch('settings', _db.collection('settings').doc('billing').snapshots(), (d) {
      _settings = _settingsFrom(d.data());
      _notify();
    });
    // D-32 / A-09: same-doctor suggestions and the PMDC numbers they show.
    _watch('linkSuggestions', _db.collection('doctorLinkSuggestions').snapshots(), (q) {
      _suggestions
        ..clear()
        ..addEntries(q.docs.map((d) => MapEntry(d.id, _suggestionFrom(d))));
      for (final s in _suggestions.values) {
        for (final id in s.doctorIds) {
          _watch('pmdc/$id', _db.collection('doctors').doc(id).collection('private').doc('admin').snapshots(), (d) {
            final n = d.data()?['pmdcNumber'] as String?;
            if (n == null) {
              _pmdc.remove(id);
            } else {
              _pmdc[id] = n;
            }
            _notify();
          });
        }
      }
      _notify();
    });
  }

  static LinkSuggestion _suggestionFrom(fs.DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return LinkSuggestion(
      pairId: d.id,
      doctorIds: [for (final x in (m['doctorIds'] as List? ?? const [])) '$x'],
      clinicIds: [for (final x in (m['clinicIds'] as List? ?? const [])) '$x'],
      strength: m['strength'] == 'strong' ? LinkStrength.strong : LinkStrength.weak,
      status: LinkStatus.values.firstWhere((x) => x.name == m['status'], orElse: () => LinkStatus.open),
      createdAt: _date(m['createdAt']) ?? DateTime(2026),
    );
  }

  // ===================================================================
  // Auth
  // ===================================================================

  @override
  Stream<void> get changes => _changes.stream;

  @override
  UserAccount? get currentUser => _user;

  static AppException _authError(FirebaseAuthException e) => switch (e.code) {
        'user-disabled' => AppException.disabled,
        'too-many-requests' => AppException.tooManyAttempts,
        'network-request-failed' => AppException.offline,
        _ => AppException.wrongLogin, // never reveal which part is wrong (§5.3)
      };

  @override
  Future<UserAccount> signIn(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email.trim(), password: password);
      await _startSession(cred.user!, touch: true);
      return _user!;
    } on FirebaseAuthException catch (e) {
      throw _authError(e);
    } on AppException {
      await _auth.signOut();
      rethrow;
    }
  }

  @override
  Future<void> signOut() async {
    _stopSession();
    await _auth.signOut();
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      // "If this email is registered, you'll get a link": don't reveal unknown emails.
      if (e.code != 'user-not-found' && e.code != 'invalid-email') throw _authError(e);
    }
  }

  @override
  Future<void> changePassword(String current, String next) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) throw AppException.notAllowed;
    try {
      await user.reauthenticateWithCredential(EmailAuthProvider.credential(email: user.email!, password: current));
      await user.updatePassword(next);
      await _call('clinicPasswordChanged', const {}); // signs out other computers
      // Our own refresh token was revoked too: sign in again with the new password.
      await _auth.signInWithEmailAndPassword(email: user.email!, password: next);
    } on FirebaseAuthException catch (e) {
      throw switch (e.code) {
        'wrong-password' || 'invalid-credential' => const AppException('wrong-password', 'Current password is incorrect.'),
        'weak-password' => const AppException('weak-password', 'The new password needs at least 8 characters.'),
        _ => _authError(e),
      };
    }
  }

  // ===================================================================
  // Functions
  // ===================================================================

  Future<Map<String, dynamic>> _call(String name, Map<String, Object?> data) async {
    try {
      final r = await _fn.httpsCallable(name, options: HttpsCallableOptions(timeout: const Duration(seconds: 30))).call<Object?>(data);
      final v = r.data;
      return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      AppLogger.warn('$name failed: ${e.code} ${e.message}');
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') throw AppException.offline;
      if (e.code == 'internal' || e.message == null) throw AppException.generic;
      throw AppException(e.code, e.message!);
    }
  }

  // ===================================================================
  // Reads
  // ===================================================================

  @override
  ClinicAccount? clinic(String clinicId) {
    if (_user?.role == UserRole.superAdmin && !_clinicDocs.containsKey(clinicId)) _watchClinic(clinicId);
    return _account(clinicId);
  }

  @override
  List<ClinicAccount> clinics() => [for (final id in _clinicDocs.keys) ?_account(id)]..sort((a, b) => a.clinic.name.compareTo(b.clinic.name));

  @override
  List<Doctor> doctors(String clinicId, {bool includeInactive = false}) =>
      _doctors.values.where((d) => d.clinicId == clinicId && (includeInactive || d.active)).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  QueueDay queueDay(String clinicId, String doctorId, String date) {
    if (date == dayKey(pktNow())) _watchToday(clinicId);
    return _days['$doctorId|$date'] ?? QueueDay.empty(clinicId, doctorId, date);
  }

  @override
  List<QueueToken> tokens(String clinicId, String date) {
    final key = '$clinicId|$date';
    if (date == dayKey(pktNow())) {
      _watchToday(clinicId); // super admin "View queue" too
    } else if (_loadedDates.add(key)) {
      unawaited(_loadDate(clinicId, date));
    }
    return [for (final id in _byClinicDate[key] ?? const <String>{}) ?_tokens[id]];
  }

  Future<void> _loadDate(String clinicId, String date) async {
    try {
      final q = await _db.collection('tokens').where('clinicId', isEqualTo: clinicId).where('date', isEqualTo: date).get();
      _putTokens('$clinicId|$date', q.docs);
    } catch (e) {
      _loadedDates.remove('$clinicId|$date');
      AppLogger.warn('load tokens $date: $e');
    }
  }

  @override
  Future<List<QueueToken>> loadTokens(String clinicId, String from, String to) async {
    final q = await _db
        .collection('tokens')
        .where('clinicId', isEqualTo: clinicId)
        .where('date', isGreaterThanOrEqualTo: from)
        .where('date', isLessThanOrEqualTo: to)
        .get();
    return q.docs.map(_tokenFrom).toList();
  }

  @override
  QueueToken? tokenById(String id) => _tokens[id];

  @override
  Patient? patient(String id) => _patients[id];

  @override
  CodeLookup findByCode(String clinicId, String code) {
    final parsed = TokenCode.parse(code);
    if (parsed == null) return const CodeLookup();
    final (:letter, :number) = parsed;
    bool matches(QueueToken t) => t.number == number && (letter.isEmpty || t.token.tokenPrefix == letter);
    // BW-5: only today's tokens of this clinic.
    final today = tokens(clinicId, dayKey(pktNow())).where(matches).toList();
    if (letter.isEmpty && doctors(clinicId, includeInactive: true).length > 1 && today.length > 1) return CodeLookup(ambiguous: today);
    if (today.isNotEmpty) return CodeLookup(token: today.first);
    // Another day: only what is already loaded (the patient's slip shows the date).
    QueueToken? other;
    for (final t in _tokens.values) {
      if (t.token.clinicId == clinicId && matches(t) && t.status.isActive && t.token.date != dayKey(pktNow())) other ??= t;
    }
    return CodeLookup(otherDate: other);
  }

  @override
  List<ClinicPatient> searchPatients(String clinicId, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final key = '$clinicId|$q';
    final ids = _searches[key];
    if (ids == null) {
      _searches[key] = const [];
      unawaited(_runSearch(clinicId, q, key));
      return const [];
    }
    return [
      for (final id in ids)
        if (_patients[id] != null) clinicPatient(clinicId, id) ?? ClinicPatient(patient: _patients[id]!, visits: const []),
    ];
  }

  Future<void> _runSearch(String clinicId, String q, String key) async {
    try {
      final base = _db.collection('patients').where('clinicIds', arrayContains: clinicId);
      var local = q.replaceAll(RegExp(r'[^0-9]'), '');
      if (local.startsWith('92') && local.length > 10) local = local.substring(2);
      while (local.startsWith('0')) {
        local = local.substring(1);
      }
      fs.QuerySnapshot<Map<String, dynamic>> snap;
      if (local.length >= 3) {
        // Phone: prefix match on "+92…" (full numbers are exact).
        final prefix = '+92$local';
        snap = await base.where('phone', isGreaterThanOrEqualTo: prefix).where('phone', isLessThan: '$prefix').limit(60).get();
      } else {
        snap = await base.where('nameLower', isGreaterThanOrEqualTo: q).where('nameLower', isLessThan: '$q').limit(60).get();
      }
      final ids = <String>[];
      for (final d in snap.docs) {
        final p = _patientFrom(d);
        if (p.status != PatientStatus.active) continue;
        _patients[d.id] = p;
        ids.add(d.id);
        unawaited(_loadHistory(clinicId, d.id));
      }
      _searches[key] = ids;
      _notify();
    } catch (e) {
      _searches.remove(key);
      AppLogger.warn('search: $e');
    }
  }

  @override
  bool isLoadingPatient(String patientId) => _loadingPatients.contains(patientId);

  @override
  ClinicPatient? clinicPatient(String clinicId, String patientId) {
    final key = '$clinicId|$patientId';
    final history = _patientHistory[key];
    if (history == null) {
      unawaited(_loadHistory(clinicId, patientId));
      final p = _patients[patientId];
      return p == null ? null : ClinicPatient(patient: p, visits: const []);
    }
    final p = _patients[patientId];
    if (p == null) return null;
    final visits = [for (final id in history) ?_tokens[id]]
      ..sort((a, b) {
        final d = b.token.date.compareTo(a.token.date);
        return d != 0 ? d : b.number.compareTo(a.number);
      });
    return ClinicPatient(
      patient: p,
      visits: visits,
      followUps: _followUps.values.where((f) => f.clinicId == clinicId && f.patientId == patientId).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate)),
    );
  }

  Future<void> _loadHistory(String clinicId, String patientId) async {
    final key = '$clinicId|$patientId';
    if (_patientHistory.containsKey(key) || !_loadingPatients.add(patientId)) return;
    try {
      final results = await Future.wait([
        _db.collection('patients').doc(patientId).get(),
        _db.collection('tokens').where('clinicId', isEqualTo: clinicId).where('patientId', isEqualTo: patientId).orderBy('date', descending: true).limit(100).get(),
      ]);
      final p = results[0] as fs.DocumentSnapshot<Map<String, dynamic>>;
      final t = results[1] as fs.QuerySnapshot<Map<String, dynamic>>;
      if (p.exists) _patients[patientId] = _patientFrom(p);
      for (final d in t.docs) {
        // Today's live copies win over this one-shot read.
        _tokens.putIfAbsent(d.id, () => _tokenFrom(d));
      }
      _patientHistory[key] = t.docs.map((d) => d.id).toList();
    } catch (e) {
      AppLogger.warn('history $patientId: $e');
    } finally {
      _loadingPatients.remove(patientId);
      _notify();
    }
  }

  @override
  Future<ClinicPatient?> loadClinicPatient(String clinicId, String patientId) async {
    _patientHistory.remove('$clinicId|$patientId'); // fresh visit count for printing
    await _loadHistory(clinicId, patientId);
    return clinicPatient(clinicId, patientId);
  }

  @override
  List<FollowUp> followUps(String clinicId) =>
      _followUps.values.where((f) => f.clinicId == clinicId).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  @override
  UserAccount? clinicLogin(String clinicId) => _logins[clinicId];

  @override
  List<Invoice> invoices({String? clinicId}) => _invoices.values.where((i) => clinicId == null || i.clinicId == clinicId).toList()
    ..sort((a, b) {
      final m = b.month.compareTo(a.month);
      return m != 0 ? m : a.clinicId.compareTo(b.clinicId);
    });

  @override
  List<ActivityLog> activity({String? clinicId}) => _activity.where((a) => clinicId == null || a.clinicId == clinicId).toList();

  @override
  AdminSettings get settings => _settings;

  @override
  Map<String, DateTime> doctorAddedAt() => Map.unmodifiable(_addedAt);

  @override
  bool canUndoNext(String doctorId) {
    final at = _undoAt[doctorId];
    return at != null && DateTime.now().difference(at).inSeconds < 30;
  }

  @override
  (int, int) monthTokens({String? clinicId}) {
    if (clinicId != null) return _stats[clinicId] ?? (0, 0);
    var app = 0, walk = 0;
    for (final s in _stats.values) {
      app += s.$1;
      walk += s.$2;
    }
    return (app, walk);
  }

  // ===================================================================
  // Queue writes (all through functions, BW-1)
  // ===================================================================

  @override
  Future<void> session(String clinicId, String doctorId, SessionAction action) =>
      _call('queueAction', {'action': action.name, 'doctorId': doctorId});

  @override
  Future<CalledInfo?> next(String clinicId, String doctorId, {String? callNotArrived}) async {
    final Map<String, dynamic> r;
    try {
      final res = await _fn
          .httpsCallable('queueAction', options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
          .call<Object?>({'action': 'next', 'doctorId': doctorId, 'callNotArrived': ?callNotArrived});
      r = res.data is Map ? Map<String, dynamic>.from(res.data! as Map) : <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      final d = e.details;
      if (d is Map && d['code'] == 'not-arrived') throw NotArrived('${d['tokenId']}', '${d['label']}', '${d['name'] ?? ''}');
      AppLogger.warn('queueAction next failed: ${e.code} ${e.message}');
      if (e.code == 'unavailable' || e.code == 'deadline-exceeded') throw AppException.offline;
      if (e.code == 'internal' || e.message == null) throw AppException.generic;
      throw AppException(e.code, e.message!);
    }
    final c = r['called'] as Map?;
    return c == null ? null : CalledInfo('${c['label']}', '${c['name']}');
  }

  @override
  Future<void> undoNext(String doctorId) => _call('queueAction', {'action': 'undo', 'doctorId': doctorId});

  @override
  Future<void> tokenAction(String tokenId, TokenAction action, {String? reason}) => _call('queueAction', {
        'action': switch (action) {
          TokenAction.arrive => 'arrive',
          TokenAction.callNow => 'callNow',
          TokenAction.skip => 'skip',
          TokenAction.hold => 'hold',
          TokenAction.backToQueue => 'backToQueue',
          TokenAction.cancel => 'cancel',
          TokenAction.noShow => 'noShow',
          TokenAction.reprint => 'reprint',
        },
        'tokenId': tokenId,
        'reason': ?reason,
      });

  /// Waits until a token written by a function reaches the live cache.
  Future<QueueToken> _awaitToken(String id) async {
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (_tokens[id] == null && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    final t = _tokens[id];
    if (t != null) return t;
    final d = await _db.collection('tokens').doc(id).get();
    return _tokenFrom(d);
  }

  @override
  PhoneLookup lookupPhone(String clinicId, String phone) {
    final key = '$clinicId|$phone';
    final hit = _lookups[key];
    if (hit != null) return hit;
    _lookups[key] = const PhoneLookup.loading();
    unawaited(() async {
      try {
        final r = await _call('clinicLookupPhone', {'phone': phone});
        final list = (r['profiles'] as List? ?? const [])
            .whereType<Map<Object?, Object?>>()
            .map((m) => PhoneProfile(
                  id: '${m['id']}',
                  name: '${m['name'] ?? ''}',
                  relation: Relation.parse(m['relation']),
                  gender: Gender.parse(m['gender']),
                  age: (m['age'] as num?)?.toInt(),
                  atThisClinic: m['atThisClinic'] == true,
                ))
            .toList();
        _lookups[key] = PhoneLookup.done(list);
      } on AppException catch (e) {
        _lookups[key] = PhoneLookup.failed(e.message);
        // Let a later retry ask again (e.g. after the rate limit window).
        Timer(const Duration(seconds: 30), () => _lookups.remove(key));
      }
      _notify();
    }());
    return const PhoneLookup.loading();
  }

  @override
  Future<QueueToken> createWalkIn(String clinicId, String doctorId, {String? patientId, String? phone, NewPatient? newPatient}) async {
    final r = await _call('clinicCreateWalkIn', {
      'doctorId': doctorId,
      'patientId': ?patientId,
      if (patientId != null) 'phone': ?phone,
      if (newPatient != null)
        'newPatient': {
          'phone': newPatient.phone,
          'name': newPatient.name.trim(),
          'age': newPatient.age,
          'gender': newPatient.gender.name,
          'relation': newPatient.relation.name,
        },
    });
    _searches.clear(); // the new patient should show up in searches
    _lookups.clear(); // a looked-up profile is now at this clinic
    return _awaitToken('${r['tokenId']}');
  }

  @override
  Future<void> setFollowUp(String tokenId, String dueDate, {String? note}) =>
      _call('setFollowUp', {'tokenId': tokenId, 'dueDate': dueDate, 'note': note});

  @override
  Future<void> updatePatient(String clinicId, String patientId, {required String name, int? birthYear, required Gender gender}) async {
    await _call('clinicUpdatePatient', {
      'patientId': patientId,
      'name': name.trim(),
      'gender': gender.name,
      'age': birthYear == null ? null : DateTime.now().year - birthYear,
    });
    _patientHistory.remove('$clinicId|$patientId');
    await _loadHistory(clinicId, patientId);
  }

  // ===================================================================
  // Clinic login: doctors, settings
  // ===================================================================

  @override
  Future<Doctor> saveDoctor(String clinicId, Doctor doctor, {bool isNew = false, String? pmdcNumber}) async {
    final r = await _call('saveDoctor', {
      'pmdcNumber': ?pmdcNumber, // D-33: server stores it admin-only
      if (!isNew) 'doctorId': doctor.id,
      'name': doctor.name.trim(),
      'speciality': doctor.speciality.trim(),
      'qualification': doctor.qualification,
      'avgConsultMinutes': doctor.avgConsultMinutes,
      'maxTokensPerDay': doctor.maxTokensPerDay,
      'bookingWindowDays': doctor.bookingWindowDays,
      'schedule': {for (final e in doctor.schedule.entries) e.key: e.value?.toMap()},
    });
    return _doctors['${r['doctorId']}'] ?? doctor;
  }

  @override
  Future<int> addLeave(String doctorId, String date) async {
    final r = await _call('setDoctorLeave', {'doctorId': doctorId, 'date': date, 'add': true});
    return (r['activeTokens'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> removeLeave(String doctorId, String date) => _call('setDoctorLeave', {'doctorId': doctorId, 'date': date, 'add': false});

  @override
  Future<int> cancelTokensOn(String doctorId, String date, String reason) async {
    final r = await _call('cancelDoctorTokens', {'doctorId': doctorId, 'date': date, 'reason': reason});
    return (r['cancelled'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> setDoctorActive(String doctorId, bool active) => _call('setDoctorActive', {'doctorId': doctorId, 'active': active});

  @override
  Future<void> updateClinicSettings(String clinicId, {String? address, String? area, String? phone, PrintFormat? printFormat, String? name, GeoPoint? location}) {
    final c = _account(clinicId);
    final loc = location ?? c?.clinic.location;
    return _call('updateClinicSettings', {
      'location': loc == null ? null : {'lat': loc.lat, 'lng': loc.lng},
      'address': address ?? c?.clinic.address,
      'area': area ?? c?.clinic.area,
      'phone': phone ?? c?.clinic.phone,
      'printFormat': (printFormat ?? c?.printFormat ?? PrintFormat.thermal80).name,
    });
  }

  @override
  Future<void> logExport(String clinicId, String range) => _call('logExport', {'range': range});

  // ===================================================================
  // Super admin
  // ===================================================================

  @override
  Future<ClinicAccount> createClinic(NewClinicDraft draft) async {
    final r = await _call('adminCreateClinic', {
      'name': draft.name.trim(),
      'area': draft.area.trim(),
      'city': draft.city.trim(),
      'address': draft.address.trim(),
      'phone': draft.phone.trim(),
      'location': draft.location == null ? null : {'lat': draft.location!.lat, 'lng': draft.location!.lng},
      'printFormat': draft.printFormat.name,
      'ownerName': draft.ownerName.trim(),
      'ownerPhone': draft.ownerPhone.trim(),
      'email': draft.email.trim().toLowerCase(),
      'pilotDays': draft.pilotDays,
      'planAfterPilot': draft.planAfterPilot.name,
      'monthlyFee': draft.monthlyFee,
      'billingDay': draft.billingDay,
    });
    // §5.2: Firebase emails "Set your Asani password" (reset template).
    await sendPasswordReset('${r['email']}');
    final id = '${r['clinicId']}';
    final end = DateTime.now().add(const Duration(seconds: 8));
    while (_account(id) == null && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return _account(id) ??
        ClinicAccount(
          clinic: Clinic(id: id, name: draft.name, area: draft.area, city: draft.city, address: draft.address, phone: draft.phone, status: ClinicStatus.pilot),
          email: draft.email,
          ownerName: draft.ownerName,
          ownerPhone: draft.ownerPhone,
          createdAt: DateTime.now(),
        );
  }

  @override
  Future<void> resendClinicInvite(String clinicId) async {
    final r = await _call('adminResendClinicInvite', {'clinicId': clinicId});
    await sendPasswordReset('${r['email']}');
  }

  @override
  Future<void> setClinicLoginStatus(String clinicId, LoginStatus status) =>
      _call('adminSetClinicLogin', {'clinicId': clinicId, 'status': status == LoginStatus.disabled ? 'disabled' : 'active'});

  @override
  Future<void> setClinicStatus(String clinicId, ClinicStatus status, {String? reason}) =>
      _call('adminSetClinicStatus', {'clinicId': clinicId, 'status': status.name, 'reason': reason});

  @override
  Future<void> changePlan(String clinicId, {Plan? plan, int? monthlyFee}) {
    final c = _account(clinicId);
    return _call('adminChangePlan', {'clinicId': clinicId, 'plan': (plan ?? c?.plan ?? Plan.basic).name, 'monthlyFee': monthlyFee ?? c?.monthlyFee ?? 0});
  }

  @override
  Future<void> extendPilot(String clinicId, int days) => _call('adminExtendPilot', {'clinicId': clinicId, 'days': days});

  @override
  Future<void> recordPayment(String invoiceId, Payment payment) => _call('recordPayment', {
        'invoiceId': invoiceId,
        'amount': payment.amount,
        'method': payment.method.name,
        'reference': payment.reference,
        'date': payment.date.millisecondsSinceEpoch,
      });

  @override
  Future<void> waiveInvoice(String invoiceId, String reason) => _call('waiveInvoice', {'invoiceId': invoiceId, 'reason': reason});

  // ---- D-31..D-33: doctor search + same-doctor linking ----
  @override
  bool hasPmdc(String doctorId) => _hasPmdc.contains(doctorId);

  @override
  List<LinkSuggestion> linkSuggestions() => [
        for (final s in _suggestions.values)
          LinkSuggestion(
            pairId: s.pairId,
            doctorIds: s.doctorIds,
            clinicIds: s.clinicIds,
            strength: s.strength,
            status: s.status,
            createdAt: s.createdAt,
            pmdcNumbers: [for (final id in s.doctorIds) _pmdc[id]],
          ),
      ]..sort((a, b) => a.strength != b.strength ? a.strength.index.compareTo(b.strength.index) : b.createdAt.compareTo(a.createdAt));

  @override
  Doctor? doctorById(String doctorId) => _doctors[doctorId];

  @override
  Future<void> linkDoctors(String pairId) => _call('adminLinkDoctors', {'pairId': pairId});

  @override
  Future<void> markNotSame(String pairId) => _call('adminMarkNotSame', {'pairId': pairId});

  @override
  Future<void> unlinkDoctor(String doctorId) => _call('adminUnlinkDoctor', {'doctorId': doctorId});

  @override
  Future<void> giveExtension(String invoiceId, DateTime newDueDate) =>
      _call('giveExtension', {'invoiceId': invoiceId, 'dueDate': newDueDate.millisecondsSinceEpoch});

  @override
  Future<void> saveSettings(AdminSettings s) => _call('saveAdminSettings', {
        'prices': {for (final e in s.prices.entries) e.key.name: e.value},
        'pilotDays': s.pilotDays,
        'billingDay': s.billingDay,
        'dueDays': s.dueDays,
        'graceDays': s.graceDays,
        'suspendDays': s.suspendDays,
        'paymentInstructions': s.paymentInstructions,
      });
}
