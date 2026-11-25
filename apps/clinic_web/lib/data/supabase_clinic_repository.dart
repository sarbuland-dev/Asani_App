import 'dart:async';
import 'dart:convert';

import 'package:asani_core/asani_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/errors/app_exception.dart';
import 'clinic_repository.dart';
import 'models.dart';

/// Clinic web on Supabase (D-52, phase 7). Same shape as the Firebase version: a live cache filled by Realtime
/// streams (RLS decides what a login may see), every write through a Postgres function (BW-1) or the
/// `admin-clinic-login` Edge Function. Email + password login; roles from `app_metadata`, set only on the server.
///
/// Realtime filters on uuid columns and on `id` never fire (docs/10 phase 5), so streams filter on `clinic_id`,
/// `date` or `month`, or not at all, and pick rows here.
class SupabaseClinicRepository implements ClinicRepository {
  SupabaseClinicRepository._(this._needsPassword);

  /// [linkType] = `invite` / `recovery` when this page was opened from an emailed link (read from the URL before
  /// Supabase consumed it): the clinic must choose a password first.
  static Future<SupabaseClinicRepository> create({String? linkType}) async {
    final repo = SupabaseClinicRepository._(linkType == 'invite' || linkType == 'recovery');
    final user = _db.auth.currentUser;
    if (user != null) {
      try {
        await repo._startSession(user, touch: repo._needsPassword);
      } catch (e) {
        AppLogger.warn('Saved session not usable: $e');
        await _db.auth.signOut();
      }
    }
    _db.auth.onAuthStateChange.listen((e) {
      if (e.event == AuthChangeEvent.passwordRecovery) {
        repo._needsPassword = true;
        repo._notify();
      }
      if (e.session == null && repo._user != null) repo._stopSession(); // banned / signed out elsewhere
    });
    return repo;
  }

  static SupabaseClient get _db => Supabase.instance.client;

  bool _needsPassword;
  final _changes = StreamController<void>.broadcast();
  final _subs = <String, StreamSubscription<dynamic>>{};
  Timer? _notifyTimer;

  UserAccount? _user;
  String _today = dayKey(pktNow());

  // ---- cache ----
  final _clinicRows = <String, Map<String, dynamic>>{};
  final _billing = <String, Map<String, dynamic>>{};
  final _doctors = <String, Doctor>{};
  final _addedAt = <String, DateTime>{};
  final _hasPmdc = <String>{};
  final _suggestions = <String, LinkSuggestion>{};
  final _pmdc = <String, String>{};
  final _days = <String, QueueDay>{}; // doctorId|date
  final _undoAt = <String, DateTime>{};
  final _tokens = <String, QueueToken>{};
  final _byClinicDate = <String, Set<String>>{};
  final _loadedDates = <String>{};
  final _patients = <String, Patient>{};
  final _patientHistory = <String, List<String>>{};
  final _loadingPatients = <String>{};
  final _searches = <String, List<String>>{};
  final _lookups = <String, PhoneLookup>{};
  final _followUps = <String, FollowUp>{};
  final _logins = <String, UserAccount>{};
  final _invoices = <String, Invoice>{};
  final _activity = <ActivityLog>[];
  final _stats = <String, (int, int)>{};
  AdminSettings _settings = const AdminSettings();

  void _notify() {
    _notifyTimer ??= Timer(const Duration(milliseconds: 40), () {
      _notifyTimer = null;
      if (!_changes.isClosed) _changes.add(null);
    });
  }

  void _watch(String key, Stream<List<Map<String, dynamic>>> stream, void Function(List<Map<String, dynamic>>) onData) {
    if (_subs.containsKey(key)) return;
    _subs[key] = stream.listen((rows) {
      onData(rows);
      _notify();
    }, onError: (Object e) {
      AppLogger.warn('stream $key: $e');
      _subs.remove(key);
    });
  }

  void _unwatch(String key) => _subs.remove(key)?.cancel();

  // ===================================================================
  // Rows → models
  // ===================================================================

  static final _snake = RegExp(r'_([a-z0-9])');
  static String _camel(String k) => k.replaceAllMapped(_snake, (m) => m[1]!.toUpperCase());

  static DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

  /// snake_case → camelCase, `*_at` ISO strings → epoch ms (what the shared models read).
  static Map<String, Object?> _plain(Map<String, dynamic> row) => {
        for (final e in row.entries)
          _camel(e.key): (e.key.endsWith('_at') && e.value is String) ? DateTime.tryParse(e.value as String)?.millisecondsSinceEpoch : e.value,
      };

  static Clinic _clinicFrom(Map<String, dynamic> r) {
    final lat = r['lat'], lng = r['lng'];
    return Clinic.fromMap({
      'id': r['id'],
      'name': r['name'] ?? '',
      'area': r['area'] ?? '',
      'city': r['city'] ?? '',
      'address': r['address'] ?? '',
      'phone': r['phone'] ?? '',
      'location': (lat is num && lng is num) ? {'lat': lat, 'lng': lng} : null,
      'status': r['status'],
      'doctorCount': (r['doctor_count'] as num?)?.toInt() ?? 0,
    });
  }

  static Plan _plan(Object? v) => Plan.values.where((p) => p.name == v).firstOrNull ?? Plan.pilot;
  static PrintFormat _print(Object? v) => PrintFormat.values.where((p) => p.name == v).firstOrNull ?? PrintFormat.thermal80;

  ClinicAccount? _account(String id) {
    final c = _clinicRows[id];
    if (c == null) return null;
    final b = _billing[id] ?? const <String, dynamic>{};
    final login = _logins[id];
    return ClinicAccount(
      clinic: _clinicFrom(c),
      email: (b['email'] as String?) ?? login?.email ?? '',
      ownerName: (b['owner_name'] as String?) ?? login?.name ?? '',
      ownerPhone: (b['owner_phone'] as String?) ?? '',
      plan: _plan(b['plan']),
      planAfterPilot: b['plan_after_pilot'] == 'premium' ? Plan.premium : Plan.basic,
      monthlyFee: (b['monthly_fee'] as num?)?.toInt() ?? 0,
      billingDay: (b['billing_day'] as num?)?.toInt() ?? 1,
      paidUntil: _date(b['paid_until']),
      pilotEndsAt: _date(b['pilot_ends_at']),
      printFormat: _print(c['print_format']),
      createdAt: _date(c['created_at']) ?? DateTime(2026),
      nextDoctorLetter: (c['next_doctor_letter'] as num?)?.toInt() ?? 0,
    );
  }

  static Doctor _doctorFrom(Map<String, dynamic> r) => Doctor.fromMap(_plain(r));

  static QueueDay _dayFrom(Map<String, dynamic> r) => QueueDay(
        clinicId: r['clinic_id'] as String,
        doctorId: r['doctor_id'] as String,
        date: r['date'] as String,
        sessionStatus: SessionStatus.parse(r['session_status']),
        currentToken: (r['current_token'] as num?)?.toInt() ?? 0,
        lastTokenNumber: (r['last_token_number'] as num?)?.toInt() ?? 0,
        activeNumbers: ((r['active_numbers'] as List?) ?? const []).map((e) => (e as num).toInt()).toList(),
        bookedCount: (r['booked_count'] as num?)?.toInt() ?? 0,
      );

  static QueueToken _tokenFrom(Map<String, dynamic> r) {
    final m = _plain(r);
    final snap = Map<String, Object?>.from((r['patient_snapshot'] as Map?) ?? const {});
    final token = Token.fromMap({
      ...m,
      'patientSnapshot': {...snap, 'name': snap['name'] ?? '', 'phone': snap['phone'] ?? '', 'birthYear': (snap['birthYear'] as num?)?.toInt()},
      'notified': const <String>[], // the clinic never needs the notification steps
    });
    return QueueToken(
      token: token,
      source: r['source'] == 'walkIn' ? TokenSource.walkIn : TokenSource.app,
      arrivedAt: _date(r['arrived_at']),
      cancelReason: r['cancel_reason'] as String?,
      history: [
        for (final h in (r['history'] as List?) ?? const [])
          if (h is Map) TokenEvent('${h['action'] ?? ''}', '${h['by'] ?? ''}', _date(h['at']) ?? DateTime.now(), note: h['note'] as String?),
      ],
    );
  }

  static Patient _patientFrom(Map<String, dynamic> r) => Patient.fromMap({..._plain(r), 'phone': r['phone'] ?? '', 'name': r['name'] ?? ''});

  static FollowUp _followUpFrom(Map<String, dynamic> r) => FollowUp.fromMap({..._plain(r), 'ownerUid': r['owner_uid'] ?? ''});

  static UserAccount _loginFrom(Map<String, dynamic> r) => UserAccount(
        uid: r['id'] as String,
        name: (r['name'] as String?) ?? '',
        email: (r['email'] as String?) ?? '',
        role: UserRole.clinic,
        clinicId: r['clinic_id'] as String?,
        status: LoginStatus.values.where((s) => s.name == r['status']).firstOrNull ?? LoginStatus.invited,
        createdAt: _date(r['created_at']) ?? DateTime.now(),
        invitedAt: _date(r['invited_at']),
        lastLoginAt: _date(r['last_login_at']),
        passwordChangedAt: _date(r['password_changed_at']),
        pinSet: r['pin_set'] == true,
      );

  static Invoice _invoiceFrom(Map<String, dynamic> r) {
    final p = r['payment'] as Map?;
    return Invoice(
      id: r['id'] as String,
      clinicId: (r['clinic_id'] as String?) ?? '',
      month: (r['month'] as String?) ?? '',
      amount: (r['amount'] as num?)?.toInt() ?? 0,
      dueDate: DateTime.tryParse('${r['due_date']}') ?? DateTime.now(),
      status: InvoiceStatus.values.where((s) => s.name == r['status']).firstOrNull ?? InvoiceStatus.unpaid,
      waiveReason: r['waive_reason'] as String?,
      payment: p == null
          ? null
          : Payment(
              amount: (p['amount'] as num?)?.toInt() ?? 0,
              method: PaymentMethod.values.where((x) => x.name == p['method']).firstOrNull ?? PaymentMethod.cash,
              reference: p['reference'] as String?,
              date: DateTime.tryParse('${p['date']}') ?? DateTime.now(),
              recordedBy: (p['recordedBy'] as String?) ?? '',
            ),
    );
  }

  static ActivityLog _logFrom(Map<String, dynamic> r) {
    final a = (r['actor'] as Map?) ?? const {};
    return ActivityLog(
      id: r['id'] as String,
      clinicId: r['clinic_id'] as String?,
      actorName: (a['name'] as String?) ?? 'System',
      actorRole: a['role'] == 'clinic' ? UserRole.clinic : UserRole.superAdmin,
      action: (r['action'] as String?) ?? '',
      target: (r['target'] as String?) ?? '',
      at: _date(r['at']) ?? DateTime.now(),
    );
  }

  static AdminSettings _settingsFrom(Map<String, dynamic>? m) {
    if (m == null) return const AdminSettings();
    final p = (m['prices'] as Map?) ?? const {};
    int n(Object? v, int d) => (v as num?)?.toInt() ?? d;
    const def = AdminSettings();
    return AdminSettings(
      prices: {for (final plan in Plan.values) plan: n(p[plan.name], def.prices[plan] ?? 0)},
      pilotDays: n(m['pilot_days'], def.pilotDays),
      billingDay: n(m['billing_day'], def.billingDay),
      dueDays: n(m['due_days'], def.dueDays),
      graceDays: n(m['grace_days'], def.graceDays),
      suspendDays: n(m['suspend_days'], def.suspendDays),
      paymentInstructions: (m['payment_instructions'] as String?) ?? def.paymentInstructions,
    );
  }

  static LinkSuggestion _suggestionFrom(Map<String, dynamic> r) => LinkSuggestion(
        pairId: r['id'] as String,
        doctorIds: [for (final x in (r['doctor_ids'] as List? ?? const [])) '$x'],
        clinicIds: [for (final x in (r['clinic_ids'] as List? ?? const [])) '$x'],
        strength: r['strength'] == 'strong' ? LinkStrength.strong : LinkStrength.weak,
        status: LinkStatus.values.firstWhere((x) => x.name == r['status'], orElse: () => LinkStatus.open),
        createdAt: _date(r['created_at']) ?? DateTime(2026),
      );

  void _putDoctors(List<Map<String, dynamic>> rows, {String? onlyClinic}) {
    if (onlyClinic != null) {
      _doctors.removeWhere((_, d) => d.clinicId == onlyClinic);
    } else {
      _doctors.clear();
    }
    for (final r in rows) {
      try {
        final d = _doctorFrom(r);
        _doctors[d.id] = d;
        if (r['has_pmdc'] == true) {
          _hasPmdc.add(d.id);
        } else {
          _hasPmdc.remove(d.id);
        }
        final at = _date(r['created_at']);
        if (at != null) _addedAt[d.id] = at;
      } catch (e) {
        AppLogger.warn('Skipping doctor ${r['id']}: $e');
      }
    }
  }

  // ===================================================================
  // Session
  // ===================================================================

  Future<void> _startSession(User user, {required bool touch}) async {
    final role = user.appMetadata['role'];
    final clinicId = user.appMetadata['clinic_id'];
    if (role == 'clinic' && clinicId is String) {
      final acc = await _db.from('clinic_accounts').select().eq('id', user.id).maybeSingle();
      final login = acc == null ? null : _loginFrom(acc);
      if (login?.status == LoginStatus.disabled) throw AppException.disabled;
      _user = UserAccount(
        uid: user.id,
        name: login?.name ?? '',
        email: user.email ?? login?.email ?? '',
        role: UserRole.clinic,
        clinicId: clinicId,
        createdAt: login?.createdAt ?? DateTime.now(),
        lastLoginAt: DateTime.now(),
        passwordChangedAt: login?.passwordChangedAt,
      );
      _watchClinic(clinicId);
      if (touch) unawaited(_db.rpc('clinic_login_touch').then((_) {}, onError: (Object _) {}));
    } else if (role == 'superAdmin') {
      final admin = await _db.from('admin_users').select('name').eq('id', user.id).maybeSingle();
      _user = UserAccount(
        uid: user.id,
        name: (admin?['name'] as String?)?.isNotEmpty == true ? admin!['name'] as String : 'Super Admin',
        email: user.email ?? '',
        role: UserRole.superAdmin,
        createdAt: DateTime.now(),
      );
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
    for (final m in <Map<dynamic, dynamic>>[
      _clinicRows, _billing, _doctors, _addedAt, _days, _undoAt, _tokens, _byClinicDate, _patients, _patientHistory, _searches,
      _lookups, _followUps, _logins, _invoices, _stats, _suggestions, _pmdc,
    ]) {
      m.clear();
    }
    _hasPmdc.clear();
    _loadedDates.clear();
    _activity.clear();
    _user = null;
    _notify();
  }

  /// A clinic login: its own clinic (RLS also limits billing, follow-ups, invoices, logs and the login row).
  void _watchClinic(String clinicId) {
    _watch('clinics', _db.from('clinics').stream(primaryKey: ['id']), (rows) {
      _clinicRows.removeWhere((k, _) => k == clinicId);
      for (final r in rows.where((r) => r['id'] == clinicId)) {
        _clinicRows[clinicId] = r;
      }
    });
    _watch('billing', _db.from('clinic_billing').stream(primaryKey: ['clinic_id']), (rows) {
      for (final r in rows) {
        _billing['${r['clinic_id']}'] = r;
      }
    });
    _watch('doctors/$clinicId', _db.from('doctors').stream(primaryKey: ['id']).eq('clinic_id', clinicId), (rows) {
      _putDoctors(rows, onlyClinic: clinicId);
    });
    _watchToday();
    _watch('followUps', _db.from('follow_ups').stream(primaryKey: ['id']), (rows) {
      _followUps
        ..clear()
        ..addEntries([for (final r in rows) MapEntry(r['id'] as String, _followUpFrom(r))]);
    });
    _watch('invoices', _db.from('invoices').stream(primaryKey: ['id']), (rows) {
      _invoices
        ..clear()
        ..addEntries([for (final r in rows) MapEntry(r['id'] as String, _invoiceFrom(r))]);
    });
    _watch('activity', _db.from('activity_logs').stream(primaryKey: ['id']).order('at', ascending: false).limit(200), (rows) {
      _activity
        ..clear()
        ..addAll(rows.map(_logFrom));
    });
    _watchSettings();
    _watch('login', _db.from('clinic_accounts').stream(primaryKey: ['id']), (rows) {
      for (final r in rows.where((r) => r['clinic_id'] == clinicId)) {
        _logins[clinicId] = _loginFrom(r);
      }
    });
  }

  void _watchSettings() => _watch('settings', _db.from('billing_settings').stream(primaryKey: ['id']), (rows) {
        _settings = _settingsFrom(rows.firstOrNull);
      });

  /// Today's tokens (RLS: own clinic, or every clinic for the Super Admin) and every queue day of today.
  void _watchToday() {
    final today = dayKey(pktNow());
    if (today != _today) {
      _unwatch('today');
      _unwatch('days');
      _loadedDates.removeWhere((k) => k.endsWith('|$_today'));
      _today = today;
    }
    _watch('today', _db.from('tokens').stream(primaryKey: ['id']).eq('date', today), (rows) {
      final byClinic = <String, List<Map<String, dynamic>>>{};
      for (final r in rows) {
        byClinic.putIfAbsent(r['clinic_id'] as String, () => []).add(r);
      }
      for (final k in _byClinicDate.keys.where((k) => k.endsWith('|$today')).toList()) {
        if (!byClinic.containsKey(k.split('|').first)) _putTokens(k, const []);
      }
      for (final e in byClinic.entries) {
        _loadedDates.add('${e.key}|$today');
        _putTokens('${e.key}|$today', e.value);
      }
    });
    _watch('days', _db.from('queue_days').stream(primaryKey: ['doctor_id', 'date']).eq('date', today), (rows) {
      for (final r in rows) {
        final d = _dayFrom(r);
        _days['${d.doctorId}|${d.date}'] = d;
        final at = _date((r['undo'] as Map?)?['at']);
        if (at != null) {
          _undoAt[d.doctorId] = at;
        } else {
          _undoAt.remove(d.doctorId);
        }
      }
    });
  }

  void _putTokens(String key, List<Map<String, dynamic>> rows) {
    final ids = _byClinicDate.putIfAbsent(key, () => <String>{});
    for (final id in ids) {
      _tokens.remove(id);
    }
    ids.clear();
    for (final r in rows) {
      try {
        final t = _tokenFrom(r);
        _tokens[t.id] = t;
        ids.add(t.id);
      } catch (e) {
        AppLogger.warn('Skipping token ${r['id']}: $e');
      }
    }
    _notify();
  }

  void _watchAdmin() {
    _watch('clinics', _db.from('clinics').stream(primaryKey: ['id']), (rows) {
      _clinicRows
        ..clear()
        ..addEntries([for (final r in rows) MapEntry(r['id'] as String, r)]);
    });
    _watch('billing', _db.from('clinic_billing').stream(primaryKey: ['clinic_id']), (rows) {
      _billing
        ..clear()
        ..addEntries([for (final r in rows) MapEntry(r['clinic_id'] as String, r)]);
    });
    final month = dayKey(pktNow()).substring(0, 7);
    _watch('stats', _db.from('clinic_stats').stream(primaryKey: ['clinic_id', 'month']).eq('month', month), (rows) {
      _stats
        ..clear()
        ..addEntries([
          for (final r in rows) MapEntry(r['clinic_id'] as String, ((r['app'] as num?)?.toInt() ?? 0, (r['walk_in'] as num?)?.toInt() ?? 0)),
        ]);
    });
    _watch('doctors', _db.from('doctors').stream(primaryKey: ['id']), (rows) => _putDoctors(rows));
    _watch('logins', _db.from('clinic_accounts').stream(primaryKey: ['id']), (rows) {
      _logins
        ..clear()
        ..addEntries([for (final r in rows) MapEntry(r['clinic_id'] as String, _loginFrom(r))]);
    });
    _watch('invoices', _db.from('invoices').stream(primaryKey: ['id']), (rows) {
      _invoices
        ..clear()
        ..addEntries([for (final r in rows) MapEntry(r['id'] as String, _invoiceFrom(r))]);
    });
    _watch('activity', _db.from('activity_logs').stream(primaryKey: ['id']).order('at', ascending: false).limit(500), (rows) {
      _activity
        ..clear()
        ..addAll(rows.map(_logFrom));
    });
    _watchSettings();
    _watchToday(); // "View queue" of any clinic
    // D-32 / A-09: same-doctor suggestions and the PMDC numbers they show (Super Admin only, RLS).
    _watch('linkSuggestions', _db.from('doctor_link_suggestions').stream(primaryKey: ['id']), (rows) {
      _suggestions
        ..clear()
        ..addEntries([for (final r in rows) MapEntry(r['id'] as String, _suggestionFrom(r))]);
    });
    _watch('pmdc', _db.from('doctor_private').stream(primaryKey: ['doctor_id']), (rows) {
      _pmdc
        ..clear()
        ..addEntries([
          for (final r in rows)
            if (r['pmdc_number'] is String) MapEntry(r['doctor_id'] as String, r['pmdc_number'] as String),
        ]);
    });
  }

  // ===================================================================
  // Auth (§5, D-52)
  // ===================================================================

  @override
  Stream<void> get changes => _changes.stream;

  @override
  UserAccount? get currentUser => _user;

  @override
  bool get needsNewPassword => _needsPassword && _user != null;

  static bool _isNetwork(Object e) {
    final s = e.toString();
    return e is AuthRetryableFetchException ||
        s.contains('ClientException') ||
        s.contains('XMLHttpRequest error') ||
        s.contains('Failed to fetch') ||
        s.contains('SocketException');
  }

  static AppException _authError(Object e) {
    if (_isNetwork(e)) return AppException.offline;
    if (e is AuthException) {
      AppLogger.warn('auth ${e.code} ${e.statusCode} ${e.message}');
      if (e.code == 'user_banned') return AppException.disabled;
      if (e.statusCode == '429' || (e.code ?? '').contains('rate_limit')) return AppException.tooManyAttempts;
      if (e.code == 'weak_password') return const AppException('weak-password', 'The new password needs at least 8 characters.');
      if (e.code == 'same_password') return const AppException('same-password', 'Choose a password you have not used here before.');
    }
    return AppException.wrongLogin; // never reveal which part is wrong (§5.3)
  }

  @override
  Future<UserAccount> signIn(String email, String password) async {
    try {
      final res = await _db.auth.signInWithPassword(email: email.trim().toLowerCase(), password: password);
      await _startSession(res.user!, touch: true);
      return _user!;
    } on AppException {
      await _db.auth.signOut();
      rethrow;
    } catch (e) {
      throw _authError(e);
    }
  }

  @override
  Future<void> signOut() async {
    _stopSession();
    _needsPassword = false;
    await _db.auth.signOut();
  }

  /// "If this email is registered, you'll get a link": unknown emails are never revealed.
  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _db.auth.resetPasswordForEmail(email.trim().toLowerCase(), redirectTo: Uri.base.origin);
    } catch (e) {
      final err = _authError(e);
      if (err.code == 'offline' || err.code == 'too-many-attempts') throw err;
    }
  }

  @override
  Future<void> setNewPassword(String password) async {
    if (password.length < 8) throw const AppException('weak-password', 'The password needs at least 8 characters.');
    try {
      await _db.auth.updateUser(UserAttributes(password: password));
    } catch (e) {
      throw _authError(e);
    }
    _needsPassword = false;
    if (_user?.isClinic ?? false) unawaited(_db.rpc('clinic_login_touch').then((_) {}, onError: (Object _) {}));
    _notify();
  }

  /// C-12: checks the current password, sets the new one, then signs out every other computer.
  @override
  Future<void> changePassword(String current, String next) async {
    final email = _db.auth.currentUser?.email;
    if (email == null) throw AppException.notAllowed;
    try {
      await _db.auth.signInWithPassword(email: email, password: current);
    } catch (e) {
      final err = _authError(e);
      throw err.code == 'wrong-login' ? const AppException('wrong-password', 'Current password is incorrect.') : err;
    }
    try {
      await _db.auth.updateUser(UserAttributes(password: next));
      await _db.auth.signOut(scope: SignOutScope.others);
    } catch (e) {
      throw _authError(e);
    }
    await _call('clinic_password_changed');
  }

  // ===================================================================
  // Calls
  // ===================================================================

  /// A Postgres function (`supabase.rpc`). The exception message is the code, the hint the text (docs/10 §6b).
  Future<Map<String, dynamic>> _call(String fn, [Map<String, Object?> params = const {}]) async {
    try {
      final r = await _db.rpc(fn, params: params);
      return r is Map ? Map<String, dynamic>.from(r) : <String, dynamic>{};
    } catch (e) {
      throw _dbError(fn, e);
    }
  }

  static AppException _dbError(String fn, Object e) {
    if (_isNetwork(e)) return AppException.offline;
    if (e is PostgrestException) {
      AppLogger.warn('$fn failed: ${e.code} ${e.message} ${e.hint ?? ''}');
      if (e.message == 'suspended') return AppException.suspended;
      if (e.code == '42501' || e.message == 'permission-denied') return AppException.notAllowed;
      return AppException(e.message, e.hint ?? AppException.generic.message);
    }
    AppLogger.error('$fn failed', e);
    return AppException.generic;
  }

  /// PIN functions answer {ok: false, code, message} instead of raising, so a wrong try is saved (D-41).
  Future<void> _pinCall(String fn, Map<String, Object?> params) async {
    final r = await _call(fn, params);
    if (r['ok'] != true) throw AppException('${r['code'] ?? 'pin-wrong'}', '${r['message'] ?? 'Wrong PIN.'}');
  }

  /// The admin-clinic-login Edge Function (create / resend / disable / enable).
  Future<Map<String, dynamic>> _loginFn(Map<String, Object?> body) async {
    try {
      final r = await _db.functions.invoke('admin-clinic-login', body: body);
      final data = r.data is String ? jsonDecode(r.data as String) : r.data;
      return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
    } on FunctionException catch (e) {
      final d = e.details is String ? (() {
        try {
          return jsonDecode(e.details as String);
        } catch (_) {
          return null;
        }
      })() : e.details;
      if (d is Map) throw AppException('${d['error'] ?? 'unknown'}', '${d['message'] ?? AppException.generic.message}');
      throw AppException.generic;
    } catch (e) {
      if (e is AppException) rethrow;
      throw _isNetwork(e) ? AppException.offline : AppException.generic;
    }
  }

  // ===================================================================
  // Reads
  // ===================================================================

  @override
  ClinicAccount? clinic(String clinicId) => _account(clinicId);

  @override
  List<ClinicAccount> clinics() => [for (final id in _clinicRows.keys) ?_account(id)]..sort((a, b) => a.clinic.name.compareTo(b.clinic.name));

  @override
  List<Doctor> doctors(String clinicId, {bool includeInactive = false}) =>
      _doctors.values.where((d) => d.clinicId == clinicId && (includeInactive || d.active)).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  QueueDay queueDay(String clinicId, String doctorId, String date) {
    if (date == dayKey(pktNow())) _watchToday();
    return _days['$doctorId|$date'] ?? QueueDay.empty(clinicId, doctorId, date);
  }

  @override
  List<QueueToken> tokens(String clinicId, String date) {
    final key = '$clinicId|$date';
    if (date == dayKey(pktNow())) {
      _watchToday();
    } else if (_loadedDates.add(key)) {
      unawaited(_loadDate(clinicId, date));
    }
    return [for (final id in _byClinicDate[key] ?? const <String>{}) ?_tokens[id]];
  }

  Future<void> _loadDate(String clinicId, String date) async {
    try {
      final rows = await _db.from('tokens').select().eq('clinic_id', clinicId).eq('date', date);
      _putTokens('$clinicId|$date', rows);
    } catch (e) {
      _loadedDates.remove('$clinicId|$date');
      AppLogger.warn('load tokens $date: $e');
    }
  }

  @override
  Future<List<QueueToken>> loadTokens(String clinicId, String from, String to) async {
    try {
      final rows = await _db.from('tokens').select().eq('clinic_id', clinicId).gte('date', from).lte('date', to).order('date');
      return rows.map(_tokenFrom).toList();
    } catch (e) {
      throw _dbError('load tokens', e);
    }
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
    final today = tokens(clinicId, dayKey(pktNow())).where(matches).toList(); // BW-5: today's tokens only
    if (letter.isEmpty && doctors(clinicId, includeInactive: true).length > 1 && today.length > 1) return CodeLookup(ambiguous: today);
    if (today.isNotEmpty) return CodeLookup(token: today.first);
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
      var local = q.replaceAll(RegExp(r'[^0-9]'), '');
      if (local.startsWith('92') && local.length > 10) local = local.substring(2);
      while (local.startsWith('0')) {
        local = local.substring(1);
      }
      final safe = q.replaceAll(RegExp(r'[%_\\]'), '');
      final base = _db.from('patients').select().contains('clinic_ids', [clinicId]).eq('status', 'active');
      final rows = local.length >= 3
          ? await base.like('phone', '+92$local%').limit(60) // phone prefix (full numbers are exact)
          : await base.like('name_lower', '$safe%').limit(60);
      final ids = <String>[];
      for (final r in rows) {
        final p = _patientFrom(r);
        _patients[p.id] = p;
        ids.add(p.id);
        unawaited(_loadHistory(clinicId, p.id));
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
    final history = _patientHistory['$clinicId|$patientId'];
    final p = _patients[patientId];
    if (history == null) {
      unawaited(_loadHistory(clinicId, patientId));
      return p == null ? null : ClinicPatient(patient: p, visits: const []);
    }
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
      final p = await _db.from('patients').select().eq('id', patientId).maybeSingle();
      final t = await _db.from('tokens').select().eq('clinic_id', clinicId).eq('patient_id', patientId).order('date', ascending: false).limit(100);
      if (p != null) _patients[patientId] = _patientFrom(p);
      for (final r in t) {
        _tokens.putIfAbsent(r['id'] as String, () => _tokenFrom(r)); // today's live copies win
      }
      _patientHistory[key] = [for (final r in t) r['id'] as String];
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
  // Queue writes (BW-1)
  // ===================================================================

  @override
  Future<void> session(String clinicId, String doctorId, SessionAction action) =>
      _call('queue_action', {'p_action': action.name, 'p_doctor_id': doctorId});

  @override
  Future<CalledInfo?> next(String clinicId, String doctorId, {String? callNotArrived}) async {
    try {
      final r = await _db.rpc('queue_action', params: {'p_action': 'next', 'p_doctor_id': doctorId, 'p_call_not_arrived': callNotArrived});
      final c = (r is Map ? r['called'] : null) as Map?;
      return c == null ? null : CalledInfo('${c['label']}', '${c['name'] ?? ''}');
    } on PostgrestException catch (e) {
      if (e.message == 'not-arrived') {
        final d = jsonDecode(e.details?.toString() ?? '{}') as Map;
        throw NotArrived('${d['tokenId']}', '${d['label']}', '${d['name'] ?? ''}');
      }
      throw _dbError('queue_action next', e);
    } catch (e) {
      if (e is NotArrived) rethrow;
      throw _dbError('queue_action next', e);
    }
  }

  @override
  Future<void> undoNext(String doctorId) => _call('queue_action', {'p_action': 'undo', 'p_doctor_id': doctorId});

  @override
  Future<void> tokenAction(String tokenId, TokenAction action, {String? reason}) =>
      _call('queue_action', {'p_action': action.name, 'p_token_id': tokenId, 'p_reason': reason});

  /// Waits until a token written by the backend reaches the live cache.
  Future<QueueToken> _awaitToken(String id) async {
    final end = DateTime.now().add(const Duration(seconds: 6));
    while (_tokens[id] == null && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    final t = _tokens[id];
    if (t != null) return t;
    final row = await _db.from('tokens').select().eq('id', id).single();
    return _tokenFrom(row);
  }

  @override
  PhoneLookup lookupPhone(String clinicId, String phone) {
    final key = '$clinicId|$phone';
    final hit = _lookups[key];
    if (hit != null) return hit;
    _lookups[key] = const PhoneLookup.loading();
    unawaited(() async {
      try {
        final r = await _call('clinic_lookup_phone', {'p_phone': phone});
        _lookups[key] = PhoneLookup.done([
          for (final m in (r['profiles'] as List? ?? const []).whereType<Map<Object?, Object?>>())
            PhoneProfile(
              id: '${m['id']}',
              name: '${m['name'] ?? ''}',
              relation: Relation.parse(m['relation']),
              gender: Gender.parse(m['gender']),
              age: (m['age'] as num?)?.toInt(),
              atThisClinic: m['atThisClinic'] == true,
              appAccount: m['appAccount'] == true,
            ),
        ]);
      } on AppException catch (e) {
        _lookups[key] = PhoneLookup.failed(e.message);
        Timer(const Duration(seconds: 30), () => _lookups.remove(key)); // allow a retry later (rate limit)
      }
      _notify();
    }());
    return const PhoneLookup.loading();
  }

  @override
  Future<QueueToken> createWalkIn(String clinicId, String doctorId, {String? patientId, String? phone, NewPatient? newPatient}) async {
    final r = await _call('clinic_create_walk_in', {
      'p_doctor_id': doctorId,
      'p_patient_id': patientId,
      'p_phone': patientId == null ? null : phone,
      'p_new': newPatient == null
          ? null
          : {
              'phone': newPatient.phone,
              'name': newPatient.name.trim(),
              'age': newPatient.age,
              'gender': newPatient.gender.name,
              'relation': newPatient.relation.name,
            },
    });
    _searches.clear();
    _lookups.clear();
    return _awaitToken('${r['tokenId']}');
  }

  @override
  Future<void> setFollowUp(String tokenId, String dueDate, {String? note}) =>
      _call('set_follow_up', {'p_token_id': tokenId, 'p_due_date': dueDate, 'p_note': note});

  @override
  Future<void> updatePatient(String clinicId, String patientId, {required String name, int? birthYear, required Gender gender}) async {
    await _call('clinic_update_patient', {
      'p_patient_id': patientId,
      'p_name': name.trim(),
      'p_gender': gender.name,
      'p_age': birthYear == null ? null : pktNow().year - birthYear,
    });
    _patientHistory.remove('$clinicId|$patientId');
    await _loadHistory(clinicId, patientId);
  }

  @override
  Future<int> linkWalkInToAccount(String clinicId, String walkInId, {required String accountPhone, String? targetPatientId}) async {
    final r = await _call('link_walk_in_to_account', {
      'p_walk_in_id': walkInId,
      'p_account_phone': accountPhone,
      'p_target_patient_id': targetPatientId,
    });
    _searches.clear();
    _lookups.clear();
    _patientHistory.removeWhere((k, _) => k.startsWith('$clinicId|'));
    await _loadHistory(clinicId, '${r['patientId'] ?? walkInId}');
    return (r['visitsMoved'] as num?)?.toInt() ?? 0;
  }

  // ===================================================================
  // Clinic login: doctors, settings, PIN
  // ===================================================================

  @override
  Future<Doctor> saveDoctor(String clinicId, Doctor doctor, {bool isNew = false, String? pmdcNumber}) async {
    final r = await _call('save_doctor', {
      'p_doctor_id': isNew ? null : doctor.id,
      'p_name': doctor.name.trim(),
      'p_speciality': doctor.speciality.trim(),
      'p_pmdc': pmdcNumber, // D-33: stored admin-only
      'p_qualification': doctor.qualification,
      'p_avg_consult_minutes': doctor.avgConsultMinutes,
      'p_max_tokens_per_day': doctor.maxTokensPerDay,
      'p_booking_window_days': doctor.bookingWindowDays,
      'p_schedule': {for (final e in doctor.schedule.entries) e.key: e.value?.toMap()},
    });
    final id = '${r['doctorId']}';
    final end = DateTime.now().add(const Duration(seconds: 4));
    while (_doctors[id] == null && DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return _doctors[id] ?? doctor;
  }

  @override
  bool hasPmdc(String doctorId) => _hasPmdc.contains(doctorId);

  @override
  Future<int> addLeave(String doctorId, String date) async {
    final r = await _call('set_doctor_leave', {'p_doctor_id': doctorId, 'p_date': date, 'p_add': true});
    return (r['activeTokens'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> removeLeave(String doctorId, String date) => _call('set_doctor_leave', {'p_doctor_id': doctorId, 'p_date': date, 'p_add': false});

  @override
  Future<int> cancelTokensOn(String doctorId, String date, String reason) async {
    final r = await _call('cancel_doctor_tokens', {'p_doctor_id': doctorId, 'p_date': date, 'p_reason': reason});
    return (r['cancelled'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> setDoctorActive(String doctorId, bool active) => _call('set_doctor_active', {'p_doctor_id': doctorId, 'p_active': active});

  @override
  Future<void> updateClinicSettings(String clinicId, {String? address, String? area, String? phone, PrintFormat? printFormat, String? name, GeoPoint? location}) {
    final c = _account(clinicId);
    final loc = location ?? c?.clinic.location;
    return _call('update_clinic_settings', {
      'p_address': address ?? c?.clinic.address,
      'p_area': area ?? c?.clinic.area,
      'p_phone': phone ?? c?.clinic.phone,
      'p_print_format': (printFormat ?? c?.printFormat ?? PrintFormat.thermal80).name,
      'p_lat': loc?.lat,
      'p_lng': loc?.lng,
    });
  }

  @override
  Future<void> logExport(String clinicId, String range) => _call('log_export', {'p_range': range});

  @override
  Future<void> setPin(String pin, {String? currentPin}) => _pinCall('clinic_set_pin', {'p_pin': pin, 'p_current_pin': currentPin});

  @override
  Future<void> verifyPin(String pin) => _pinCall('clinic_verify_pin', {'p_pin': pin});

  @override
  Future<void> resetClinicPin(String clinicId) => _call('admin_reset_clinic_pin', {'p_clinic_id': clinicId});

  // ===================================================================
  // Super admin
  // ===================================================================

  @override
  Future<ClinicAccount> createClinic(NewClinicDraft draft) async {
    final r = await _loginFn({
      'action': 'create',
      'clinic': {
        'name': draft.name.trim(),
        'area': draft.area.trim(),
        'city': draft.city.trim(),
        'address': draft.address.trim(),
        'phone': draft.phone.trim(),
        'lat': draft.location?.lat,
        'lng': draft.location?.lng,
        'printFormat': draft.printFormat.name,
        'ownerName': draft.ownerName.trim(),
        'ownerPhone': draft.ownerPhone.trim(),
        'email': draft.email.trim().toLowerCase(),
        'pilotDays': draft.pilotDays,
        'planAfterPilot': draft.planAfterPilot.name,
        'monthlyFee': draft.monthlyFee,
        'billingDay': draft.billingDay,
      },
    });
    final id = '${r['clinicId']}';
    final end = DateTime.now().add(const Duration(seconds: 6));
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
  Future<void> resendClinicInvite(String clinicId) => _loginFn({'action': 'resend', 'clinicId': clinicId});

  @override
  Future<void> setClinicLoginStatus(String clinicId, LoginStatus status) =>
      _loginFn({'action': status == LoginStatus.disabled ? 'disable' : 'enable', 'clinicId': clinicId});

  @override
  Future<void> setClinicStatus(String clinicId, ClinicStatus status, {String? reason}) =>
      _call('admin_set_clinic_status', {'p_clinic_id': clinicId, 'p_status': status.name, 'p_reason': reason});

  @override
  Future<void> changePlan(String clinicId, {Plan? plan, int? monthlyFee}) {
    final c = _account(clinicId);
    return _call('admin_change_plan', {
      'p_clinic_id': clinicId,
      'p_plan': (plan ?? c?.plan ?? Plan.basic).name,
      'p_monthly_fee': monthlyFee ?? c?.monthlyFee ?? 0,
    });
  }

  @override
  Future<void> extendPilot(String clinicId, int days) => _call('admin_extend_pilot', {'p_clinic_id': clinicId, 'p_days': days});

  static String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Future<void> recordPayment(String invoiceId, Payment payment) => _call('record_payment', {
        'p_invoice_id': invoiceId,
        'p_method': payment.method.name,
        'p_amount': payment.amount,
        'p_reference': payment.reference,
        'p_date': _ymd(payment.date),
      });

  @override
  Future<void> waiveInvoice(String invoiceId, String reason) => _call('waive_invoice', {'p_invoice_id': invoiceId, 'p_reason': reason});

  @override
  Future<void> giveExtension(String invoiceId, DateTime newDueDate) =>
      _call('give_extension', {'p_invoice_id': invoiceId, 'p_due_date': _ymd(newDueDate)});

  @override
  Future<void> saveSettings(AdminSettings s) => _call('save_admin_settings', {
        'p_prices': {for (final e in s.prices.entries) e.key.name: e.value},
        'p_pilot_days': s.pilotDays,
        'p_billing_day': s.billingDay,
        'p_due_days': s.dueDays,
        'p_grace_days': s.graceDays,
        'p_suspend_days': s.suspendDays,
        'p_payment_instructions': s.paymentInstructions,
      });

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
  Future<void> linkDoctors(String pairId) => _call('admin_link_doctors', {'p_pair_id': pairId});

  @override
  Future<void> markNotSame(String pairId) => _call('admin_mark_not_same', {'p_pair_id': pairId});

  @override
  Future<void> unlinkDoctor(String doctorId) => _call('admin_unlink_doctor', {'p_doctor_id': doctorId});
}
