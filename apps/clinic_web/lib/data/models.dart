import 'package:asani_core/asani_core.dart';

/// Clinic-web roles (PRD-CLINIC-WEB §4, D-18). Stored as Firebase Auth custom
/// claims (`role: "clinic"` + `clinicId`, or `role: "superAdmin"`), set only
/// by Cloud Functions. There are no receptionist or doctor accounts: the whole
/// clinic shares one clinic login, and doctors are records, not users.
enum UserRole {
  superAdmin,
  clinic;

  String get label => switch (this) { superAdmin => 'Super Admin', clinic => 'Clinic login' };
}

enum LoginStatus {
  invited,
  active,
  disabled;

  String get label => switch (this) { invited => 'Invited', active => 'Active', disabled => 'Disabled' };
}

/// A login: the Super Admin, or a clinic's single login (clinicAccounts/{uid}).
class UserAccount {
  const UserAccount({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.clinicId,
    this.status = LoginStatus.active,
    required this.createdAt,
    this.invitedAt,
    this.lastLoginAt,
    this.passwordChangedAt,
  });

  final String uid;

  /// Super Admin: person's name. Clinic login: the manager / senior doctor.
  final String name;
  final String email;
  final UserRole role;
  final String? clinicId;
  final LoginStatus status;
  final DateTime createdAt;
  final DateTime? invitedAt;
  final DateTime? lastLoginAt;
  final DateTime? passwordChangedAt;

  bool get isClinic => role == UserRole.clinic;

  UserAccount copyWith({String? name, LoginStatus? status, DateTime? invitedAt, DateTime? lastLoginAt, DateTime? passwordChangedAt}) => UserAccount(
        uid: uid,
        name: name ?? this.name,
        email: email,
        role: role,
        clinicId: clinicId,
        status: status ?? this.status,
        createdAt: createdAt,
        invitedAt: invitedAt ?? this.invitedAt,
        lastLoginAt: lastLoginAt ?? this.lastLoginAt,
        passwordChangedAt: passwordChangedAt ?? this.passwordChangedAt,
      );
}

/// What a role may do (PRD-CLINIC-WEB §4.2 permission matrix).
extension Perms on UserRole {
  /// Queue work: check-in, Next, token actions, sessions, walk-ins, patients, follow-ups.
  bool get canRunQueue => this == UserRole.clinic;

  /// D-19: the clinic adds, edits, deactivates its doctors and sets leave.
  /// The Super Admin only views them (and gets a new-doctor alert).
  bool get canManageDoctors => this == UserRole.clinic;
}

enum TokenSource {
  app,
  walkIn;

  String get label => switch (this) { app => 'App', walkIn => 'Walk-in' };
}

/// One line in a token's history (who did what and when).
class TokenEvent {
  const TokenEvent(this.action, this.by, this.at, {this.note});
  final String action;
  final String by; // "Al-Shifa Clinic (clinic login)"
  final DateTime at;
  final String? note;
}

/// A token as the clinic sees it: the shared [Token] plus clinic-only fields.
class QueueToken {
  const QueueToken({
    required this.token,
    required this.source,
    this.arrivedAt,
    this.history = const [],
    this.cancelReason,
  });

  final Token token;
  final TokenSource source;
  final DateTime? arrivedAt;
  final List<TokenEvent> history;
  final String? cancelReason;

  String get id => token.id;
  String get label => token.label;
  TokenStatus get status => token.status;
  int get number => token.number;

  /// Wait at the clinic: arrival (or booking) until called.
  int? get waitMinutes {
    final called = token.calledAt;
    if (called == null) return null;
    final from = arrivedAt ?? token.createdAt;
    final m = called.difference(from).inMinutes;
    return m < 0 ? 0 : m;
  }

  QueueToken copyWith({Token? token, DateTime? arrivedAt, List<TokenEvent>? history, String? cancelReason}) => QueueToken(
        token: token ?? this.token,
        source: source,
        arrivedAt: arrivedAt ?? this.arrivedAt,
        history: history ?? this.history,
        cancelReason: cancelReason ?? this.cancelReason,
      );
}

enum PrintFormat {
  thermal80,
  a5,
  none;

  String get label => switch (this) { thermal80 => 'Thermal 80 mm', a5 => 'A5 form', none => 'None (no printing)' };
}

enum Plan {
  pilot,
  basic,
  premium;

  String get label => switch (this) { pilot => 'Pilot', basic => 'Basic', premium => 'Premium' };
}

/// Clinic + its private billing/owner data (clinics/{id}/private/billing).
class ClinicAccount {
  const ClinicAccount({
    required this.clinic,
    required this.email,
    required this.ownerName,
    required this.ownerPhone,
    this.plan = Plan.pilot,
    this.planAfterPilot = Plan.basic,
    this.monthlyFee = 3000,
    this.billingDay = 1,
    this.paidUntil,
    this.pilotEndsAt,
    this.printFormat = PrintFormat.thermal80,
    required this.createdAt,
    this.nextDoctorLetter = 0,
  });

  final Clinic clinic;
  final String email;
  final String ownerName;
  final String ownerPhone;
  final Plan plan;
  final Plan planAfterPilot;
  final int monthlyFee;
  final int billingDay;
  final DateTime? paidUntil;
  final DateTime? pilotEndsAt;
  final PrintFormat printFormat;
  final DateTime createdAt;

  /// Letters are never reused (BW-7): index of the next letter to hand out.
  final int nextDoctorLetter;

  String get id => clinic.id;
  ClinicStatus get status => clinic.status;

  ClinicAccount copyWith({
    Clinic? clinic,
    String? ownerName,
    String? ownerPhone,
    Plan? plan,
    Plan? planAfterPilot,
    int? monthlyFee,
    int? billingDay,
    DateTime? paidUntil,
    DateTime? pilotEndsAt,
    PrintFormat? printFormat,
    int? nextDoctorLetter,
  }) =>
      ClinicAccount(
        clinic: clinic ?? this.clinic,
        email: email,
        ownerName: ownerName ?? this.ownerName,
        ownerPhone: ownerPhone ?? this.ownerPhone,
        plan: plan ?? this.plan,
        planAfterPilot: planAfterPilot ?? this.planAfterPilot,
        monthlyFee: monthlyFee ?? this.monthlyFee,
        billingDay: billingDay ?? this.billingDay,
        paidUntil: paidUntil ?? this.paidUntil,
        pilotEndsAt: pilotEndsAt ?? this.pilotEndsAt,
        printFormat: printFormat ?? this.printFormat,
        createdAt: createdAt,
        nextDoctorLetter: nextDoctorLetter ?? this.nextDoctorLetter,
      );
}

/// Copy of a [Clinic] with some fields changed (core has no copyWith).
Clinic clinicWith(Clinic c, {String? name, String? area, String? city, String? address, String? phone, ClinicStatus? status, int? doctorCount}) =>
    Clinic(
      id: c.id,
      name: name ?? c.name,
      area: area ?? c.area,
      city: city ?? c.city,
      address: address ?? c.address,
      phone: phone ?? c.phone,
      location: c.location,
      status: status ?? c.status,
      doctorCount: doctorCount ?? c.doctorCount,
    );

enum InvoiceStatus {
  unpaid,
  overdue,
  paid,
  waived;

  String get label => switch (this) { unpaid => 'Unpaid', overdue => 'Overdue', paid => 'Paid', waived => 'Waived' };
}

enum PaymentMethod {
  bank,
  jazzCash,
  easypaisa,
  cash;

  String get label => switch (this) { bank => 'Bank', jazzCash => 'JazzCash', easypaisa => 'Easypaisa', cash => 'Cash' };
}

class Payment {
  const Payment({required this.amount, required this.method, this.reference, required this.date, required this.recordedBy});
  final int amount;
  final PaymentMethod method;
  final String? reference;
  final DateTime date;
  final String recordedBy;
}

class Invoice {
  const Invoice({
    required this.id,
    required this.clinicId,
    required this.month,
    required this.amount,
    required this.dueDate,
    this.status = InvoiceStatus.unpaid,
    this.payment,
    this.waiveReason,
  });

  final String id;
  final String clinicId;
  final String month; // yyyy-MM
  final int amount;
  final DateTime dueDate;
  final InvoiceStatus status;
  final Payment? payment;
  final String? waiveReason;

  bool get isOpen => status == InvoiceStatus.unpaid || status == InvoiceStatus.overdue;

  Invoice copyWith({InvoiceStatus? status, Payment? payment, String? waiveReason, DateTime? dueDate}) => Invoice(
        id: id,
        clinicId: clinicId,
        month: month,
        amount: amount,
        dueDate: dueDate ?? this.dueDate,
        status: status ?? this.status,
        payment: payment ?? this.payment,
        waiveReason: waiveReason ?? this.waiveReason,
      );
}

/// activityLogs/{id}: written only by the backend (A-07).
class ActivityLog {
  const ActivityLog({
    required this.id,
    required this.clinicId,
    required this.actorName,
    required this.actorRole,
    required this.action,
    required this.target,
    required this.at,
  });

  final String id;
  final String? clinicId;
  final String actorName;
  final UserRole actorRole;
  final String action; // e.g. "added doctor"
  final String target; // e.g. "Dr. Ayesha Malik"
  final DateTime at;
}

/// A patient profile the clinic knows about (visited or booked here).
class ClinicPatient {
  const ClinicPatient({required this.patient, required this.visits, this.followUps = const []});
  final Patient patient;

  /// Tokens of this patient at this clinic only (BW-6), newest first.
  final List<QueueToken> visits;
  final List<FollowUp> followUps;

  int get visitCount => visits.where((v) => v.status == TokenStatus.completed).length;
  QueueToken? get lastVisit => visits.where((v) => v.status == TokenStatus.completed).firstOrNull;
}

/// settings/billing (A-08).
class AdminSettings {
  const AdminSettings({
    this.prices = const {Plan.pilot: 0, Plan.basic: 3000, Plan.premium: 5000},
    this.pilotDays = 30,
    this.billingDay = 1,
    this.dueDays = 7,
    this.graceDays = 7,
    this.suspendDays = 15,
    this.paymentInstructions =
        'Bank: Meezan Bank · Asani Health · IBAN PK00 MEZN 0000 0000 0000 0000\nJazzCash / Easypaisa: 0300 0000000 (Asani)\nPlease send the transaction ID or a screenshot after paying.',
  });

  final Map<Plan, int> prices;
  final int pilotDays;
  final int billingDay;
  final int dueDays;

  /// Days after the due date: reminder email (grace) and suspension (A-06, Q-W05).
  final int graceDays;
  final int suspendDays;
  final String paymentInstructions;

  AdminSettings copyWith({Map<Plan, int>? prices, int? pilotDays, int? billingDay, int? dueDays, int? graceDays, int? suspendDays, String? paymentInstructions}) =>
      AdminSettings(
        prices: prices ?? this.prices,
        pilotDays: pilotDays ?? this.pilotDays,
        billingDay: billingDay ?? this.billingDay,
        dueDays: dueDays ?? this.dueDays,
        graceDays: graceDays ?? this.graceDays,
        suspendDays: suspendDays ?? this.suspendDays,
        paymentInstructions: paymentInstructions ?? this.paymentInstructions,
      );
}

/// Daily numbers for one doctor or the whole clinic (C-10).
class DaySummary {
  const DaySummary({
    this.issued = 0,
    this.app = 0,
    this.walkIn = 0,
    this.completed = 0,
    this.cancelled = 0,
    this.noShow = 0,
    this.avgWait,
    this.busiestHour,
    this.byHour = const {},
  });

  final int issued;
  final int app;
  final int walkIn;
  final int completed;
  final int cancelled;
  final int noShow;
  final double? avgWait;
  final int? busiestHour;
  final Map<int, int> byHour;

  static DaySummary of(Iterable<QueueToken> tokens) {
    final list = tokens.toList();
    final waits = list.map((t) => t.waitMinutes).whereType<int>().toList();
    final byHour = <int, int>{};
    for (final t in list) {
      final h = (t.arrivedAt ?? t.token.createdAt).hour;
      byHour[h] = (byHour[h] ?? 0) + 1;
    }
    int? busiest;
    for (final e in byHour.entries) {
      if (busiest == null || e.value > byHour[busiest]!) busiest = e.key;
    }
    return DaySummary(
      issued: list.length,
      app: list.where((t) => t.source == TokenSource.app).length,
      walkIn: list.where((t) => t.source == TokenSource.walkIn).length,
      completed: list.where((t) => t.status == TokenStatus.completed).length,
      cancelled: list.where((t) => t.status == TokenStatus.cancelled).length,
      noShow: list.where((t) => t.status == TokenStatus.noShow).length,
      avgWait: waits.isEmpty ? null : waits.reduce((a, b) => a + b) / waits.length,
      busiestHour: busiest,
      byHour: byHour,
    );
  }
}

/// D-32: why two doctor records may be the same person.
enum LinkStrength {
  strong,
  weak;

  String get label => switch (this) { strong => 'Strong (same PMDC)', weak => 'Weak (same name + speciality)' };
}

enum LinkStatus { open, linked, notSame, unlinked }

/// doctorLinkSuggestions/{pairId} (DATABASE §8b, D-32). Super Admin only.
class LinkSuggestion {
  const LinkSuggestion({
    required this.pairId,
    required this.doctorIds,
    required this.clinicIds,
    required this.strength,
    required this.status,
    required this.createdAt,
    this.pmdcNumbers = const [null, null],
  });

  final String pairId;

  /// Two doctor IDs, sorted; [clinicIds] and [pmdcNumbers] in the same order.
  final List<String> doctorIds;
  final List<String> clinicIds;
  final LinkStrength strength;
  final LinkStatus status;
  final DateTime createdAt;
  final List<String?> pmdcNumbers;

  static String pairIdOf(String a, String b) => ([a, b]..sort()).join('_');
}
