import 'package:asani_core/asani_core.dart';

import 'models.dart';

/// Queue actions on a single token (C-04). All go through the backend (BW-1).
enum TokenAction {
  arrive('Arrived'),
  callNow('Called'),
  skip('Skipped'),
  hold('On hold'),
  backToQueue('Back to queue'),
  cancel('Cancelled'),
  noShow('No-show'),
  reprint('Reprinted');

  const TokenAction(this.logLabel);
  final String logLabel;
}

enum SessionAction { start, pause, end }

/// Result of a check-in lookup by token code (C-05).
class CodeLookup {
  const CodeLookup({this.token, this.otherDate, this.ambiguous = const []});

  /// Today's token with this code at this clinic.
  final QueueToken? token;

  /// A token with this code exists, but for another date.
  final QueueToken? otherDate;

  /// Single-letter-less code ("11") matched more than one doctor.
  final List<QueueToken> ambiguous;
}

/// New patient details for a walk-in (C-06).
class NewPatient {
  const NewPatient({required this.phone, required this.name, this.age, required this.gender, this.relation = Relation.other});
  final String phone; // E.164
  final String name;
  final int? age;
  final Gender gender;
  final Relation relation;
}

/// Everything the "New clinic" wizard collects (A-04).
class NewClinicDraft {
  NewClinicDraft();
  String name = '';
  String area = '';
  String city = 'Lahore';
  String address = '';
  String phone = '';
  PrintFormat printFormat = PrintFormat.thermal80;
  final List<Doctor> doctors = [];
  String ownerName = '';
  String ownerPhone = '';
  String email = '';
  int pilotDays = 30;
  Plan planAfterPilot = Plan.basic;
  int monthlyFee = 3000;
  int billingDay = 1;
}

/// The clinic web's data layer. UI → provider → repository → backend.
///
/// [DemoClinicRepository] implements it in memory today. A Firebase version
/// will call the callable functions listed in PRD-CLINIC-WEB §11
/// (`queueAction`, `staffCreateWalkIn`, `inviteStaff`, `recordPayment` …).
abstract interface class ClinicRepository {
  /// Fires after every change, so providers can rebuild (live queue).
  Stream<void> get changes;

  // ---- Auth (§5) ----
  StaffAccount? get currentUser;
  Future<StaffAccount> signIn(String email, String password);
  Future<void> signOut();
  Future<void> sendPasswordReset(String email);

  // ---- Clinic reads ----
  ClinicAccount? clinic(String clinicId);
  List<Doctor> doctors(String clinicId, {bool includeInactive = false});
  QueueDay queueDay(String clinicId, String doctorId, String date);
  List<QueueToken> tokens(String clinicId, String date);
  QueueToken? tokenById(String id);
  CodeLookup findByCode(String clinicId, String code);
  List<ClinicPatient> searchPatients(String clinicId, String query);
  ClinicPatient? clinicPatient(String clinicId, String patientId);
  List<FollowUp> followUps(String clinicId);
  Patient? patient(String id);
  List<StaffAccount> staff(String clinicId);
  List<Invoice> invoices({String? clinicId});
  List<ActivityLog> activity({String? clinicId});
  AdminSettings get settings;
  List<ClinicAccount> clinics();
  bool canUndoNext(String doctorId);

  // ---- Queue writes (BW-1) ----
  Future<void> session(String clinicId, String doctorId, SessionAction action);
  Future<QueueToken?> next(String clinicId, String doctorId);
  Future<void> undoNext(String doctorId);
  Future<void> tokenAction(String tokenId, TokenAction action, {String? reason});
  Future<QueueToken> createWalkIn(String clinicId, String doctorId, {String? patientId, NewPatient? newPatient});
  Future<void> setFollowUp(String tokenId, String dueDate, {String? note});
  Future<void> updatePatient(String clinicId, String patientId, {required String name, int? birthYear, required Gender gender});

  // ---- Clinic admin ----
  Future<Doctor> saveDoctor(String clinicId, Doctor doctor, {bool isNew = false});
  Future<int> addLeave(String doctorId, String date);
  Future<void> removeLeave(String doctorId, String date);
  Future<int> cancelTokensOn(String doctorId, String date, String reason);
  Future<void> setDoctorActive(String doctorId, bool active);
  Future<void> inviteStaff(String clinicId, {required String name, required String email, required StaffRole role, String? doctorId});
  Future<void> resendInvite(String uid);
  Future<void> updateStaff(String uid, {StaffRole? role, String? doctorId, StaffStatus? status});
  Future<void> updateClinicSettings(String clinicId, {String? address, String? area, String? phone, PrintFormat? printFormat, String? name});
  Future<void> logExport(String clinicId, String range);

  // ---- Super admin ----
  Future<ClinicAccount> createClinic(NewClinicDraft draft);
  Future<void> setClinicStatus(String clinicId, ClinicStatus status, {String? reason});
  Future<void> changePlan(String clinicId, {Plan? plan, int? monthlyFee});
  Future<void> extendPilot(String clinicId, int days);
  Future<void> recordPayment(String invoiceId, Payment payment);
  Future<void> waiveInvoice(String invoiceId, String reason);
  Future<void> giveExtension(String invoiceId, DateTime newDueDate);
  Future<void> saveSettings(AdminSettings settings);
}
