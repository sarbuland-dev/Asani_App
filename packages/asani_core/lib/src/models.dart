import 'dates.dart';
import 'enums.dart';

// Timestamps are serialised as epoch milliseconds in these maps. The Firestore
// repository (later) converts them to/from Firestore `Timestamp`.
int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;
DateTime? _dt(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
List<String> _strings(Object? v) => (v as List?)?.map((e) => e.toString()).toList() ?? const [];

class AppUser {
  const AppUser({
    required this.uid,
    required this.phone,
    required this.name,
    this.city = 'Lahore',
    this.selfPatientId,
    this.consentAcceptedAt,
    this.consentVersion,
    this.queueAlertsEnabled = true,
  });

  final String uid;
  final String phone; // E.164, e.g. +923001234567
  final String name;
  final String city;
  final String? selfPatientId;
  final DateTime? consentAcceptedAt;
  final String? consentVersion;

  /// Account-wide "Queue alerts" switch, same on every phone (D-18).
  /// The phone's own notification permission is separate (AppSettings).
  final bool queueAlertsEnabled;

  bool get hasProfile => name.trim().isNotEmpty && consentAcceptedAt != null;

  AppUser copyWith({
    String? name,
    String? city,
    String? selfPatientId,
    DateTime? consentAcceptedAt,
    String? consentVersion,
    bool? queueAlertsEnabled,
  }) =>
      AppUser(
        uid: uid,
        phone: phone,
        name: name ?? this.name,
        city: city ?? this.city,
        selfPatientId: selfPatientId ?? this.selfPatientId,
        consentAcceptedAt: consentAcceptedAt ?? this.consentAcceptedAt,
        consentVersion: consentVersion ?? this.consentVersion,
        queueAlertsEnabled: queueAlertsEnabled ?? this.queueAlertsEnabled,
      );

  Map<String, Object?> toMap() => {
        'uid': uid,
        'phone': phone,
        'name': name,
        'role': 'patient',
        'city': city,
        'selfPatientId': selfPatientId,
        'consentAcceptedAt': _ms(consentAcceptedAt),
        'consentVersion': consentVersion,
        'queueAlertsEnabled': queueAlertsEnabled,
      };

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
        uid: m['uid'] as String,
        phone: m['phone'] as String,
        name: (m['name'] as String?) ?? '',
        city: (m['city'] as String?) ?? 'Lahore',
        selfPatientId: m['selfPatientId'] as String?,
        consentAcceptedAt: _dt(m['consentAcceptedAt']),
        consentVersion: m['consentVersion'] as String?,
        queueAlertsEnabled: (m['queueAlertsEnabled'] as bool?) ?? true,
      );
}

class Patient {
  const Patient({
    required this.id,
    required this.ownerUid,
    required this.phone,
    required this.name,
    this.birthYear,
    required this.gender,
    required this.relation,
    this.patientPhone,
    this.status = PatientStatus.active,
    required this.createdAt,
  });

  final String id;
  final String? ownerUid;
  final String phone;
  final String name;
  final int? birthYear; // null until the user enters an age
  final Gender gender;
  final Relation relation;
  final String? patientPhone;
  final PatientStatus status;
  final DateTime createdAt;

  String get nameLower => name.trim().toLowerCase();
  int? age([DateTime? now]) => birthYear == null ? null : (now ?? DateTime.now()).year - birthYear!;
  bool get isSelf => relation == Relation.self;

  Patient copyWith({String? name, int? birthYear, Gender? gender, Relation? relation, String? patientPhone, PatientStatus? status}) =>
      Patient(
        id: id,
        ownerUid: ownerUid,
        phone: phone,
        name: name ?? this.name,
        birthYear: birthYear ?? this.birthYear,
        gender: gender ?? this.gender,
        relation: relation ?? this.relation,
        patientPhone: patientPhone ?? this.patientPhone,
        status: status ?? this.status,
        createdAt: createdAt,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'ownerUid': ownerUid,
        'phone': phone,
        'name': name,
        'nameLower': nameLower,
        'birthYear': birthYear,
        'gender': gender.name,
        'relation': relation.name,
        'patientPhone': patientPhone,
        'status': status.name,
        'createdBy': 'app',
        'createdAt': _ms(createdAt),
      };

  factory Patient.fromMap(Map<String, Object?> m) => Patient(
        id: m['id'] as String,
        ownerUid: m['ownerUid'] as String?,
        phone: m['phone'] as String,
        name: m['name'] as String,
        birthYear: m['birthYear'] as int?,
        gender: Gender.parse(m['gender']),
        relation: Relation.parse(m['relation']),
        patientPhone: m['patientPhone'] as String?,
        status: PatientStatus.parse(m['status']),
        createdAt: _dt(m['createdAt']) ?? DateTime.now(),
      );
}

class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;
}

class Clinic {
  const Clinic({
    required this.id,
    required this.name,
    required this.area,
    required this.city,
    required this.address,
    required this.phone,
    this.location,
    this.status = ClinicStatus.active,
    this.doctorCount = 0,
  });

  final String id;
  final String name;
  final String area;
  final String city;
  final String address;
  final String phone;
  final GeoPoint? location;
  final ClinicStatus status;
  final int doctorCount;

  /// F-02: name or area, case-insensitive, partial match.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return name.toLowerCase().contains(q) || area.toLowerCase().contains(q);
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'nameLower': name.toLowerCase(),
        'area': area,
        'city': city,
        'address': address,
        'phone': phone,
        'location': location == null ? null : {'lat': location!.lat, 'lng': location!.lng},
        'status': status.name,
        'doctorCount': doctorCount,
        'timezone': 'Asia/Karachi',
      };

  factory Clinic.fromMap(Map<String, Object?> m) {
    final loc = m['location'] as Map?;
    return Clinic(
      id: m['id'] as String,
      name: m['name'] as String,
      area: m['area'] as String,
      city: m['city'] as String,
      address: m['address'] as String,
      phone: m['phone'] as String,
      location: loc == null ? null : GeoPoint((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble()),
      status: ClinicStatus.parse(m['status']),
      doctorCount: (m['doctorCount'] as int?) ?? 0,
    );
  }
}

class DaySchedule {
  const DaySchedule(this.start, this.end);
  final String start; // "17:00"
  final String end; // "21:00"

  int get startMinutes => hhmmToMinutes(start);
  int get endMinutes => hhmmToMinutes(end);

  Map<String, Object?> toMap() => {'start': start, 'end': end};
  static DaySchedule? fromMap(Object? m) =>
      m is Map ? DaySchedule(m['start'] as String, m['end'] as String) : null;
}

class Doctor {
  const Doctor({
    required this.id,
    required this.clinicId,
    required this.name,
    required this.speciality,
    this.qualification,
    required this.tokenPrefix,
    this.avgConsultMinutes = 10,
    this.maxTokensPerDay = 40,
    this.bookingWindowDays = 7,
    required this.schedule,
    this.onLeaveDates = const [],
    this.active = true,
    this.sortOrder = 0,
  });

  final String id;
  final String clinicId;
  final String name;
  final String speciality;
  final String? qualification;

  /// Letter shown before token numbers, e.g. "A" → token "A-11" (UI design).
  final String tokenPrefix;
  final int avgConsultMinutes;
  final int maxTokensPerDay;
  final int bookingWindowDays;

  /// Keys mon…sun → schedule, or null when the doctor is off that day.
  final Map<String, DaySchedule?> schedule;
  final List<String> onLeaveDates;
  final bool active;
  final int sortOrder;

  DaySchedule? scheduleOn(DateTime date) => schedule[weekdayKey(date)];
  bool onLeave(DateTime date) => onLeaveDates.contains(dayKey(date));
  String tokenLabel(int number) => '$tokenPrefix-$number';

  Map<String, Object?> toMap() => {
        'id': id,
        'clinicId': clinicId,
        'name': name,
        'speciality': speciality,
        'qualification': qualification,
        'tokenPrefix': tokenPrefix,
        'avgConsultMinutes': avgConsultMinutes,
        'maxTokensPerDay': maxTokensPerDay,
        'bookingWindowDays': bookingWindowDays,
        'schedule': {for (final e in schedule.entries) e.key: e.value?.toMap()},
        'onLeaveDates': onLeaveDates,
        'active': active,
        'sortOrder': sortOrder,
      };

  factory Doctor.fromMap(Map<String, Object?> m) => Doctor(
        id: m['id'] as String,
        clinicId: m['clinicId'] as String,
        name: m['name'] as String,
        speciality: m['speciality'] as String,
        qualification: m['qualification'] as String?,
        tokenPrefix: (m['tokenPrefix'] as String?) ?? 'A',
        avgConsultMinutes: (m['avgConsultMinutes'] as int?) ?? 10,
        maxTokensPerDay: (m['maxTokensPerDay'] as int?) ?? 40,
        bookingWindowDays: (m['bookingWindowDays'] as int?) ?? 7,
        schedule: {
          for (final e in ((m['schedule'] as Map?) ?? {}).entries) e.key as String: DaySchedule.fromMap(e.value),
        },
        onLeaveDates: _strings(m['onLeaveDates']),
        active: (m['active'] as bool?) ?? true,
        sortOrder: (m['sortOrder'] as int?) ?? 0,
      );
}

/// doctors/{doctorId}/days/{yyyy-MM-dd}
class QueueDay {
  const QueueDay({
    required this.clinicId,
    required this.doctorId,
    required this.date,
    this.sessionStatus = SessionStatus.notStarted,
    this.currentToken = 0,
    this.lastTokenNumber = 0,
    this.activeNumbers = const [],
    this.bookedCount = 0,
    this.updatedAt,
  });

  final String clinicId;
  final String doctorId;
  final String date;
  final SessionStatus sessionStatus;
  final int currentToken;
  final int lastTokenNumber;
  final List<int> activeNumbers;
  final int bookedCount;
  final DateTime? updatedAt;

  int get waitingCount => activeNumbers.length;

  factory QueueDay.empty(String clinicId, String doctorId, String date) =>
      QueueDay(clinicId: clinicId, doctorId: doctorId, date: date);

  QueueDay copyWith({
    SessionStatus? sessionStatus,
    int? currentToken,
    int? lastTokenNumber,
    List<int>? activeNumbers,
    int? bookedCount,
    DateTime? updatedAt,
  }) =>
      QueueDay(
        clinicId: clinicId,
        doctorId: doctorId,
        date: date,
        sessionStatus: sessionStatus ?? this.sessionStatus,
        currentToken: currentToken ?? this.currentToken,
        lastTokenNumber: lastTokenNumber ?? this.lastTokenNumber,
        activeNumbers: activeNumbers ?? this.activeNumbers,
        bookedCount: bookedCount ?? this.bookedCount,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toMap() => {
        'clinicId': clinicId,
        'doctorId': doctorId,
        'date': date,
        'sessionStatus': sessionStatus.name,
        'currentToken': currentToken,
        'lastTokenNumber': lastTokenNumber,
        'activeNumbers': activeNumbers,
        'waitingCount': waitingCount,
        'bookedCount': bookedCount,
        'updatedAt': _ms(updatedAt),
      };

  factory QueueDay.fromMap(Map<String, Object?> m) => QueueDay(
        clinicId: m['clinicId'] as String,
        doctorId: m['doctorId'] as String,
        date: m['date'] as String,
        sessionStatus: SessionStatus.parse(m['sessionStatus']),
        currentToken: (m['currentToken'] as int?) ?? 0,
        lastTokenNumber: (m['lastTokenNumber'] as int?) ?? 0,
        activeNumbers: ((m['activeNumbers'] as List?) ?? []).cast<int>(),
        bookedCount: (m['bookedCount'] as int?) ?? 0,
        updatedAt: _dt(m['updatedAt']),
      );
}

class PatientSnapshot {
  const PatientSnapshot({required this.name, this.birthYear, required this.gender, required this.relation, required this.phone});

  final String name;
  final int? birthYear;
  final Gender gender;
  final Relation relation;
  final String phone;

  factory PatientSnapshot.of(Patient p) =>
      PatientSnapshot(name: p.name, birthYear: p.birthYear, gender: p.gender, relation: p.relation, phone: p.phone);

  int? age([DateTime? now]) => birthYear == null ? null : (now ?? DateTime.now()).year - birthYear!;

  Map<String, Object?> toMap() =>
      {'name': name, 'birthYear': birthYear, 'gender': gender.name, 'relation': relation.name, 'phone': phone};

  factory PatientSnapshot.fromMap(Map m) => PatientSnapshot(
        name: m['name'] as String,
        birthYear: m['birthYear'] as int?,
        gender: Gender.parse(m['gender']),
        relation: Relation.parse(m['relation']),
        phone: m['phone'] as String,
      );
}

class Token {
  const Token({
    required this.id,
    required this.clinicId,
    required this.doctorId,
    required this.date,
    required this.number,
    required this.tokenPrefix,
    required this.patientId,
    required this.patientSnapshot,
    required this.bookedByUserId,
    this.status = TokenStatus.booked,
    this.notified = const {},
    required this.createdAt,
    this.calledAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
  });

  final String id;
  final String clinicId;
  final String doctorId;
  final String date;
  final int number;
  final String tokenPrefix;
  final String patientId;
  final PatientSnapshot patientSnapshot;
  final String? bookedByUserId;
  final TokenStatus status;
  final Set<QueueStep> notified;
  final DateTime createdAt;
  final DateTime? calledAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  /// Reason the clinic picked when it cancelled (C-04, D-23).
  final String? cancelReason;

  String get label => '$tokenPrefix-$number';

  bool get cancelledByClinic => status == TokenStatus.cancelled && cancelledBy == 'clinic';

  /// Minutes from booking to being called, when known.
  int? get waitedMinutes => calledAt?.difference(createdAt).inMinutes;

  Token copyWith({
    TokenStatus? status,
    Set<QueueStep>? notified,
    DateTime? calledAt,
    DateTime? completedAt,
    DateTime? cancelledAt,
    String? cancelledBy,
  }) =>
      Token(
        id: id,
        clinicId: clinicId,
        doctorId: doctorId,
        date: date,
        number: number,
        tokenPrefix: tokenPrefix,
        patientId: patientId,
        patientSnapshot: patientSnapshot,
        bookedByUserId: bookedByUserId,
        status: status ?? this.status,
        notified: notified ?? this.notified,
        createdAt: createdAt,
        calledAt: calledAt ?? this.calledAt,
        completedAt: completedAt ?? this.completedAt,
        cancelledAt: cancelledAt ?? this.cancelledAt,
        cancelledBy: cancelledBy ?? this.cancelledBy,
        cancelReason: cancelReason,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'clinicId': clinicId,
        'doctorId': doctorId,
        'date': date,
        'number': number,
        'tokenPrefix': tokenPrefix,
        'patientId': patientId,
        'patientSnapshot': patientSnapshot.toMap(),
        'bookedByUserId': bookedByUserId,
        'source': 'app',
        'status': status.name,
        'notified': notified.map((s) => s.name).toList(),
        'createdAt': _ms(createdAt),
        'calledAt': _ms(calledAt),
        'completedAt': _ms(completedAt),
        'cancelledAt': _ms(cancelledAt),
        'cancelledBy': cancelledBy,
        'cancelReason': cancelReason,
      };

  factory Token.fromMap(Map<String, Object?> m) => Token(
        id: m['id'] as String,
        clinicId: m['clinicId'] as String,
        doctorId: m['doctorId'] as String,
        date: m['date'] as String,
        number: m['number'] as int,
        tokenPrefix: (m['tokenPrefix'] as String?) ?? 'A',
        patientId: m['patientId'] as String,
        patientSnapshot: PatientSnapshot.fromMap(m['patientSnapshot'] as Map),
        bookedByUserId: m['bookedByUserId'] as String?,
        status: TokenStatus.parse(m['status']),
        notified: _strings(m['notified']).map(QueueStep.parse).whereType<QueueStep>().toSet(),
        createdAt: _dt(m['createdAt']) ?? DateTime.now(),
        calledAt: _dt(m['calledAt']),
        completedAt: _dt(m['completedAt']),
        cancelledAt: _dt(m['cancelledAt']),
        cancelledBy: m['cancelledBy'] as String?,
        cancelReason: m['cancelReason'] as String?,
      );
}

class FollowUp {
  const FollowUp({
    required this.id,
    required this.ownerUid,
    required this.patientId,
    required this.clinicId,
    required this.doctorId,
    required this.dueDate,
    this.status = FollowUpStatus.pending,
    this.note,
  });

  final String id;
  final String ownerUid;
  final String patientId;
  final String clinicId;
  final String doctorId;
  final String dueDate; // yyyy-MM-dd
  final FollowUpStatus status;
  final String? note;

  FollowUp copyWith({FollowUpStatus? status}) => FollowUp(
        id: id,
        ownerUid: ownerUid,
        patientId: patientId,
        clinicId: clinicId,
        doctorId: doctorId,
        dueDate: dueDate,
        status: status ?? this.status,
        note: note,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'ownerUid': ownerUid,
        'patientId': patientId,
        'clinicId': clinicId,
        'doctorId': doctorId,
        'dueDate': dueDate,
        'status': status.name,
        'note': note,
      };

  factory FollowUp.fromMap(Map<String, Object?> m) => FollowUp(
        id: m['id'] as String,
        ownerUid: m['ownerUid'] as String,
        patientId: m['patientId'] as String,
        clinicId: m['clinicId'] as String,
        doctorId: m['doctorId'] as String,
        dueDate: m['dueDate'] as String,
        status: FollowUpStatus.parse(m['status']),
        note: m['note'] as String?,
      );
}
