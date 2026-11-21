/// Enum values are stored as camelCase strings (DATABASE.md).
T _byName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

enum TokenStatus {
  booked,
  arrived,
  called,
  completed,
  cancelled,
  noShow,
  skipped,
  onHold;

  static TokenStatus parse(Object? v) => _byName(values, v, booked);

  /// Active = booked, arrived, called, onHold (PRD BR-5).
  bool get isActive => this == booked || this == arrived || this == called || this == onHold;

  /// D-35: Skipped is a paused state for the patient: the clinic can still
  /// recall it, so the app keeps it under Active with a "go to reception" card.
  bool get isOpenForPatient => isActive || this == skipped;

  /// Counts towards "patients ahead" (PRD N-1).
  bool get isWaiting => this == booked || this == arrived || this == onHold;

  /// Patient may cancel only while booked or arrived (PRD F-05).
  bool get canCancel => this == booked || this == arrived;

  String get label => switch (this) {
        booked => 'Booked',
        arrived => 'Arrived',
        called => 'Called',
        completed => 'Completed',
        cancelled => 'Cancelled',
        noShow => 'No-show',
        skipped => 'Skipped',
        onHold => 'On hold',
      };
}

enum SessionStatus {
  notStarted,
  running,
  paused,
  ended;

  static SessionStatus parse(Object? v) => _byName(values, v, notStarted);
}

enum ClinicStatus {
  pilot,
  active,
  grace,
  suspended,
  cancelled;

  static ClinicStatus parse(Object? v) => _byName(values, v, active);

  /// BR-1: online booking allowed.
  bool get acceptsBookings => this == pilot || this == active || this == grace;
}

enum Gender {
  male,
  female,
  other;

  static Gender parse(Object? v) => _byName(values, v, other);

  String get label => switch (this) { male => 'Male', female => 'Female', other => 'Other' };
  String get short => switch (this) { male => 'M', female => 'F', other => 'O' };
}

enum Relation {
  self,
  mother,
  father,
  spouse,
  son,
  daughter,
  brother,
  sister,
  other;

  static Relation parse(Object? v) => _byName(values, v, other);

  String get label => switch (this) {
        self => 'Self',
        mother => 'Mother',
        father => 'Father',
        spouse => 'Spouse',
        son => 'Son',
        daughter => 'Daughter',
        brother => 'Brother',
        sister => 'Sister',
        other => 'Other',
      };
}

enum PatientStatus {
  active,
  deleted,
  merged;

  static PatientStatus parse(Object? v) => _byName(values, v, active);
}

enum FollowUpStatus {
  pending,
  booked,
  done,
  missed;

  static FollowUpStatus parse(Object? v) => _byName(values, v, pending);

  String get label => switch (this) {
        pending => 'Pending',
        booked => 'Booked',
        done => 'Done',
        missed => 'Missed',
      };
}

/// Queue notification steps (PRD F-06). Value = patients ahead; 0 = called.
enum QueueStep {
  threeAhead(3),
  twoAhead(2),
  oneAhead(1),
  called(0);

  const QueueStep(this.ahead);
  final int ahead;

  static QueueStep? parse(Object? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return null;
  }
}
