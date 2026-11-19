import 'package:asani_core/asani_core.dart';

/// Demo clinics and doctors. Some schedules are set relative to "now" so the
/// live queue is running whenever the demo is opened.
class DemoSeed {
  DemoSeed(this.now);
  final DateTime now;

  /// The demo account gets a family and visit history.
  static const demoPhone = '+923001234567';

  String _hm(int minutes) => minutesToHhmm(minutes.clamp(0, 23 * 60 + 59));

  /// Today's session around the current time (started ~1 h ago).
  DaySchedule get _runningNow => DaySchedule(_hm((now.hour - 1) * 60), _hm((now.hour + 4) * 60));

  /// Today's session starting about an hour from now.
  DaySchedule? get _laterToday => now.hour >= 22 ? null : DaySchedule(_hm((now.hour + 1) * 60), _hm((now.hour + 4) * 60));

  Map<String, DaySchedule?> _week(DaySchedule? normal, {DaySchedule? today, bool todayOff = false, Set<String> off = const {'sun'}}) {
    final todayKey = weekdayKey(now);
    return {
      for (final k in weekdayKeys)
        k: k == todayKey ? (todayOff ? null : (today ?? (off.contains(k) ? null : normal))) : (off.contains(k) ? null : normal),
    };
  }

  String get today => dayKey(now);
  String inDays(int n) => dayKey(dateOnly(now).add(Duration(days: n)));

  List<Clinic> clinics() => const [
        Clinic(id: 'c_alshifa', name: 'Al-Shifa Clinic', area: 'Johar Town', city: 'Lahore', address: 'Main Boulevard, Johar Town', phone: '042-1234567', location: GeoPoint(31.4697, 74.2728)),
        Clinic(id: 'c_citycare', name: 'City Care Clinic', area: 'Gulberg', city: 'Lahore', address: 'MM Alam Road, Gulberg III', phone: '042-3576543', location: GeoPoint(31.5102, 74.3511)),
        Clinic(id: 'c_modeltown', name: 'Model Town Medical', area: 'Model Town', city: 'Lahore', address: 'Link Road, Model Town', phone: '042-3588812', location: GeoPoint(31.4835, 74.3239)),
        Clinic(id: 'c_dha', name: 'DHA Family Clinic', area: 'DHA Phase 5', city: 'Lahore', address: 'Sector C, DHA Phase 5', phone: '042-3712990', location: GeoPoint(31.4625, 74.4086)),
        Clinic(id: 'c_shifafamily', name: 'Shifa Family Clinic', area: 'Model Town', city: 'Lahore', address: 'Block K, Model Town', phone: '042-3591177'),
        Clinic(id: 'c_rehman', name: 'Rehman Clinic', area: 'Iqbal Town', city: 'Lahore', address: 'Moon Market, Iqbal Town', phone: '042-3781100', status: ClinicStatus.suspended),
        Clinic(id: 'c_clifton', name: 'Clifton Care Clinic', area: 'Clifton', city: 'Karachi', address: 'Block 5, Clifton', phone: '021-35871234', location: GeoPoint(24.8138, 67.0300)),
        Clinic(id: 'c_capital', name: 'Capital Health Clinic', area: 'F-8 Markaz', city: 'Islamabad', address: 'F-8 Markaz', phone: '051-2287654', location: GeoPoint(33.7086, 73.0375)),
      ];

  List<Doctor> doctors() {
    const evening = DaySchedule('17:00', '21:00');
    return [
      Doctor(id: 'd_ayesha', clinicId: 'c_alshifa', name: 'Dr. Ayesha Malik', speciality: 'General Physician', qualification: 'MBBS, FCPS', tokenPrefix: 'A', schedule: _week(evening, today: _runningNow), sortOrder: 1, doctorGroupId: 'g_ayesha'),
      Doctor(id: 'd_kamran', clinicId: 'c_alshifa', name: 'Dr. Kamran Ahmed', speciality: 'Child Specialist', qualification: 'MBBS, DCH', tokenPrefix: 'B', schedule: _week(const DaySchedule('10:00', '14:00')), onLeaveDates: [today], sortOrder: 2),
      Doctor(id: 'd_sana', clinicId: 'c_alshifa', name: 'Dr. Sana Riaz', speciality: 'Gynecologist', qualification: 'MBBS, FCPS', tokenPrefix: 'C', avgConsultMinutes: 15, maxTokensPerDay: 30, schedule: _week(const DaySchedule('18:00', '21:00'), today: _laterToday, todayOff: _laterToday == null), sortOrder: 3),
      Doctor(id: 'd_imran', clinicId: 'c_citycare', name: 'Dr. Imran Qureshi', speciality: 'General Physician', tokenPrefix: 'A', schedule: _week(const DaySchedule('16:00', '22:00'), today: _runningNow), sortOrder: 1),
      Doctor(id: 'd_farah', clinicId: 'c_citycare', name: 'Dr. Farah Naz', speciality: 'Dermatologist', tokenPrefix: 'B', avgConsultMinutes: 12, schedule: _week(const DaySchedule('11:00', '15:00')), sortOrder: 2),
      Doctor(id: 'd_usman', clinicId: 'c_modeltown', name: 'Dr. Usman Tariq', speciality: 'ENT Specialist', tokenPrefix: 'A', schedule: _week(const DaySchedule('16:00', '20:00'), off: {'sat', 'sun'}), sortOrder: 1),
      Doctor(id: 'd_hina', clinicId: 'c_dha', name: 'Dr. Hina Shah', speciality: 'Pediatrician', tokenPrefix: 'A', schedule: _week(const DaySchedule('09:00', '13:00'), off: {}), sortOrder: 1),
      Doctor(id: 'd_bilal', clinicId: 'c_dha', name: 'Dr. Bilal Ahmed', speciality: 'General Physician', tokenPrefix: 'B', schedule: _week(evening, today: _runningNow), sortOrder: 2),
      // D-32 demo: Dr. Ayesha also sits at DHA (linked by the Super Admin), and a heart doctor for the Doctors tab.
      Doctor(id: 'd_ayesha_dha', clinicId: 'c_dha', name: 'Dr. Ayesha Malik', speciality: 'generalPhysician', qualification: 'MBBS, FCPS', tokenPrefix: 'C', schedule: _week(const DaySchedule('10:00', '13:00')), sortOrder: 3, doctorGroupId: 'g_ayesha'),
      Doctor(id: 'd_asif', clinicId: 'c_citycare', name: 'Dr. Asif Khan', speciality: 'heart', qualification: 'MBBS, FCPS (Cardiology)', tokenPrefix: 'C', avgConsultMinutes: 15, schedule: _week(evening, today: _runningNow), sortOrder: 3),
      Doctor(id: 'd_nadia', clinicId: 'c_shifafamily', name: 'Dr. Nadia Karim', speciality: 'General Physician', tokenPrefix: 'A', schedule: _week(evening, todayOff: true), sortOrder: 1),
      Doctor(id: 'd_rehman', clinicId: 'c_rehman', name: 'Dr. Abdul Rehman', speciality: 'General Physician', tokenPrefix: 'A', schedule: _week(evening), sortOrder: 1),
      Doctor(id: 'd_zara', clinicId: 'c_clifton', name: 'Dr. Zara Hussain', speciality: 'General Physician', tokenPrefix: 'A', schedule: _week(evening, today: _runningNow), sortOrder: 1),
      Doctor(id: 'd_omar', clinicId: 'c_capital', name: 'Dr. Omar Farooq', speciality: 'Cardiologist', tokenPrefix: 'A', avgConsultMinutes: 15, schedule: _week(const DaySchedule('16:00', '21:00')), sortOrder: 1),
    ];
  }

  /// Today's queues, plus one full day for Dr. Ayesha ("Full" date chip).
  List<QueueDay> days() {
    QueueDay running(String clinicId, String doctorId, int current, int last) => QueueDay(
          clinicId: clinicId,
          doctorId: doctorId,
          date: today,
          sessionStatus: SessionStatus.running,
          currentToken: current,
          lastTokenNumber: last,
          bookedCount: last,
          activeNumbers: [for (var n = current + 1; n <= last; n++) n],
          updatedAt: now,
        );
    return [
      running('c_alshifa', 'd_ayesha', 7, 18),
      running('c_citycare', 'd_imran', 3, 8),
      running('c_dha', 'd_bilal', 2, 5),
      running('c_clifton', 'd_zara', 5, 9),
      QueueDay(clinicId: 'c_alshifa', doctorId: 'd_sana', date: today, lastTokenNumber: 8, bookedCount: 8, activeNumbers: [for (var n = 1; n <= 8; n++) n]),
      QueueDay(clinicId: 'c_alshifa', doctorId: 'd_ayesha', date: inDays(4), lastTokenNumber: 40, bookedCount: 40, activeNumbers: [for (var n = 1; n <= 40; n++) n]),
    ];
  }

  /// Family and history for the demo account.
  ({List<Patient> patients, List<Token> tokens, List<FollowUp> followUps}) demoAccount(String uid, Patient self) {
    final createdAt = now.subtract(const Duration(days: 90));
    Patient p(String id, String name, int age, Gender g, Relation r) => Patient(
        id: id, ownerUid: uid, phone: demoPhone, name: name, birthYear: now.year - age, gender: g, relation: r, createdAt: createdAt);
    final mother = p('p_shazia', 'Shazia Begum', 55, Gender.female, Relation.mother);
    final son = p('p_ahmed', 'Ahmed', 5, Gender.male, Relation.son);

    Token past(String id, Patient pt, String clinicId, String doctorId, String prefix, int n, int daysAgo, int waited,
        {TokenStatus status = TokenStatus.completed}) {
      final booked = now.subtract(Duration(days: daysAgo, hours: 2));
      return Token(
        id: id,
        clinicId: clinicId,
        doctorId: doctorId,
        date: dayKey(booked),
        number: n,
        tokenPrefix: prefix,
        patientId: pt.id,
        patientSnapshot: PatientSnapshot.of(pt),
        bookedByUserId: uid,
        status: status,
        createdAt: booked,
        calledAt: status == TokenStatus.completed ? booked.add(Duration(minutes: waited)) : null,
        completedAt: status == TokenStatus.completed ? booked.add(Duration(minutes: waited + 10)) : null,
        cancelledAt: status == TokenStatus.cancelled ? booked.add(const Duration(minutes: 40)) : null,
        cancelledBy: status == TokenStatus.cancelled ? 'patient' : null,
      );
    }

    return (
      patients: [mother, son],
      tokens: [
        past('t_h1', mother, 'c_alshifa', 'd_ayesha', 'A', 8, 5, 22),
        past('t_h2', self, 'c_citycare', 'd_imran', 'A', 15, 10, 0, status: TokenStatus.cancelled),
        past('t_h3', mother, 'c_citycare', 'd_imran', 'A', 12, 24, 35),
        past('t_h4', son, 'c_dha', 'd_hina', 'A', 6, 30, 18),
        past('t_h5', mother, 'c_alshifa', 'd_ayesha', 'A', 5, 48, 15),
        past('t_h6', self, 'c_alshifa', 'd_ayesha', 'A', 3, 60, 12),
      ],
      followUps: [
        FollowUp(id: 'f_1', ownerUid: uid, patientId: mother.id, clinicId: 'c_alshifa', doctorId: 'd_ayesha', dueDate: inDays(2)),
      ],
    );
  }
}
