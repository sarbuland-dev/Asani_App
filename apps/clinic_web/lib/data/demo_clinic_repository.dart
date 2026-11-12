import 'dart:async';
import 'dart:math';

import 'package:asani_core/asani_core.dart';

import '../core/errors/app_exception.dart';
import 'clinic_repository.dart';
import 'models.dart';

/// In-memory clinic backend for demo mode (same idea as the patient app's
/// demo backend, D-11). Data is seeded around "now" in Pakistan time so the
/// queue is always live. Nothing is saved: a page reload starts fresh.
///
/// Demo accounts (password `asani123`) are listed in apps/clinic_web/README.md.
class DemoClinicRepository implements ClinicRepository {
  DemoClinicRepository({bool simulate = true}) {
    _seed();
    if (simulate) _sim = Timer.periodic(const Duration(seconds: 50), (_) => _simulateAppBooking());
  }

  static const demoPassword = 'asani123';
  static const _letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  final _changes = StreamController<void>.broadcast();
  final _rnd = Random(7);
  Timer? _sim;

  final _clinics = <String, ClinicAccount>{};
  final _doctors = <String, Doctor>{};
  final _days = <String, QueueDay>{}; // doctorId|date
  final _tokens = <String, QueueToken>{};
  final _byClinicDate = <String, List<String>>{}; // clinicId|date → token ids
  final _patients = <String, Patient>{};
  final _patientClinics = <String, Set<String>>{}; // patients.clinicIds
  final _followUps = <String, FollowUp>{};
  final _staff = <String, StaffAccount>{};
  final _invoices = <String, Invoice>{};
  final _activity = <ActivityLog>[];
  final _failedLogins = <String, int>{};
  final _undo = <String, _UndoNext>{};
  AdminSettings _settings = const AdminSettings();
  StaffAccount? _user;
  int _seq = 0;

  void dispose() {
    _sim?.cancel();
    _changes.close();
  }

  DateTime get _now => pktNow();
  String get _today => dayKey(_now);
  String _id(String prefix) => '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
  void _notify() => _changes.add(null);

  Future<void> _latency([int ms = 180]) => Future<void>.delayed(Duration(milliseconds: ms));

  String get _actor => _user == null ? 'System' : '${_user!.name} (${_user!.role.label})';

  void _log(String? clinicId, String action, String target) {
    final u = _user;
    _activity.insert(
      0,
      ActivityLog(
        id: _id('log'),
        clinicId: clinicId,
        actorName: u?.name ?? 'System',
        actorRole: u?.role ?? StaffRole.superAdmin,
        action: action,
        target: target,
        at: _now,
      ),
    );
  }

  StaffAccount _requireUser() => _user ?? (throw AppException.notAllowed);

  void _requireWritable(String clinicId) {
    final c = _clinics[clinicId];
    if (c == null) throw AppException.generic;
    if (c.status == ClinicStatus.suspended || c.status == ClinicStatus.cancelled) throw AppException.suspended;
  }

  // ===================================================================
  // Auth
  // ===================================================================

  @override
  Stream<void> get changes => _changes.stream;

  @override
  StaffAccount? get currentUser => _user;

  @override
  Future<StaffAccount> signIn(String email, String password) async {
    await _latency(450);
    final key = email.trim().toLowerCase();
    if ((_failedLogins[key] ?? 0) >= 5) throw AppException.tooManyAttempts;
    final acc = _staff.values.where((s) => s.email.toLowerCase() == key).firstOrNull;
    // Invited accounts have no password yet; never reveal which part is wrong.
    if (acc == null || password != demoPassword || acc.status == StaffStatus.invited) {
      _failedLogins[key] = (_failedLogins[key] ?? 0) + 1;
      throw AppException.wrongLogin;
    }
    if (acc.status == StaffStatus.disabled) throw AppException.disabled;
    _failedLogins.remove(key);
    final updated = acc.copyWith(lastLoginAt: _now);
    _staff[acc.uid] = updated;
    _user = updated;
    _notify();
    return updated;
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _notify();
  }

  @override
  Future<void> sendPasswordReset(String email) => _latency(400);

  // ===================================================================
  // Reads
  // ===================================================================

  @override
  ClinicAccount? clinic(String clinicId) => _clinics[clinicId];

  @override
  List<ClinicAccount> clinics() => _clinics.values.toList()..sort((a, b) => a.clinic.name.compareTo(b.clinic.name));

  @override
  List<Doctor> doctors(String clinicId, {bool includeInactive = false}) =>
      _doctors.values.where((d) => d.clinicId == clinicId && (includeInactive || d.active)).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  @override
  QueueDay queueDay(String clinicId, String doctorId, String date) =>
      _days['$doctorId|$date'] ?? QueueDay.empty(clinicId, doctorId, date);

  @override
  List<QueueToken> tokens(String clinicId, String date) =>
      [for (final id in _byClinicDate['$clinicId|$date'] ?? const <String>[]) _tokens[id]!];

  @override
  QueueToken? tokenById(String id) => _tokens[id];

  @override
  Patient? patient(String id) => _patients[id];

  @override
  CodeLookup findByCode(String clinicId, String code) {
    final clean = code.trim().toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    final m = RegExp(r'^([A-Z]*)(\d+)$').firstMatch(clean);
    if (m == null) return const CodeLookup();
    final letter = m.group(1)!;
    final number = int.parse(m.group(2)!);
    final docs = doctors(clinicId, includeInactive: true);
    bool matches(QueueToken t) => t.number == number && (letter.isEmpty || t.token.tokenPrefix == letter);

    // BW-5: only today's tokens of this clinic.
    final today = tokens(clinicId, _today).where(matches).toList();
    if (letter.isEmpty && docs.length > 1 && today.length > 1) return CodeLookup(ambiguous: today);
    if (today.isNotEmpty) return CodeLookup(token: today.first);

    // Same code on another day: warn, so the receptionist can tell the patient.
    QueueToken? other;
    for (final t in _tokens.values) {
      if (t.token.clinicId != clinicId || !matches(t) || !t.status.isActive) continue;
      if (other == null || t.token.date.compareTo(other.token.date) > 0) other = t;
    }
    return CodeLookup(otherDate: other);
  }

  List<QueueToken> _patientTokens(String clinicId, String patientId) =>
      _tokens.values.where((t) => t.token.clinicId == clinicId && t.token.patientId == patientId).toList()
        ..sort((a, b) {
          final d = b.token.date.compareTo(a.token.date);
          return d != 0 ? d : b.number.compareTo(a.number);
        });

  @override
  ClinicPatient? clinicPatient(String clinicId, String patientId) {
    final p = _patients[patientId];
    if (p == null || !(_patientClinics[patientId]?.contains(clinicId) ?? false)) return null;
    return ClinicPatient(
      patient: p,
      visits: _patientTokens(clinicId, patientId),
      followUps: _followUps.values.where((f) => f.clinicId == clinicId && f.patientId == patientId).toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate)),
    );
  }

  @override
  List<ClinicPatient> searchPatients(String clinicId, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    var local = digits;
    if (local.startsWith('92') && local.length > 10) local = local.substring(2);
    while (local.startsWith('0')) {
      local = local.substring(1);
    }
    final byPhone = local.length >= 3;
    final out = <ClinicPatient>[];
    for (final p in _patients.values) {
      if (p.status != PatientStatus.active) continue;
      if (!(_patientClinics[p.id]?.contains(clinicId) ?? false)) continue; // BW-6
      final hit = byPhone ? p.phone.replaceAll(RegExp(r'[^0-9]'), '').contains(local) : p.nameLower.contains(q);
      if (hit) out.add(clinicPatient(clinicId, p.id)!);
    }
    out.sort((a, b) {
      final c = a.patient.phone.compareTo(b.patient.phone);
      return c != 0 ? c : a.patient.relation.index.compareTo(b.patient.relation.index);
    });
    return out.take(60).toList();
  }

  @override
  List<FollowUp> followUps(String clinicId) =>
      _followUps.values.where((f) => f.clinicId == clinicId).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  @override
  List<StaffAccount> staff(String clinicId) =>
      _staff.values.where((s) => s.clinicId == clinicId).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  List<Invoice> invoices({String? clinicId}) =>
      _invoices.values.where((i) => clinicId == null || i.clinicId == clinicId).toList()
        ..sort((a, b) {
          final m = b.month.compareTo(a.month);
          return m != 0 ? m : a.clinicId.compareTo(b.clinicId);
        });

  @override
  List<ActivityLog> activity({String? clinicId}) =>
      _activity.where((a) => clinicId == null || a.clinicId == clinicId).toList();

  @override
  AdminSettings get settings => _settings;

  @override
  bool canUndoNext(String doctorId) {
    final u = _undo[doctorId];
    return u != null && _now.difference(u.at).inSeconds < 30;
  }

  // ===================================================================
  // Queue writes
  // ===================================================================

  void _put(QueueToken t) {
    _tokens[t.id] = t;
    final key = '${t.token.clinicId}|${t.token.date}';
    final list = _byClinicDate.putIfAbsent(key, () => []);
    if (!list.contains(t.id)) list.add(t.id);
  }

  QueueToken _event(QueueToken t, String action, {Token? token, DateTime? arrivedAt, String? note, String? cancelReason}) =>
      t.copyWith(
        token: token,
        arrivedAt: arrivedAt,
        cancelReason: cancelReason,
        history: [...t.history, TokenEvent(action, _actor, _now, note: note)],
      );

  /// Keeps the queue day in line with its tokens (activeNumbers, current).
  void _syncDay(String clinicId, String doctorId, String date) {
    final key = '$doctorId|$date';
    final day = _days[key] ?? QueueDay.empty(clinicId, doctorId, date);
    final list = tokens(clinicId, date).where((t) => t.token.doctorId == doctorId).toList();
    final called = list.where((t) => t.status == TokenStatus.called).firstOrNull;
    final active = list.where((t) => t.status.isWaiting).map((t) => t.number).toList()..sort();
    var last = day.lastTokenNumber;
    for (final t in list) {
      if (t.number > last) last = t.number;
    }
    _days[key] = day.copyWith(
      currentToken: called?.number ?? day.currentToken,
      activeNumbers: active,
      lastTokenNumber: last,
      bookedCount: list.where((t) => t.status != TokenStatus.cancelled).length,
      updatedAt: _now,
    );
  }

  @override
  Future<void> session(String clinicId, String doctorId, SessionAction action) async {
    _requireUser();
    _requireWritable(clinicId);
    await _latency();
    final day = queueDay(clinicId, doctorId, _today);
    final status = switch (action) {
      SessionAction.start => SessionStatus.running,
      SessionAction.pause => SessionStatus.paused,
      SessionAction.end => SessionStatus.ended,
    };
    if (action == SessionAction.end) {
      // C-02: remaining Booked tokens become No-show.
      for (final t in tokens(clinicId, _today).where((t) => t.token.doctorId == doctorId && t.status == TokenStatus.booked)) {
        _put(_event(t, 'No-show (session ended)', token: t.token.copyWith(status: TokenStatus.noShow)));
      }
      final called = tokens(clinicId, _today).where((t) => t.token.doctorId == doctorId && t.status == TokenStatus.called);
      for (final t in called) {
        _put(_event(t, 'Completed', token: t.token.copyWith(status: TokenStatus.completed, completedAt: _now)));
      }
    }
    _days['$doctorId|$_today'] = day.copyWith(sessionStatus: status, updatedAt: _now);
    _syncDay(clinicId, doctorId, _today);
    _notify();
  }

  /// C-03 order: lowest Arrived first; if none, lowest Booked (Q-W03 open).
  QueueToken? _nextCandidate(List<QueueToken> list) {
    final arrived = list.where((t) => t.status == TokenStatus.arrived).toList()..sort((a, b) => a.number.compareTo(b.number));
    if (arrived.isNotEmpty) return arrived.first;
    final booked = list.where((t) => t.status == TokenStatus.booked).toList()..sort((a, b) => a.number.compareTo(b.number));
    return booked.firstOrNull;
  }

  @override
  Future<QueueToken?> next(String clinicId, String doctorId) async {
    _requireUser();
    _requireWritable(clinicId);
    final day = queueDay(clinicId, doctorId, _today);
    if (day.sessionStatus == SessionStatus.notStarted) throw const AppException('not-started', 'Start the session first.');
    if (day.sessionStatus == SessionStatus.paused) throw const AppException('paused', 'The session is paused. Resume it first.');
    if (day.sessionStatus == SessionStatus.ended) throw const AppException('ended', "Today's session has ended.");
    await _latency(120);

    final list = tokens(clinicId, _today).where((t) => t.token.doctorId == doctorId).toList();
    final current = list.where((t) => t.status == TokenStatus.called).firstOrNull;
    final candidate = _nextCandidate(list);
    if (current == null && candidate == null) throw const AppException('empty', 'No patients waiting.');

    _undo[doctorId] = _UndoNext(_now, day, [?current, ?candidate]);
    if (current != null) {
      _put(_event(current, 'Completed', token: current.token.copyWith(status: TokenStatus.completed, completedAt: _now)));
    }
    QueueToken? called;
    if (candidate != null) {
      called = _event(candidate, 'Called (Next)', token: candidate.token.copyWith(status: TokenStatus.called, calledAt: _now));
      _put(called);
      _days['$doctorId|$_today'] = queueDay(clinicId, doctorId, _today).copyWith(currentToken: candidate.number);
    }
    _syncDay(clinicId, doctorId, _today);
    _notify();
    return called;
  }

  @override
  Future<void> undoNext(String doctorId) async {
    final u = _undo.remove(doctorId);
    if (u == null || _now.difference(u.at).inSeconds >= 30) throw const AppException('undo-expired', 'Undo is no longer available.');
    await _latency(120);
    for (final t in u.before) {
      _put(t.copyWith(history: [...t.history, TokenEvent('Undo last Next', _actor, _now)]));
    }
    _days['$doctorId|${u.day.date}'] = u.day.copyWith(updatedAt: _now);
    _syncDay(u.day.clinicId, doctorId, u.day.date);
    _notify();
  }

  @override
  Future<void> tokenAction(String tokenId, TokenAction action, {String? reason}) async {
    _requireUser();
    final t = _tokens[tokenId];
    if (t == null) throw AppException.generic;
    if (action != TokenAction.reprint) _requireWritable(t.token.clinicId);
    if (t.status == TokenStatus.completed && action != TokenAction.reprint) {
      throw const AppException('completed', 'A completed token cannot be changed.'); // BW-4
    }
    await _latency();
    final tk = t.token;
    switch (action) {
      case TokenAction.arrive:
        _put(_event(t, 'Arrived', token: tk.copyWith(status: TokenStatus.arrived), arrivedAt: _now));
      case TokenAction.callNow:
        // BW-3: only one Called token per doctor; the current one is completed.
        final current = tokens(tk.clinicId, tk.date).where((x) => x.token.doctorId == tk.doctorId && x.status == TokenStatus.called);
        for (final c in current) {
          if (c.id != t.id) _put(_event(c, 'Completed', token: c.token.copyWith(status: TokenStatus.completed, completedAt: _now)));
        }
        _put(_event(t, t.status == TokenStatus.skipped ? 'Recalled' : 'Called (out of order)',
            token: tk.copyWith(status: TokenStatus.called, calledAt: _now), arrivedAt: t.arrivedAt ?? _now));
        _days['${tk.doctorId}|${tk.date}'] = queueDay(tk.clinicId, tk.doctorId, tk.date).copyWith(currentToken: tk.number);
      case TokenAction.skip:
        _put(_event(t, 'Skipped', token: tk.copyWith(status: TokenStatus.skipped)));
      case TokenAction.hold:
        _put(_event(t, 'On hold', token: tk.copyWith(status: TokenStatus.onHold), note: reason));
      case TokenAction.backToQueue:
        _put(_event(t, 'Back to queue', token: tk.copyWith(status: TokenStatus.arrived), arrivedAt: t.arrivedAt ?? _now));
      case TokenAction.cancel:
        _put(_event(t, 'Cancelled',
            token: tk.copyWith(status: TokenStatus.cancelled, cancelledAt: _now, cancelledBy: 'clinic'),
            note: reason,
            cancelReason: reason));
      case TokenAction.noShow:
        _put(_event(t, 'Marked No-show', token: tk.copyWith(status: TokenStatus.noShow)));
      case TokenAction.reprint:
        _put(_event(t, 'Reprinted'));
    }
    _syncDay(tk.clinicId, tk.doctorId, tk.date);
    _notify();
  }

  @override
  Future<QueueToken> createWalkIn(String clinicId, String doctorId, {String? patientId, NewPatient? newPatient}) async {
    _requireUser();
    _requireWritable(clinicId);
    final doctor = _doctors[doctorId];
    if (doctor == null) throw AppException.generic;
    final day = queueDay(clinicId, doctorId, _today);
    if (day.sessionStatus == SessionStatus.ended) throw const AppException('ended', "Today's session has ended for this doctor.");
    if (day.lastTokenNumber >= doctor.maxTokensPerDay) {
      throw AppException('tokens-full', 'All ${doctor.maxTokensPerDay} tokens for today are used.');
    }
    await _latency(250);

    Patient p;
    if (patientId != null) {
      p = _patients[patientId] ?? (throw AppException.generic);
    } else {
      final n = newPatient!;
      p = Patient(
        id: _id('p'),
        ownerUid: _patients.values.where((x) => x.phone == n.phone).map((x) => x.ownerUid).nonNulls.firstOrNull,
        phone: n.phone,
        name: n.name.trim(),
        birthYear: n.age == null ? null : _now.year - n.age!,
        gender: n.gender,
        relation: n.relation,
        createdAt: _now,
      );
      _patients[p.id] = p;
    }
    _patientClinics.putIfAbsent(p.id, () => {}).add(clinicId);

    // BW-2: one sequence per doctor per day, shared with app bookings.
    final number = day.lastTokenNumber + 1;
    _days['$doctorId|$_today'] = day.copyWith(lastTokenNumber: number);
    final token = QueueToken(
      token: Token(
        id: 't_${doctorId}_${_today}_$number',
        clinicId: clinicId,
        doctorId: doctorId,
        date: _today,
        number: number,
        tokenPrefix: doctor.tokenPrefix,
        patientId: p.id,
        patientSnapshot: PatientSnapshot.of(p),
        bookedByUserId: null,
        status: TokenStatus.arrived,
        createdAt: _now,
      ),
      source: TokenSource.walkIn,
      arrivedAt: _now,
      history: [TokenEvent('Walk-in created · Arrived', _actor, _now)],
    );
    _put(token);
    _syncDay(clinicId, doctorId, _today);
    _notify();
    return token;
  }

  @override
  Future<void> setFollowUp(String tokenId, String dueDate, {String? note}) async {
    _requireUser();
    final t = _tokens[tokenId] ?? (throw AppException.generic);
    await _latency();
    final existing = _followUps.values
        .where((f) => f.patientId == t.token.patientId && f.doctorId == t.token.doctorId && f.status == FollowUpStatus.pending)
        .firstOrNull;
    if (existing != null) _followUps.remove(existing.id);
    final f = FollowUp(
      id: _id('f'),
      ownerUid: _patients[t.token.patientId]?.ownerUid ?? '',
      patientId: t.token.patientId,
      clinicId: t.token.clinicId,
      doctorId: t.token.doctorId,
      dueDate: dueDate,
      note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
    );
    _followUps[f.id] = f;
    _put(_event(t, 'Follow-up set', note: Fmt0.day(dueDate)));
    _notify();
  }

  @override
  Future<void> updatePatient(String clinicId, String patientId, {required String name, int? birthYear, required Gender gender}) async {
    _requireUser();
    final p = _patients[patientId] ?? (throw AppException.generic);
    await _latency();
    _patients[patientId] = p.copyWith(name: name.trim(), birthYear: birthYear, gender: gender);
    _log(clinicId, 'edited patient details', name.trim());
    _notify();
  }

  // ===================================================================
  // Clinic admin
  // ===================================================================

  @override
  Future<Doctor> saveDoctor(String clinicId, Doctor doctor, {bool isNew = false}) async {
    _requireUser();
    await _latency();
    var d = doctor;
    if (isNew) {
      final c = _clinics[clinicId]!;
      final letter = c.nextDoctorLetter < _letters.length ? _letters[c.nextDoctorLetter] : 'Z${c.nextDoctorLetter}';
      _clinics[clinicId] = c.copyWith(nextDoctorLetter: c.nextDoctorLetter + 1);
      d = Doctor(
        id: _id('d'),
        clinicId: clinicId,
        name: doctor.name,
        speciality: doctor.speciality,
        qualification: doctor.qualification,
        tokenPrefix: letter, // BW-7: auto, never reused
        avgConsultMinutes: doctor.avgConsultMinutes,
        maxTokensPerDay: doctor.maxTokensPerDay,
        bookingWindowDays: doctor.bookingWindowDays,
        schedule: doctor.schedule,
        sortOrder: doctors(clinicId, includeInactive: true).length + 1,
      );
      _log(clinicId, 'added doctor', d.name);
    } else {
      _log(clinicId, 'updated doctor', d.name);
    }
    _doctors[d.id] = d;
    _syncDoctorCount(clinicId);
    _notify();
    return d;
  }

  void _syncDoctorCount(String clinicId) {
    final c = _clinics[clinicId];
    if (c == null) return;
    _clinics[clinicId] = c.copyWith(clinic: clinicWith(c.clinic, doctorCount: doctors(clinicId).length));
  }

  Doctor _copyDoctor(Doctor d, {List<String>? onLeaveDates, bool? active}) => Doctor(
        id: d.id,
        clinicId: d.clinicId,
        name: d.name,
        speciality: d.speciality,
        qualification: d.qualification,
        tokenPrefix: d.tokenPrefix,
        avgConsultMinutes: d.avgConsultMinutes,
        maxTokensPerDay: d.maxTokensPerDay,
        bookingWindowDays: d.bookingWindowDays,
        schedule: d.schedule,
        onLeaveDates: onLeaveDates ?? d.onLeaveDates,
        active: active ?? d.active,
        sortOrder: d.sortOrder,
      );

  @override
  Future<int> addLeave(String doctorId, String date) async {
    _requireUser();
    final d = _doctors[doctorId] ?? (throw AppException.generic);
    await _latency();
    if (!d.onLeaveDates.contains(date)) {
      _doctors[doctorId] = _copyDoctor(d, onLeaveDates: [...d.onLeaveDates, date]..sort());
      _log(d.clinicId, 'added leave', '${d.name} · ${Fmt0.day(date)}');
    }
    _notify();
    return tokens(d.clinicId, date).where((t) => t.token.doctorId == doctorId && t.status.isActive).length;
  }

  @override
  Future<void> removeLeave(String doctorId, String date) async {
    _requireUser();
    final d = _doctors[doctorId] ?? (throw AppException.generic);
    await _latency();
    _doctors[doctorId] = _copyDoctor(d, onLeaveDates: d.onLeaveDates.where((x) => x != date).toList());
    _log(d.clinicId, 'removed leave', '${d.name} · ${Fmt0.day(date)}');
    _notify();
  }

  @override
  Future<int> cancelTokensOn(String doctorId, String date, String reason) async {
    _requireUser();
    final d = _doctors[doctorId] ?? (throw AppException.generic);
    await _latency(300);
    var n = 0;
    for (final t in tokens(d.clinicId, date).where((t) => t.token.doctorId == doctorId && t.status.isActive)) {
      _put(_event(t, 'Cancelled', token: t.token.copyWith(status: TokenStatus.cancelled, cancelledAt: _now, cancelledBy: 'clinic'), note: reason, cancelReason: reason));
      n++;
    }
    _syncDay(d.clinicId, doctorId, date);
    _log(d.clinicId, 'cancelled $n tokens', '${d.name} · ${Fmt0.day(date)}');
    _notify();
    return n;
  }

  @override
  Future<void> setDoctorActive(String doctorId, bool active) async {
    _requireUser();
    final d = _doctors[doctorId] ?? (throw AppException.generic);
    await _latency();
    _doctors[doctorId] = _copyDoctor(d, active: active);
    _syncDoctorCount(d.clinicId);
    _log(d.clinicId, active ? 'reactivated doctor' : 'deactivated doctor', d.name);
    _notify();
  }

  @override
  Future<void> inviteStaff(String clinicId, {required String name, required String email, required StaffRole role, String? doctorId}) async {
    final u = _requireUser();
    final e = email.trim().toLowerCase();
    if (_staff.values.any((s) => s.email.toLowerCase() == e)) {
      throw const AppException('email-taken', 'An account with this email already exists.');
    }
    await _latency(350);
    final s = StaffAccount(
      uid: _id('u'),
      name: name.trim(),
      email: e,
      role: role,
      clinicId: clinicId,
      doctorId: role == StaffRole.doctor ? doctorId : null,
      status: StaffStatus.invited,
      invitedBy: u.name,
      createdAt: _now,
    );
    _staff[s.uid] = s;
    _log(clinicId, 'invited ${role.label.toLowerCase()}', '${s.name} <$e>');
    _notify();
  }

  @override
  Future<void> resendInvite(String uid) async {
    _requireUser();
    final s = _staff[uid] ?? (throw AppException.generic);
    await _latency(300);
    _log(s.clinicId, 'resent invite', s.name);
    _notify();
  }

  @override
  Future<void> updateStaff(String uid, {StaffRole? role, String? doctorId, StaffStatus? status}) async {
    final u = _requireUser();
    final s = _staff[uid] ?? (throw AppException.generic);
    if (u.uid == uid || (s.isMainAccount && u.role != StaffRole.superAdmin)) {
      throw const AppException('self', "You can't change this account.");
    }
    await _latency();
    _staff[uid] = s.copyWith(role: role, doctorId: doctorId, status: status);
    if (role != null && role != s.role) _log(s.clinicId, 'changed role to ${role.label}', s.name);
    if (status != null && status != s.status) {
      _log(s.clinicId, status == StaffStatus.disabled ? 'disabled staff' : 'enabled staff', s.name);
    }
    _notify();
  }

  @override
  Future<void> updateClinicSettings(String clinicId, {String? address, String? area, String? phone, PrintFormat? printFormat, String? name}) async {
    _requireUser();
    final c = _clinics[clinicId] ?? (throw AppException.generic);
    await _latency();
    _clinics[clinicId] = c.copyWith(
      clinic: clinicWith(c.clinic, address: address, area: area, phone: phone, name: name),
      printFormat: printFormat,
    );
    _log(clinicId, 'updated clinic settings', c.clinic.name);
    _notify();
  }

  @override
  Future<void> logExport(String clinicId, String range) async {
    _log(clinicId, 'exported visits', range);
    _notify();
  }

  // ===================================================================
  // Super admin
  // ===================================================================

  @override
  Future<ClinicAccount> createClinic(NewClinicDraft draft) async {
    _requireUser();
    final email = draft.email.trim().toLowerCase();
    if (_staff.values.any((s) => s.email.toLowerCase() == email)) {
      throw const AppException('email-taken', 'An account with this email already exists.');
    }
    await _latency(600);
    final id = _id('c');
    final clinic = ClinicAccount(
      clinic: Clinic(
        id: id,
        name: draft.name.trim(),
        area: draft.area.trim(),
        city: draft.city.trim(),
        address: draft.address.trim(),
        phone: draft.phone.trim(),
        status: ClinicStatus.pilot,
        doctorCount: draft.doctors.length,
      ),
      email: email,
      ownerName: draft.ownerName.trim(),
      ownerPhone: draft.ownerPhone.trim(),
      plan: Plan.pilot,
      planAfterPilot: draft.planAfterPilot,
      monthlyFee: draft.monthlyFee,
      billingDay: draft.billingDay,
      pilotEndsAt: _now.add(Duration(days: draft.pilotDays)),
      printFormat: draft.printFormat,
      createdAt: _now,
    );
    _clinics[id] = clinic;
    _log(id, 'created clinic', clinic.clinic.name);
    for (final d in draft.doctors) {
      await saveDoctor(id, d, isNew: true);
    }
    _staff['u_${id}_main'] = StaffAccount(
      uid: 'u_${id}_main',
      name: draft.ownerName.trim(),
      email: email,
      role: StaffRole.clinicAdmin,
      clinicId: id,
      status: StaffStatus.invited,
      invitedBy: _user?.name,
      createdAt: _now,
      isMainAccount: true,
    );
    _log(id, 'invited clinic admin', '${draft.ownerName.trim()} <$email>');
    _notify();
    return _clinics[id]!;
  }

  @override
  Future<void> setClinicStatus(String clinicId, ClinicStatus status, {String? reason}) async {
    _requireUser();
    final c = _clinics[clinicId] ?? (throw AppException.generic);
    await _latency();
    _clinics[clinicId] = c.copyWith(clinic: clinicWith(c.clinic, status: status));
    final verb = switch (status) {
      ClinicStatus.suspended => 'suspended clinic',
      ClinicStatus.cancelled => 'cancelled clinic',
      _ => 'reactivated clinic',
    };
    _log(clinicId, verb, reason == null ? c.clinic.name : '${c.clinic.name} · $reason');
    _notify();
  }

  @override
  Future<void> changePlan(String clinicId, {Plan? plan, int? monthlyFee}) async {
    _requireUser();
    final c = _clinics[clinicId] ?? (throw AppException.generic);
    await _latency();
    _clinics[clinicId] = c.copyWith(plan: plan, monthlyFee: monthlyFee);
    _log(clinicId, 'changed plan', '${(plan ?? c.plan).label} · ${monthlyFee ?? c.monthlyFee}');
    _notify();
  }

  @override
  Future<void> extendPilot(String clinicId, int days) async {
    _requireUser();
    final c = _clinics[clinicId] ?? (throw AppException.generic);
    await _latency();
    final base = c.pilotEndsAt != null && c.pilotEndsAt!.isAfter(_now) ? c.pilotEndsAt! : _now;
    _clinics[clinicId] = c.copyWith(pilotEndsAt: base.add(Duration(days: days)), clinic: clinicWith(c.clinic, status: ClinicStatus.pilot));
    _log(clinicId, 'extended pilot by $days days', c.clinic.name);
    _notify();
  }

  @override
  Future<void> recordPayment(String invoiceId, Payment payment) async {
    _requireUser();
    final inv = _invoices[invoiceId] ?? (throw AppException.generic);
    await _latency(300);
    _invoices[invoiceId] = inv.copyWith(status: InvoiceStatus.paid, payment: payment);
    final c = _clinics[inv.clinicId]!;
    // A-05: paid until +1 month, clinic Active.
    final from = c.paidUntil != null && c.paidUntil!.isAfter(_now) ? c.paidUntil! : _now;
    final stillOpen = _invoices.values.any((i) => i.clinicId == inv.clinicId && i.isOpen && i.dueDate.isBefore(_now));
    _clinics[inv.clinicId] = c.copyWith(
      paidUntil: DateTime(from.year, from.month + 1, from.day),
      clinic: clinicWith(c.clinic, status: stillOpen ? c.status : ClinicStatus.active),
      plan: c.plan == Plan.pilot ? c.planAfterPilot : null,
    );
    _log(inv.clinicId, 'recorded payment', '${inv.month} · Rs ${payment.amount} · ${payment.method.label}');
    _notify();
  }

  @override
  Future<void> waiveInvoice(String invoiceId, String reason) async {
    _requireUser();
    final inv = _invoices[invoiceId] ?? (throw AppException.generic);
    await _latency();
    _invoices[invoiceId] = inv.copyWith(status: InvoiceStatus.waived, waiveReason: reason);
    _log(inv.clinicId, 'waived invoice', '${inv.month} · $reason');
    _notify();
  }

  @override
  Future<void> giveExtension(String invoiceId, DateTime newDueDate) async {
    _requireUser();
    final inv = _invoices[invoiceId] ?? (throw AppException.generic);
    await _latency();
    _invoices[invoiceId] = inv.copyWith(status: InvoiceStatus.unpaid, dueDate: newDueDate);
    final c = _clinics[inv.clinicId]!;
    if (c.status == ClinicStatus.grace || c.status == ClinicStatus.suspended) {
      _clinics[inv.clinicId] = c.copyWith(clinic: clinicWith(c.clinic, status: ClinicStatus.active));
    }
    _log(inv.clinicId, 'gave payment extension', '${inv.month} · due ${Fmt0.date(newDueDate)}');
    _notify();
  }

  @override
  Future<void> saveSettings(AdminSettings settings) async {
    _requireUser();
    await _latency();
    _settings = settings;
    _log(null, 'updated admin settings', 'Plans & billing');
    _notify();
  }

  // ===================================================================
  // Live simulation: a patient books from the app now and then.
  // ===================================================================

  void _simulateAppBooking() {
    final running = _doctors.values.where((d) {
      if (d.clinicId != 'c_alshifa' || !d.active) return false;
      return queueDay(d.clinicId, d.id, _today).sessionStatus == SessionStatus.running;
    }).toList();
    if (running.isEmpty) return;
    final d = running[_rnd.nextInt(running.length)];
    final day = queueDay(d.clinicId, d.id, _today);
    if (day.lastTokenNumber >= d.maxTokensPerDay) return;
    final pool = _patients.values.where((p) => p.ownerUid != null).toList();
    final p = pool[_rnd.nextInt(pool.length)];
    final busy = tokens(d.clinicId, _today).any((t) => t.token.patientId == p.id && t.token.doctorId == d.id && t.status.isActive);
    if (busy) return;
    _addToken(d, _today, day.lastTokenNumber + 1, p, TokenSource.app, TokenStatus.booked, _now);
    _patientClinics.putIfAbsent(p.id, () => {}).add(d.clinicId);
    _syncDay(d.clinicId, d.id, _today);
    _notify();
  }

  // ===================================================================
  // Seed
  // ===================================================================

  QueueToken _addToken(Doctor d, String date, int number, Patient p, TokenSource source, TokenStatus status, DateTime createdAt,
      {DateTime? arrivedAt, DateTime? calledAt, DateTime? completedAt}) {
    final events = <TokenEvent>[
      TokenEvent(source == TokenSource.app ? 'Booked in app' : 'Walk-in created', source == TokenSource.app ? p.name : 'Reception', createdAt),
      if (arrivedAt != null && source == TokenSource.app) TokenEvent('Arrived', 'Reception', arrivedAt),
      if (calledAt != null) TokenEvent('Called', 'Reception', calledAt),
      if (completedAt != null) TokenEvent('Completed', 'Reception', completedAt),
    ];
    final t = QueueToken(
      token: Token(
        id: 't_${d.id}_${date}_$number',
        clinicId: d.clinicId,
        doctorId: d.id,
        date: date,
        number: number,
        tokenPrefix: d.tokenPrefix,
        patientId: p.id,
        patientSnapshot: PatientSnapshot.of(p),
        bookedByUserId: source == TokenSource.app ? p.ownerUid : null,
        status: status,
        createdAt: createdAt,
        calledAt: calledAt,
        completedAt: completedAt,
        cancelledAt: status == TokenStatus.cancelled ? createdAt.add(const Duration(minutes: 40)) : null,
        cancelledBy: status == TokenStatus.cancelled ? 'patient' : null,
      ),
      source: source,
      arrivedAt: arrivedAt,
      history: events,
    );
    _put(t);
    _patientClinics.putIfAbsent(p.id, () => {}).add(d.clinicId);
    final key = '${d.id}|$date';
    final day = _days[key] ?? QueueDay.empty(d.clinicId, d.id, date);
    if (number > day.lastTokenNumber) _days[key] = day.copyWith(lastTokenNumber: number);
    return t;
  }

  void _seed() {
    final now = _now;
    final today = dayKey(now);
    DateTime at(DateTime day, int minutes) => DateTime(day.year, day.month, day.day).add(Duration(minutes: minutes));
    String hm(int m) => minutesToHhmm(m.clamp(0, 23 * 60 + 59));

    final runningNow = DaySchedule(hm((now.hour - 2) * 60), hm((now.hour + 3) * 60));
    final laterToday = DaySchedule(hm((now.hour + 1) * 60), hm((now.hour + 4) * 60));
    Map<String, DaySchedule?> week(DaySchedule normal, {DaySchedule? today, Set<String> off = const {'sun'}}) => {
          for (final k in weekdayKeys) k: k == weekdayKey(now) && today != null ? today : (off.contains(k) ? null : normal),
        };
    const evening = DaySchedule('17:00', '21:00');

    // ---- Clinics ----
    ClinicAccount acc(Clinic c, String email, String owner, String phone,
            {Plan plan = Plan.basic, int fee = 3000, int paidMonths = 0, int pilotDaysLeft = 0, int ageDays = 120, int letters = 1}) =>
        ClinicAccount(
          clinic: c,
          email: email,
          ownerName: owner,
          ownerPhone: phone,
          plan: plan,
          monthlyFee: fee,
          paidUntil: paidMonths == 0 ? null : DateTime(now.year, now.month + paidMonths, 1),
          pilotEndsAt: plan == Plan.pilot ? now.add(Duration(days: pilotDaysLeft)) : now.subtract(Duration(days: ageDays - 30)),
          createdAt: now.subtract(Duration(days: ageDays)),
          nextDoctorLetter: letters,
        );
    final list = [
      acc(const Clinic(id: 'c_alshifa', name: 'Al-Shifa Clinic', area: 'Johar Town', city: 'Lahore', address: 'Main Boulevard, Johar Town', phone: '042-1234567', status: ClinicStatus.active, doctorCount: 3),
          'clinic@alshifa.pk', 'Dr. Tariq Mehmood', '+923004567890', paidMonths: 1, letters: 3, ageDays: 150),
      acc(const Clinic(id: 'c_citycare', name: 'City Care Clinic', area: 'Gulberg', city: 'Lahore', address: 'MM Alam Road, Gulberg III', phone: '042-3576543', status: ClinicStatus.pilot, doctorCount: 2),
          'clinic@citycare.pk', 'Nasir Ali', '+923214567812', plan: Plan.pilot, pilotDaysLeft: 12, ageDays: 18, letters: 2),
      acc(const Clinic(id: 'c_modeltown', name: 'Model Town Medical', area: 'Model Town', city: 'Lahore', address: 'Link Road, Model Town', phone: '042-3588812', status: ClinicStatus.grace, doctorCount: 1),
          'clinic@modeltownmedical.pk', 'Dr. Usman Tariq', '+923335551234', ageDays: 100),
      acc(const Clinic(id: 'c_dha', name: 'DHA Family Clinic', area: 'DHA Phase 5', city: 'Lahore', address: 'Sector C, DHA Phase 5', phone: '042-3712990', status: ClinicStatus.active, doctorCount: 2),
          'clinic@dhafamily.pk', 'Mrs. Rubina Shah', '+923008889911', plan: Plan.premium, fee: 5000, paidMonths: 1, letters: 2, ageDays: 95),
      acc(const Clinic(id: 'c_rehman', name: 'Rehman Clinic', area: 'Iqbal Town', city: 'Lahore', address: 'Moon Market, Iqbal Town', phone: '042-3781100', status: ClinicStatus.suspended, doctorCount: 1),
          'clinic@rehmanclinic.pk', 'Dr. Abdul Rehman', '+923451112233', ageDays: 110),
      acc(const Clinic(id: 'c_clifton', name: 'Clifton Care Clinic', area: 'Clifton', city: 'Karachi', address: 'Block 5, Clifton', phone: '021-35871234', status: ClinicStatus.pilot, doctorCount: 1),
          'clinic@cliftoncare.pk', 'Zara Hussain', '+923009998877', plan: Plan.pilot, pilotDaysLeft: 25, ageDays: 5),
    ];
    for (final c in list) {
      _clinics[c.id] = c;
    }

    // ---- Doctors ----
    final docs = [
      Doctor(id: 'd_ayesha', clinicId: 'c_alshifa', name: 'Dr. Ayesha Malik', speciality: 'General Physician', qualification: 'MBBS, FCPS', tokenPrefix: 'A', maxTokensPerDay: 40, schedule: week(evening, today: runningNow), sortOrder: 1),
      Doctor(id: 'd_kamran', clinicId: 'c_alshifa', name: 'Dr. Kamran Ahmed', speciality: 'Child Specialist', qualification: 'MBBS, DCH', tokenPrefix: 'B', schedule: week(const DaySchedule('10:00', '14:00'), today: runningNow), onLeaveDates: [dayKey(now.add(const Duration(days: 3)))], sortOrder: 2),
      Doctor(id: 'd_sana', clinicId: 'c_alshifa', name: 'Dr. Sana Riaz', speciality: 'Gynecologist', qualification: 'MBBS, FCPS', tokenPrefix: 'C', avgConsultMinutes: 15, maxTokensPerDay: 30, schedule: week(const DaySchedule('18:00', '21:00'), today: laterToday), sortOrder: 3),
      Doctor(id: 'd_imran', clinicId: 'c_citycare', name: 'Dr. Imran Qureshi', speciality: 'General Physician', tokenPrefix: 'A', schedule: week(const DaySchedule('16:00', '22:00'), today: runningNow), sortOrder: 1),
      Doctor(id: 'd_farah', clinicId: 'c_citycare', name: 'Dr. Farah Naz', speciality: 'Dermatologist', tokenPrefix: 'B', avgConsultMinutes: 12, schedule: week(const DaySchedule('11:00', '15:00')), sortOrder: 2),
      Doctor(id: 'd_usman', clinicId: 'c_modeltown', name: 'Dr. Usman Tariq', speciality: 'ENT Specialist', tokenPrefix: 'A', schedule: week(const DaySchedule('16:00', '20:00'), off: {'sat', 'sun'}), sortOrder: 1),
      Doctor(id: 'd_hina', clinicId: 'c_dha', name: 'Dr. Hina Shah', speciality: 'Pediatrician', tokenPrefix: 'A', schedule: week(const DaySchedule('09:00', '13:00'), off: {}), sortOrder: 1),
      Doctor(id: 'd_bilal', clinicId: 'c_dha', name: 'Dr. Bilal Ahmed', speciality: 'General Physician', tokenPrefix: 'B', schedule: week(evening, today: runningNow), sortOrder: 2),
      Doctor(id: 'd_rehman', clinicId: 'c_rehman', name: 'Dr. Abdul Rehman', speciality: 'General Physician', tokenPrefix: 'A', schedule: week(evening), sortOrder: 1),
      Doctor(id: 'd_zara', clinicId: 'c_clifton', name: 'Dr. Zara Hussain', speciality: 'General Physician', tokenPrefix: 'A', schedule: week(evening, today: runningNow), sortOrder: 1),
    ];
    for (final d in docs) {
      _doctors[d.id] = d;
    }

    // ---- Patients (families on one phone) ----
    const first = ['Ali', 'Fatima', 'Ahmed', 'Ayesha', 'Hassan', 'Zainab', 'Usman', 'Maryam', 'Bilal', 'Hira', 'Umar', 'Sana', 'Hamza', 'Iqra', 'Saad', 'Mehwish', 'Faisal', 'Rabia', 'Imran', 'Nadia', 'Kashif', 'Amna', 'Tariq', 'Saima', 'Waqas', 'Noor', 'Asad', 'Khadija', 'Junaid', 'Sadia'];
    const last = ['Khan', 'Ahmed', 'Malik', 'Butt', 'Sheikh', 'Chaudhry', 'Raza', 'Hussain', 'Iqbal', 'Qureshi', 'Mirza', 'Javed'];
    final families = <List<Patient>>[];
    for (var f = 0; f < 70; f++) {
      final phone = '+923${(_rnd.nextInt(5)).toString()}${(10000000 + _rnd.nextInt(89999999)).toString().padLeft(8, '0')}';
      final surname = last[_rnd.nextInt(last.length)];
      final owner = f % 6 == 5 ? null : 'uid_$f'; // some families only visit as walk-ins
      final size = 1 + _rnd.nextInt(3);
      final fam = <Patient>[];
      for (var i = 0; i < size; i++) {
        final relation = i == 0 ? Relation.self : [Relation.mother, Relation.son, Relation.daughter, Relation.spouse, Relation.father][_rnd.nextInt(5)];
        final g = switch (relation) {
          Relation.mother || Relation.daughter => Gender.female,
          Relation.father || Relation.son => Gender.male,
          _ => _rnd.nextBool() ? Gender.male : Gender.female,
        };
        final age = switch (relation) {
          Relation.son || Relation.daughter => 2 + _rnd.nextInt(14),
          Relation.mother || Relation.father => 50 + _rnd.nextInt(25),
          _ => 20 + _rnd.nextInt(30),
        };
        final p = Patient(
          id: 'p_${f}_$i',
          ownerUid: owner,
          phone: phone,
          name: '${first[_rnd.nextInt(first.length)]} $surname',
          birthYear: now.year - age,
          gender: g,
          relation: relation,
          createdAt: now.subtract(Duration(days: 200 - f)),
        );
        _patients[p.id] = p;
        fam.add(p);
      }
      families.add(fam);
    }
    final all = _patients.values.toList();
    Patient pick() => all[_rnd.nextInt(all.length)];

    // ---- 30 days of history for every doctor ----
    for (final d in docs) {
      final busy = d.clinicId == 'c_alshifa' ? 16 : 7;
      for (var back = 30; back >= 1; back--) {
        final date = now.subtract(Duration(days: back));
        final s = d.scheduleOn(date);
        if (s == null || _clinics[d.clinicId]!.createdAt.isAfter(date)) continue;
        final n = busy ~/ 2 + _rnd.nextInt(busy);
        final key = dayKey(date);
        for (var i = 1; i <= n; i++) {
          final p = pick();
          final walkIn = _rnd.nextInt(10) < 4;
          final roll = _rnd.nextInt(20);
          final status = roll == 0 ? TokenStatus.cancelled : (roll == 1 ? TokenStatus.noShow : TokenStatus.completed);
          final arrive = at(date, s.startMinutes + (i - 1) * d.avgConsultMinutes ~/ 2 + _rnd.nextInt(10));
          final created = walkIn ? arrive : arrive.subtract(Duration(minutes: 30 + _rnd.nextInt(600)));
          final called = status == TokenStatus.completed ? arrive.add(Duration(minutes: 8 + _rnd.nextInt(35))) : null;
          _addToken(d, key, i, p, walkIn ? TokenSource.walkIn : TokenSource.app, status, created,
              arrivedAt: status == TokenStatus.completed ? arrive : null,
              calledAt: called,
              completedAt: called?.add(Duration(minutes: d.avgConsultMinutes)));
        }
        _days['${d.id}|$key'] = queueDay(d.clinicId, d.id, key).copyWith(sessionStatus: SessionStatus.ended);
        _syncDay(d.clinicId, d.id, key);
      }
    }

    // ---- Today ----
    void today0(Doctor d, SessionStatus session, {int done = 0, bool called = false, int waiting = 0}) {
      final s = d.scheduleOn(now) ?? runningNow;
      final start = at(now, s.startMinutes);
      var number = 0;
      for (var i = 0; i < done; i++) {
        number++;
        final arrive = start.add(Duration(minutes: i * 6));
        final c = arrive.add(Duration(minutes: 10 + _rnd.nextInt(20)));
        _addToken(d, today, number, pick(), _rnd.nextBool() ? TokenSource.app : TokenSource.walkIn, TokenStatus.completed,
            arrive.subtract(const Duration(hours: 3)), arrivedAt: arrive, calledAt: c, completedAt: c.add(Duration(minutes: d.avgConsultMinutes)));
      }
      if (called) {
        number++;
        _addToken(d, today, number, pick(), TokenSource.app, TokenStatus.called, now.subtract(const Duration(hours: 4)),
            arrivedAt: now.subtract(const Duration(minutes: 35)), calledAt: now.subtract(const Duration(minutes: 4)));
      }
      for (var i = 0; i < waiting; i++) {
        number++;
        final r = i % 7;
        final walk = session != SessionStatus.notStarted && (r == 2 || r == 5);
        final status = session == SessionStatus.notStarted
            ? TokenStatus.booked
            : switch (r) {
          0 || 2 => TokenStatus.arrived,
          1 => TokenStatus.booked,
          3 => i == 3 ? TokenStatus.skipped : TokenStatus.booked,
          4 => i == 4 ? TokenStatus.onHold : TokenStatus.booked,
          _ => walk ? TokenStatus.arrived : TokenStatus.booked,
        };
        final arrived = status == TokenStatus.booked ? null : now.subtract(Duration(minutes: 30 - i));
        _addToken(d, today, number, pick(), walk ? TokenSource.walkIn : TokenSource.app, status,
            walk ? (arrived ?? now) : now.subtract(Duration(hours: 6, minutes: i * 9)), arrivedAt: arrived);
      }
      _days['${d.id}|$today'] = queueDay(d.clinicId, d.id, today).copyWith(sessionStatus: session);
      _syncDay(d.clinicId, d.id, today);
    }

    today0(_doctors['d_ayesha']!, SessionStatus.running, done: 6, called: true, waiting: 11);
    today0(_doctors['d_kamran']!, SessionStatus.paused, done: 3, called: true, waiting: 4);
    today0(_doctors['d_sana']!, SessionStatus.notStarted, waiting: 6);
    today0(_doctors['d_imran']!, SessionStatus.running, done: 2, called: true, waiting: 5);
    today0(_doctors['d_bilal']!, SessionStatus.running, done: 1, called: true, waiting: 3);
    today0(_doctors['d_zara']!, SessionStatus.running, done: 4, called: true, waiting: 4);

    // A booking for another date (check-in warning "token for another date").
    final tomorrow = dayKey(now.add(const Duration(days: 1)));
    _addToken(_doctors['d_ayesha']!, tomorrow, 1, families[0][0], TokenSource.app, TokenStatus.booked, now.subtract(const Duration(hours: 1)));
    _addToken(_doctors['d_ayesha']!, tomorrow, 2, families[1][0], TokenSource.app, TokenStatus.booked, now.subtract(const Duration(minutes: 30)));
    _syncDay('c_alshifa', 'd_ayesha', tomorrow);
    // Kamran's leave in 3 days already has bookings (leave warning demo).
    final leaveDay = dayKey(now.add(const Duration(days: 3)));
    _addToken(_doctors['d_kamran']!, leaveDay, 1, families[2][0], TokenSource.app, TokenStatus.booked, now);
    _syncDay('c_alshifa', 'd_kamran', leaveDay);

    // ---- Follow-ups (C-09) ----
    final completed = _tokens.values.where((t) => t.token.clinicId == 'c_alshifa' && t.status == TokenStatus.completed).toList();
    const notes = ['Review', 'Bring reports', 'BP check', 'Blood test review', null];
    for (var i = 0; i < 24 && i < completed.length; i++) {
      final t = completed[(i * 37) % completed.length];
      final due = dayKey(now.add(Duration(days: i % 3 == 0 ? 0 : (i % 3 == 1 ? 1 + i % 9 : -(1 + i % 6)))));
      final status = i % 3 == 2 ? (i % 2 == 0 ? FollowUpStatus.done : FollowUpStatus.pending) : (i % 5 == 0 ? FollowUpStatus.booked : FollowUpStatus.pending);
      _followUps['f_$i'] = FollowUp(
        id: 'f_$i',
        ownerUid: _patients[t.token.patientId]!.ownerUid ?? '',
        patientId: t.token.patientId,
        clinicId: t.token.clinicId,
        doctorId: t.token.doctorId,
        dueDate: due,
        status: status,
        note: notes[i % notes.length],
      );
    }

    // ---- Staff (§5, C-12) ----
    StaffAccount staff(String uid, String name, String email, StaffRole role, String? clinicId,
            {String? doctorId, StaffStatus status = StaffStatus.active, bool main = false, int ageDays = 90, String? invitedBy = 'Sarbuland'}) =>
        StaffAccount(
          uid: uid,
          name: name,
          email: email,
          role: role,
          clinicId: clinicId,
          doctorId: doctorId,
          status: status,
          invitedBy: invitedBy,
          createdAt: now.subtract(Duration(days: ageDays)),
          lastLoginAt: status == StaffStatus.active ? now.subtract(Duration(hours: 1 + ageDays % 30)) : null,
          isMainAccount: main,
        );
    for (final s in [
      staff('u_admin', 'Sarbuland', 'admin@asani.app', StaffRole.superAdmin, null, ageDays: 200, invitedBy: null),
      staff('u_alshifa_main', 'Dr. Tariq Mehmood', 'clinic@alshifa.pk', StaffRole.clinicAdmin, 'c_alshifa', main: true, ageDays: 150),
      staff('u_asma', 'Asma Khan', 'reception@alshifa.pk', StaffRole.receptionist, 'c_alshifa', ageDays: 140, invitedBy: 'Dr. Tariq Mehmood'),
      staff('u_ayesha', 'Dr. Ayesha Malik', 'ayesha@alshifa.pk', StaffRole.doctor, 'c_alshifa', doctorId: 'd_ayesha', ageDays: 120, invitedBy: 'Dr. Tariq Mehmood'),
      staff('u_bilal_r', 'Bilal Hussain', 'evening@alshifa.pk', StaffRole.receptionist, 'c_alshifa', status: StaffStatus.invited, ageDays: 2, invitedBy: 'Dr. Tariq Mehmood'),
      staff('u_old', 'Kiran Javed', 'kiran@alshifa.pk', StaffRole.receptionist, 'c_alshifa', status: StaffStatus.disabled, ageDays: 130, invitedBy: 'Dr. Tariq Mehmood'),
      staff('u_citycare_main', 'Nasir Ali', 'clinic@citycare.pk', StaffRole.clinicAdmin, 'c_citycare', main: true, ageDays: 18),
      staff('u_modeltown_main', 'Dr. Usman Tariq', 'clinic@modeltownmedical.pk', StaffRole.clinicAdmin, 'c_modeltown', main: true, ageDays: 100),
      staff('u_dha_main', 'Mrs. Rubina Shah', 'clinic@dhafamily.pk', StaffRole.clinicAdmin, 'c_dha', main: true, ageDays: 95),
      staff('u_dha_rec', 'Saima Noor', 'front@dhafamily.pk', StaffRole.receptionist, 'c_dha', ageDays: 80, invitedBy: 'Mrs. Rubina Shah'),
      staff('u_rehman_main', 'Dr. Abdul Rehman', 'clinic@rehmanclinic.pk', StaffRole.clinicAdmin, 'c_rehman', main: true, ageDays: 110),
      staff('u_clifton_main', 'Zara Hussain', 'clinic@cliftoncare.pk', StaffRole.clinicAdmin, 'c_clifton', main: true, status: StaffStatus.invited, ageDays: 5),
    ]) {
      _staff[s.uid] = s;
    }

    // ---- Invoices (A-05, A-06) ----
    String month(int back) {
      final m = DateTime(now.year, now.month - back, 1);
      return '${m.year}-${m.month.toString().padLeft(2, '0')}';
    }

    DateTime due(int back) => DateTime(now.year, now.month - back, 1 + _settings.dueDays);
    void inv(String clinicId, int back, InvoiceStatus status, {DateTime? dueDate, PaymentMethod method = PaymentMethod.jazzCash}) {
      final c = _clinics[clinicId]!;
      final d = dueDate ?? due(back);
      _invoices['inv_${clinicId}_${month(back)}'] = Invoice(
        id: 'inv_${clinicId}_${month(back)}',
        clinicId: clinicId,
        month: month(back),
        amount: c.monthlyFee,
        dueDate: d,
        status: status,
        payment: status == InvoiceStatus.paid
            ? Payment(amount: c.monthlyFee, method: method, reference: 'TX${100000 + _rnd.nextInt(899999)}', date: d.subtract(const Duration(days: 2)), recordedBy: 'Sarbuland')
            : null,
      );
    }

    for (var b = 3; b >= 0; b--) {
      inv('c_alshifa', b, InvoiceStatus.paid, method: b.isEven ? PaymentMethod.bank : PaymentMethod.jazzCash);
      inv('c_dha', b, b == 0 ? InvoiceStatus.unpaid : InvoiceStatus.paid, dueDate: b == 0 ? now.add(const Duration(days: 3)) : null, method: PaymentMethod.easypaisa);
    }
    for (var b = 2; b >= 1; b--) {
      inv('c_modeltown', b, InvoiceStatus.paid);
    }
    inv('c_modeltown', 0, InvoiceStatus.overdue, dueDate: now.subtract(const Duration(days: 9)));
    inv('c_rehman', 2, InvoiceStatus.paid);
    inv('c_rehman', 1, InvoiceStatus.overdue, dueDate: now.subtract(const Duration(days: 22)));
    inv('c_rehman', 0, InvoiceStatus.overdue, dueDate: now.subtract(const Duration(days: 4)));
    _clinics['c_modeltown'] = _clinics['c_modeltown']!.copyWith(paidUntil: DateTime(now.year, now.month, 1));
    _clinics['c_rehman'] = _clinics['c_rehman']!.copyWith(paidUntil: DateTime(now.year, now.month - 1, 1));

    // ---- Activity (A-07) ----
    void act(String? clinicId, String name, StaffRole role, String action, String target, Duration ago) =>
        _activity.add(ActivityLog(id: _id('log'), clinicId: clinicId, actorName: name, actorRole: role, action: action, target: target, at: now.subtract(ago)));
    act('c_alshifa', 'Dr. Tariq Mehmood', StaffRole.clinicAdmin, 'invited receptionist', 'Bilal Hussain <evening@alshifa.pk>', const Duration(days: 2));
    act('c_alshifa', 'Dr. Tariq Mehmood', StaffRole.clinicAdmin, 'added leave', 'Dr. Kamran Ahmed · ${Fmt0.day(leaveDay)}', const Duration(hours: 2));
    act('c_clifton', 'Sarbuland', StaffRole.superAdmin, 'created clinic', 'Clifton Care Clinic', const Duration(days: 5));
    act('c_clifton', 'Sarbuland', StaffRole.superAdmin, 'invited clinic admin', 'Zara Hussain <clinic@cliftoncare.pk>', const Duration(days: 5));
    act('c_rehman', 'System', StaffRole.superAdmin, 'suspended clinic', 'Rehman Clinic · unpaid 15+ days', const Duration(days: 7));
    act('c_modeltown', 'System', StaffRole.superAdmin, 'moved to grace', 'Model Town Medical · invoice overdue', const Duration(days: 9));
    act('c_dha', 'Mrs. Rubina Shah', StaffRole.clinicAdmin, 'updated doctor', 'Dr. Hina Shah', const Duration(days: 3, hours: 4));
    act('c_alshifa', 'Sarbuland', StaffRole.superAdmin, 'recorded payment', '${month(0)} · Rs 3000 · Bank', const Duration(days: 6));
    act('c_citycare', 'Nasir Ali', StaffRole.clinicAdmin, 'added doctor', 'Dr. Farah Naz', const Duration(days: 15));
    act('c_dha', 'Mrs. Rubina Shah', StaffRole.clinicAdmin, 'exported visits', 'Last 30 days', const Duration(days: 1, hours: 2));
    _activity.sort((a, b) => b.at.compareTo(a.at));
  }
}

class _UndoNext {
  _UndoNext(this.at, this.day, this.before);
  final DateTime at;
  final QueueDay day;
  final List<QueueToken> before;
}

/// Tiny date labels used in log lines (kept here so the data layer does not
/// depend on UI formatting).
abstract final class Fmt0 {
  static const _m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String day(String key) {
    final d = parseDayKey(key);
    return '${d.day} ${_m[d.month - 1]}';
  }

  static String date(DateTime d) => '${d.day} ${_m[d.month - 1]} ${d.year}';
}
