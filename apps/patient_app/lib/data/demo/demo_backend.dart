import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:asani_core/asani_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/errors/app_exception.dart';
import '../repositories/repositories.dart';
import 'demo_seed.dart';

/// In-memory backend used until Firebase is connected.
///
/// It mirrors what the Cloud Functions will do (bookToken rules BR-1..BR-7,
/// cancelToken, onTokenWrite keeping `activeNumbers`, queue notifications)
/// and acts as `tools/queue-sim` by moving running queues forward on a timer.
/// User data is saved on the device so it survives restarts.
class DemoBackend
    implements
        AuthRepository,
        ClinicRepository,
        QueueRepository,
        TokenRepository,
        PatientRepository,
        FollowUpRepository,
        SettingsRepository,
        NotificationRepository,
        QueueSimulator {
  DemoBackend._(this._prefs);

  static const _storageKey = 'asani_demo_state_v1';
  static const demoOtp = '123456';
  static const maxActiveTokensPerAccount = 5; // BR-6
  static const simulatorInterval = Duration(seconds: 15);

  final SharedPreferences _prefs;
  final _changes = StreamController<void>.broadcast();
  final _alerts = StreamController<QueueAlert>.broadcast();
  final _random = Random();
  Timer? _simulator;

  // Reference data (seeded every launch).
  late final List<Clinic> _clinics;
  late final Map<String, Doctor> _doctors;

  // User data (persisted).
  final Map<String, AppUser> _users = {};
  final Map<String, Patient> _patients = {};
  final Map<String, Token> _tokens = {};
  final Map<String, QueueDay> _days = {};
  final Map<String, FollowUp> _followUps = {};
  String? _currentUid;
  AppSettings _settings = const AppSettings();

  // Login flow (not persisted).
  String? _pendingPhone;
  int _failedAttempts = 0;

  static Future<DemoBackend> create() async {
    final backend = DemoBackend._(await SharedPreferences.getInstance());
    backend._init();
    return backend;
  }

  // ---------------------------------------------------------------- setup

  void _init() {
    final now = DateTime.now();
    final seed = DemoSeed(now);
    final doctors = seed.doctors();
    _doctors = {for (final d in doctors) d.id: d};
    _clinics = [
      for (final c in seed.clinics())
        Clinic(
          id: c.id,
          name: c.name,
          area: c.area,
          city: c.city,
          address: c.address,
          phone: c.phone,
          location: c.location,
          status: c.status,
          doctorCount: doctors.where((d) => d.clinicId == c.id && d.active).length,
        ),
    ];
    _load();
    for (final day in seed.days()) {
      _days.putIfAbsent(_dayId(day.doctorId, day.date), () => day);
    }
    _closeOldTokens(now);
    _simulator = Timer.periodic(simulatorInterval, (_) => _tick());
  }

  /// Firebase mode: doctors read from Firestore replace the demo copies, so
  /// booking rules and the queue use the real schedule.
  void useDoctors(Iterable<Doctor> doctors) {
    var changed = false;
    for (final d in doctors) {
      final old = _doctors[d.id];
      if (old != null && old.toMap().toString() == d.toMap().toString()) continue;
      _doctors[d.id] = d;
      changed = true;
    }
    if (changed) _changed();
  }

  /// Firebase mode: family profiles read from Firestore, so booking (still
  /// demo) can book for them.
  void usePatients(Iterable<Patient> patients) {
    var changed = false;
    for (final p in patients) {
      final old = _patients[p.id];
      if (old != null && old.toMap().toString() == p.toMap().toString()) continue;
      _patients[p.id] = p;
      changed = true;
    }
    if (changed) _changed();
  }

  /// Firebase mode: the real queue is moved by tools/queue-sim, not this timer.
  void stopSimulator() {
    _simulator?.cancel();
    _simulator = null;
  }

  void dispose() {
    _simulator?.cancel();
    _changes.close();
    _alerts.close();
  }

  String _dayId(String doctorId, String date) => '${doctorId}_$date';

  void _load() {
    final raw = _prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      for (final u in (m['users'] as List)) {
        final user = AppUser.fromMap(Map<String, Object?>.from(u as Map));
        _users[user.uid] = user;
      }
      for (final p in (m['patients'] as List)) {
        final patient = Patient.fromMap(Map<String, Object?>.from(p as Map));
        _patients[patient.id] = patient;
      }
      for (final t in (m['tokens'] as List)) {
        final token = Token.fromMap(Map<String, Object?>.from(t as Map));
        _tokens[token.id] = token;
      }
      for (final d in (m['days'] as List)) {
        final day = QueueDay.fromMap(Map<String, Object?>.from(d as Map));
        _days[_dayId(day.doctorId, day.date)] = day;
      }
      for (final f in (m['followUps'] as List)) {
        final followUp = FollowUp.fromMap(Map<String, Object?>.from(f as Map));
        _followUps[followUp.id] = followUp;
      }
      _currentUid = m['currentUid'] as String?;
      _settings = AppSettings.fromMap((m['settings'] as Map?) ?? const {});
    } catch (e, st) {
      AppLogger.error('Could not read saved demo data; starting fresh', e, st);
    }
  }

  /// Only days from today onwards are kept.
  void _save() {
    final today = dayKey(DateTime.now());
    final data = {
      'users': _users.values.map((u) => u.toMap()).toList(),
      'patients': _patients.values.map((p) => p.toMap()).toList(),
      'tokens': _tokens.values.map((t) => t.toMap()).toList(),
      'days': _days.values.where((d) => d.date.compareTo(today) >= 0).map((d) => d.toMap()).toList(),
      'followUps': _followUps.values.map((f) => f.toMap()).toList(),
      'currentUid': _currentUid,
      'settings': _settings.toMap(),
    };
    _prefs.setString(_storageKey, jsonEncode(data));
  }

  void _changed() {
    _save();
    if (!_changes.isClosed) _changes.add(null);
  }

  /// Tokens from earlier days that never finished are closed.
  void _closeOldTokens(DateTime now) {
    final today = dayKey(now);
    for (final t in _tokens.values.toList()) {
      if (t.date.compareTo(today) < 0 && t.status.isActive) {
        _tokens[t.id] = t.copyWith(status: TokenStatus.completed, completedAt: parseDayKey(t.date));
      }
    }
  }

  /// Emits now and after every change.
  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  Future<void> _latency([int ms = 600]) => Future.delayed(Duration(milliseconds: ms));

  String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_random.nextInt(1 << 16).toRadixString(36)}';

  AppUser? get _me => _currentUid == null ? null : _users[_currentUid];

  // ---------------------------------------------------------------- auth

  @override
  AuthState get current {
    final me = _me;
    if (me != null) return AuthState(me.hasProfile ? AuthStatus.signedIn : AuthStatus.needsProfile, user: me);
    if (_pendingPhone != null) return AuthState(AuthStatus.codeSent, pendingPhone: _pendingPhone);
    return const AuthState(AuthStatus.signedOut);
  }

  @override
  Stream<AuthState> watchAuth() => _watch(() => current);

  @override
  Future<void> sendCode(String e164Phone) async {
    await _latency(800);
    _pendingPhone = e164Phone;
    _failedAttempts = 0;
    _changed();
  }

  @override
  Future<void> verifyCode(String code) async {
    await _latency(700);
    final phone = _pendingPhone;
    if (phone == null) throw AppException.generic;
    if (_failedAttempts >= 5) throw AppException.tooManyAttempts;
    if (code != demoOtp) {
      _failedAttempts++;
      throw AppException.wrongCode;
    }
    final uid = 'u_${phone.replaceAll('+', '')}';
    _users.putIfAbsent(uid, () => AppUser(uid: uid, phone: phone, name: ''));
    _currentUid = uid;
    _pendingPhone = null;
    _changed();
  }

  @override
  void cancelLogin() {
    _pendingPhone = null;
    _changed();
  }

  @override
  Future<void> completeProfile({required String name, required int age, required Gender gender}) async {
    await _latency(500);
    final me = _me;
    if (me == null) throw const AppException('session-expired', 'Session expired. Please log in again.');
    final isDemo = me.phone == DemoSeed.demoPhone;
    final now = DateTime.now();
    name = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    final self = Patient(
      id: _newId('p'),
      ownerUid: me.uid,
      phone: me.phone,
      name: name,
      gender: gender,
      birthYear: now.year - age,
      relation: Relation.self,
      createdAt: now,
    );
    _patients[self.id] = self;
    _users[me.uid] = me.copyWith(
      name: name.trim(),
      selfPatientId: self.id,
      consentAcceptedAt: now,
      consentVersion: '2026-11-v1',
    );
    // linkPatientProfiles: nothing to link in the demo, except the demo family.
    if (isDemo && !_patients.values.any((p) => p.ownerUid == me.uid && p.id != self.id)) {
      final demo = DemoSeed(now).demoAccount(me.uid, self);
      for (final p in demo.patients) {
        _patients[p.id] = p;
      }
      for (final t in demo.tokens) {
        _tokens[t.id] = t;
      }
      for (final f in demo.followUps) {
        _followUps[f.id] = f;
      }
    }
    _changed();
  }

  @override
  Future<void> updateName(String name) async {
    await _latency(300);
    final me = _me;
    if (me == null) return;
    _users[me.uid] = me.copyWith(name: name.trim());
    final selfId = me.selfPatientId;
    if (selfId != null && _patients[selfId] != null) {
      _patients[selfId] = _patients[selfId]!.copyWith(name: name.trim());
    }
    _changed();
  }

  @override
  Future<void> setCity(String city) async {
    final me = _me;
    if (me == null) return;
    _users[me.uid] = me.copyWith(city: city);
    _changed();
  }

  @override
  Future<void> setQueueAlerts(bool enabled) async {
    final me = _me;
    if (me == null) return;
    _users[me.uid] = me.copyWith(queueAlertsEnabled: enabled);
    _changed();
  }

  @override
  Future<void> signOut() async {
    await _latency(300);
    _currentUid = null;
    _changed();
  }

  /// deleteAccount: remove the user and personal fields; visit records are
  /// anonymised (PRD F-10).
  @override
  Future<void> deleteAccount() async {
    await _latency(800);
    final me = _me;
    if (me == null) return;
    for (final p in _patients.values.where((p) => p.ownerUid == me.uid).toList()) {
      _patients.remove(p.id);
    }
    for (final t in _tokens.values.where((t) => t.bookedByUserId == me.uid).toList()) {
      _tokens.remove(t.id);
    }
    _followUps.removeWhere((_, f) => f.ownerUid == me.uid);
    _users.remove(me.uid);
    _currentUid = null;
    _changed();
  }

  // ---------------------------------------------------------------- Firebase bridge

  /// Firebase mode: login lives in Firebase, while clinics, tokens and
  /// family still run on demo data for the signed-in account.
  void attachAccount(AppUser user, Patient self) {
    _users[user.uid] = user;
    _patients[self.id] = self;
    _currentUid = user.uid;
    _changed();
  }

  void detachAccount() {
    if (_currentUid == null) return;
    _currentUid = null;
    _changed();
  }

  // ---------------------------------------------------------------- clinics

  bool _visible(Clinic c) => c.status.acceptsBookings;

  @override
  Stream<List<String>> watchCities() => _watch(() => (_clinics.where(_visible).map((c) => c.city).toSet().toList())..sort());

  @override
  Stream<List<Clinic>> watchClinics(String city) =>
      _watch(() => _clinics.where((c) => c.city == city && _visible(c)).toList()..sort((a, b) => a.name.compareTo(b.name)));

  @override
  Stream<Clinic?> watchClinic(String clinicId) => _watch(() => _clinics.where((c) => c.id == clinicId).firstOrNull);

  List<Doctor> _doctorsOf(String clinicId) =>
      _doctors.values.where((d) => d.clinicId == clinicId && d.active).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  Stream<List<Doctor>> watchDoctors(String clinicId) => _watch(() => _doctorsOf(clinicId));

  @override
  Stream<Doctor?> watchDoctor(String doctorId) => _watch(() => _doctors[doctorId]);

  @override
  Stream<Map<String, List<Doctor>>> watchDoctorsByClinic() =>
      _watch(() => {for (final c in _clinics) c.id: _doctorsOf(c.id)});

  /// Clinics the user booked before, latest first, max 5 (PRD F-02).
  @override
  Stream<List<Clinic>> watchRecentClinics() =>
      _watch(() => _recentClinicIds().map((id) => _clinics.firstWhere((c) => c.id == id)).toList());

  /// IDs of the clinics in [watchRecentClinics], for the Firestore clinic repository.
  Stream<List<String>> watchRecentClinicIds() => _watch(_recentClinicIds);

  List<String> _recentClinicIds() {
    final mine = _myTokens()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final ids = <String>[];
    for (final t in mine) {
      if (!ids.contains(t.clinicId)) ids.add(t.clinicId);
    }
    return ids.take(5).toList();
  }

  // ---------------------------------------------------------------- queue

  QueueDay _day(String doctorId, String date) {
    final d = _doctors[doctorId];
    return _days[_dayId(doctorId, date)] ?? QueueDay.empty(d?.clinicId ?? '', doctorId, date);
  }

  @override
  Stream<QueueDay> watchDay(String doctorId, String date) => _watch(() => _day(doctorId, date));

  // ---------------------------------------------------------------- tokens

  List<Token> _myTokens() => _tokens.values.where((t) => t.bookedByUserId == _currentUid && _currentUid != null).toList();

  @override
  Stream<List<Token>> watchMyTokens() => _watch(_myTokens);

  @override
  Future<List<Token>> loadOlderTokens(DateTime before, {int limit = 50}) async => const []; // demo: all tokens are live

  @override
  Stream<Token?> watchToken(String tokenId) => _watch(() => _tokens[tokenId]);

  @override
  Stream<QueueAlert> get alerts => _alerts.stream;

  // ---------------------------------------------------------------- notifications list (D-45)
  final _inbox = <AppNotification>[];
  DateTime? _seenAt;

  @override
  Stream<List<AppNotification>> watchNotifications() => _watch(() {
        final since = DateTime.now().subtract(const Duration(days: 30));
        return _inbox.where((n) => n.createdAt.isAfter(since)).toList();
      });

  @override
  Stream<DateTime?> watchSeenAt() => _watch(() => _seenAt);

  @override
  Future<void> markAllSeen() async {
    _seenAt = DateTime.now();
    _changed();
  }

  /// Mirrors the `bookToken` Cloud Function (PRD F-04, BR-1..BR-7).
  @override
  Future<Token> bookToken({
    required String clinicId,
    required String doctorId,
    required String patientId,
    required String date,
  }) async {
    await _latency(900);
    final me = _me;
    final clinic = _clinics.where((c) => c.id == clinicId).firstOrNull;
    final doctor = _doctors[doctorId];
    final patient = _patients[patientId];
    if (me == null || clinic == null || doctor == null || patient == null) throw AppException.bookingFailed;

    if (!clinic.status.acceptsBookings) throw AppException.clinicUnavailable; // BR-1
    final now = DateTime.now();
    final day = _day(doctorId, date);
    switch (availabilityFor(doctor: doctor, date: parseDayKey(date), day: day, now: now)) {
      case DoctorAvailability.onLeave || DoctorAvailability.notScheduled:
        throw AppException.doctorUnavailable; // BR-2
      case DoctorAvailability.ended:
        throw AppException.sessionEnded; // BR-3
      case DoctorAvailability.full:
        throw AppException.tokensFull; // BR-4
      case DoctorAvailability.available || DoctorAvailability.notStarted:
        break;
    }
    final mine = _myTokens();
    final duplicate = mine
        .where((t) => t.patientId == patientId && t.doctorId == doctorId && t.date == date && t.status.isActive)
        .firstOrNull;
    if (duplicate != null) throw AppException.duplicateToken(patient.name, duplicate.label); // BR-5
    if (mine.where((t) => t.status.isActive).length >= maxActiveTokensPerAccount) {
      throw AppException.tooManyActive; // BR-6
    }

    // BR-7: sequential number, assigned "inside the transaction".
    final number = day.lastTokenNumber + 1;
    _days[_dayId(doctorId, date)] = day.copyWith(
      lastTokenNumber: number,
      bookedCount: day.bookedCount + 1,
      activeNumbers: [...day.activeNumbers, number]..sort(),
      updatedAt: now,
    );
    final token = Token(
      id: _newId('t'),
      clinicId: clinicId,
      doctorId: doctorId,
      date: date,
      number: number,
      tokenPrefix: doctor.tokenPrefix,
      patientId: patientId,
      patientSnapshot: PatientSnapshot.of(patient),
      bookedByUserId: me.uid,
      createdAt: now,
    );
    _tokens[token.id] = token;
    _followUps.updateAll((_, f) =>
        f.patientId == patientId && f.doctorId == doctorId && f.status == FollowUpStatus.pending
            ? f.copyWith(status: FollowUpStatus.booked)
            : f);
    _checkNotifications(doctorId, date);
    _changed();
    return _tokens[token.id]!;
  }

  /// Mirrors `cancelToken` + the `onTokenWrite` trigger.
  @override
  Future<void> cancelToken(String tokenId) async {
    await _latency(600);
    final t = _tokens[tokenId];
    if (t == null || !t.status.canCancel) throw AppException.generic;
    _tokens[tokenId] = t.copyWith(status: TokenStatus.cancelled, cancelledAt: DateTime.now(), cancelledBy: 'patient');
    final day = _day(t.doctorId, t.date);
    _days[_dayId(t.doctorId, t.date)] = day.copyWith(
      activeNumbers: day.activeNumbers.where((n) => n != t.number).toList(),
      updatedAt: DateTime.now(),
    );
    _checkNotifications(t.doctorId, t.date);
    _changed();
  }

  /// Queue notifications for my tokens of one doctor/day (PRD F-06).
  void _checkNotifications(String doctorId, String date) {
    final day = _day(doctorId, date);
    final doctor = _doctors[doctorId];
    if (doctor == null || date != dayKey(DateTime.now())) return;
    final withDoctor = _tokens.values.any((x) => x.doctorId == doctorId && x.date == date && x.status == TokenStatus.called);
    for (final t in _myTokens().where((t) => t.doctorId == doctorId && t.date == date)) {
      final ahead = patientsAhead(day.activeNumbers, t.number);
      final r = nextQueueNotification(status: t.status, ahead: ahead, alreadyNotified: t.notified, someoneWithDoctor: withDoctor);
      if (r.send == null) continue;
      _tokens[t.id] = t.copyWith(notified: r.notified);
      final step = r.send!;
      final (title, body) = switch (step) {
        QueueStep.threeAhead => ('3 patients ahead of you', 'Token ${t.label} · ${doctor.name}. Please start heading to the clinic.'),
        QueueStep.twoAhead => ('2 patients ahead of you', 'Token ${t.label} · ${doctor.name}'),
        QueueStep.oneAhead => ("You're next", 'Token ${t.label} · Please be at the reception.'),
        QueueStep.called => ('Your turn now', 'Token ${t.label} · Please go to ${doctor.name}.'),
      };
      // D-45: in the list even when alerts are off.
      _inbox.insert(0, AppNotification(id: 'n_${_inbox.length}_${t.id}', type: 'queue', title: title, body: body, route: '/token/${t.id}', tokenId: t.id, createdAt: DateTime.now()));
      if (!_settings.notificationsAllowed || _me?.queueAlertsEnabled == false) continue;
      _alerts.add(QueueAlert(tokenId: t.id, step: step, title: title, body: body));
    }
  }

  // ---------------------------------------------------------------- queue-sim

  void _tick() {
    if (!_settings.autoAdvanceQueue) return;
    final now = DateTime.now();
    final today = dayKey(now);
    var changed = false;
    for (final entry in _days.entries.toList()) {
      final day = entry.value;
      if (day.date != today) continue;
      final schedule = _doctors[day.doctorId]?.scheduleOn(now);
      final nowMin = now.hour * 60 + now.minute;
      if (day.sessionStatus == SessionStatus.notStarted && schedule != null && nowMin >= schedule.startMinutes) {
        _days[entry.key] = day.copyWith(sessionStatus: SessionStatus.running, updatedAt: now);
        changed = true;
      } else if (day.sessionStatus == SessionStatus.running && (day.activeNumbers.isNotEmpty || _calledToken(day) != null)) {
        _advance(day.doctorId, today);
        changed = true;
      }
    }
    if (changed) _changed();
  }

  Token? _calledToken(QueueDay day) => _tokens.values
      .where((t) => t.doctorId == day.doctorId && t.date == day.date && t.status == TokenStatus.called)
      .firstOrNull;

  /// queue-sim `next`: finish the current patient, call the next one.
  void _advance(String doctorId, String date) {
    final now = DateTime.now();
    var day = _day(doctorId, date);
    final called = _calledToken(day);
    if (called != null) {
      _tokens[called.id] = called.copyWith(status: TokenStatus.completed, completedAt: now);
    }
    if (day.activeNumbers.isEmpty) {
      _days[_dayId(doctorId, date)] = day.copyWith(updatedAt: now);
      return;
    }
    final next = day.activeNumbers.first;
    day = day.copyWith(
      currentToken: next,
      activeNumbers: day.activeNumbers.skip(1).toList(),
      sessionStatus: SessionStatus.running,
      updatedAt: now,
    );
    _days[_dayId(doctorId, date)] = day;
    final mine = _tokens.values.where((t) => t.doctorId == doctorId && t.date == date && t.number == next).firstOrNull;
    if (mine != null && mine.status.isWaiting) {
      _tokens[mine.id] = mine.copyWith(status: TokenStatus.called, calledAt: now);
    }
    _checkNotifications(doctorId, date);
  }

  @override
  Future<void> advanceQueue(String doctorId) async {
    final today = dayKey(DateTime.now());
    final day = _day(doctorId, today);
    if (day.sessionStatus == SessionStatus.notStarted) {
      _days[_dayId(doctorId, today)] = day.copyWith(sessionStatus: SessionStatus.running);
    }
    _advance(doctorId, today);
    _changed();
  }

  @override
  List<Doctor> doctorsWithMyActiveTokens() {
    final today = dayKey(DateTime.now());
    final ids = _myTokens().where((t) => t.status.isActive && t.date == today).map((t) => t.doctorId).toSet();
    return ids.map((id) => _doctors[id]).whereType<Doctor>().toList();
  }

  // ---------------------------------------------------------------- patients

  @override
  Stream<List<Patient>> watchMyPatients() => _watch(() {
        final list = _patients.values.where((p) => p.ownerUid == _currentUid && p.status == PatientStatus.active).toList();
        list.sort((a, b) {
          if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
          return a.createdAt.compareTo(b.createdAt);
        });
        return list;
      });

  @override
  Future<Patient> addPatient({
    required String name,
    int? age,
    required Gender gender,
    required Relation relation,
    String? patientPhone,
  }) async {
    await _latency(500);
    final me = _me;
    if (me == null) throw AppException.generic;
    final now = DateTime.now();
    final p = Patient(
      id: _newId('p'),
      ownerUid: me.uid,
      phone: me.phone,
      name: name.trim(),
      birthYear: age == null ? null : now.year - age,
      gender: gender,
      relation: relation,
      patientPhone: patientPhone,
      createdAt: now,
    );
    _patients[p.id] = p;
    _changed();
    return p;
  }

  @override
  Future<void> updatePatient(Patient patient, {int? age}) async {
    await _latency(400);
    final updated = age == null ? patient : patient.copyWith(birthYear: DateTime.now().year - age);
    _patients[patient.id] = updated;
    if (updated.isSelf) {
      final me = _me;
      if (me != null) _users[me.uid] = me.copyWith(name: updated.name);
    }
    _changed();
  }

  /// Soft delete (PRD F-07). Self cannot be removed.
  @override
  Future<void> removePatient(String patientId) async {
    await _latency(400);
    final p = _patients[patientId];
    if (p == null || p.isSelf) throw AppException.generic;
    _patients[patientId] = p.copyWith(status: PatientStatus.deleted);
    _changed();
  }

  // ---------------------------------------------------------------- follow-ups

  @override
  Stream<List<FollowUp>> watchMyFollowUps() => _watch(() {
        final list = _followUps.values.where((f) => f.ownerUid == _currentUid).toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
        return list;
      });

  // ---------------------------------------------------------------- settings

  @override
  AppSettings get settings => _settings;

  @override
  Stream<AppSettings> watchSettings() => _watch(() => _settings);

  @override
  Future<void> update(AppSettings settings) async {
    _settings = settings;
    _changed();
  }
}
