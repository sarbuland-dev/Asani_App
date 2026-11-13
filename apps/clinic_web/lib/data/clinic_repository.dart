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

/// One family profile on a full phone number, from any clinic (PRD D-22).
/// Only these fields are ever shared with a clinic: no visits, no history.
class PhoneProfile {
  const PhoneProfile({required this.id, required this.name, required this.relation, required this.gender, this.age, this.atThisClinic = false});
  final String id;
  final String name;
  final Relation relation;
  final Gender gender;
  final int? age;
  final bool atThisClinic;
}

/// State of a full-phone lookup (loading → profiles or error).
class PhoneLookup {
  const PhoneLookup.loading() : profiles = const [], loading = true, error = null;
  const PhoneLookup.done(this.profiles) : loading = false, error = null;
  const PhoneLookup.failed(this.error) : profiles = const [], loading = false;
  final List<PhoneProfile> profiles;
  final bool loading;
  final String? error;
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
  String ownerName = '';
  String ownerPhone = '';
  String email = '';
  int pilotDays = 30;
  Plan planAfterPilot = Plan.basic;
  int monthlyFee = 3000;
  int billingDay = 1;
}

/// Who Next called (for the "Now serving A-8, Ali" snackbar).
class CalledInfo {
  const CalledInfo(this.label, this.name);
  final String label;
  final String name;
}

/// D-24: Next reached a token that has not arrived. Nothing changed; the
/// receptionist picks Skip or Call anyway (`next(..., callNotArrived: tokenId)`).
class NotArrived implements Exception {
  const NotArrived(this.tokenId, this.label, this.name);
  final String tokenId;
  final String label;
  final String name;
}

/// The clinic web's data layer. UI → provider → repository → backend.
///
/// Reads are synchronous from a live cache; [changes] fires when it updates.
/// [DemoClinicRepository] keeps everything in memory; [FirebaseClinicRepository]
/// fills the cache from Firestore listeners and writes only through the
/// callable functions (PRD-CLINIC-WEB §11, BW-1). Data that is not in the cache
/// yet (older days, a patient's history) is loaded on first read and appears
/// with the next [changes] event; the `load…` methods wait for it.
abstract interface class ClinicRepository {
  /// Fires after every change, so providers can rebuild (live queue).
  Stream<void> get changes;

  // ---- Auth (§5) ----
  UserAccount? get currentUser;
  Future<UserAccount> signIn(String email, String password);
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
  /// D-22: profiles on a full E.164 number from any clinic (rate limited server-side).
  PhoneLookup lookupPhone(String clinicId, String phone);
  ClinicPatient? clinicPatient(String clinicId, String patientId);
  List<FollowUp> followUps(String clinicId);
  Patient? patient(String id);
  /// The clinic's single login (D-18).
  UserAccount? clinicLogin(String clinicId);
  List<Invoice> invoices({String? clinicId});
  List<ActivityLog> activity({String? clinicId});
  AdminSettings get settings;
  List<ClinicAccount> clinics();

  /// D-19 / A-01: when each doctor was added (doctorId → time), for the
  /// Super Admin's "New doctors" card and the New marker.
  Map<String, DateTime> doctorAddedAt();
  bool canUndoNext(String doctorId);

  /// Tokens this month (app, walk-in): one clinic, or all clinics for null (A-01).
  (int, int) monthTokens({String? clinicId});

  /// True while a patient's clinic history is still loading.
  bool isLoadingPatient(String patientId);

  /// Waits for a patient's history at this clinic (print "4th visit", profile).
  Future<ClinicPatient?> loadClinicPatient(String clinicId, String patientId);

  /// Waits for all tokens of a date range (export, C-14). Dates are yyyy-MM-dd.
  Future<List<QueueToken>> loadTokens(String clinicId, String from, String to);

  // ---- Queue writes (BW-1) ----
  Future<void> session(String clinicId, String doctorId, SessionAction action);
  /// D-24: calls the lowest number; throws [NotArrived] if that token is not Arrived
  /// and [callNotArrived] is not its id.
  Future<CalledInfo?> next(String clinicId, String doctorId, {String? callNotArrived});
  Future<void> undoNext(String doctorId);
  Future<void> tokenAction(String tokenId, TokenAction action, {String? reason});
  /// [phone] is required with a [patientId] from [lookupPhone] that is not yet at this clinic (D-22).
  Future<QueueToken> createWalkIn(String clinicId, String doctorId, {String? patientId, String? phone, NewPatient? newPatient});
  Future<void> setFollowUp(String tokenId, String dueDate, {String? note});
  Future<void> updatePatient(String clinicId, String patientId, {required String name, int? birthYear, required Gender gender});

  // ---- Clinic admin ----
  Future<Doctor> saveDoctor(String clinicId, Doctor doctor, {bool isNew = false});
  Future<int> addLeave(String doctorId, String date);
  Future<void> removeLeave(String doctorId, String date);
  Future<int> cancelTokensOn(String doctorId, String date, String reason);
  Future<void> setDoctorActive(String doctorId, bool active);
  /// Clinic login: new password; signs out every other computer (C-12).
  Future<void> changePassword(String current, String next);
  Future<void> updateClinicSettings(String clinicId, {String? address, String? area, String? phone, PrintFormat? printFormat, String? name});
  Future<void> logExport(String clinicId, String range);

  // ---- Super admin ----
  Future<ClinicAccount> createClinic(NewClinicDraft draft);
  Future<void> resendClinicInvite(String clinicId);
  Future<void> setClinicLoginStatus(String clinicId, LoginStatus status);
  Future<void> setClinicStatus(String clinicId, ClinicStatus status, {String? reason});
  Future<void> changePlan(String clinicId, {Plan? plan, int? monthlyFee});
  Future<void> extendPilot(String clinicId, int days);
  Future<void> recordPayment(String invoiceId, Payment payment);
  Future<void> waiveInvoice(String invoiceId, String reason);
  Future<void> giveExtension(String invoiceId, DateTime newDueDate);
  Future<void> saveSettings(AdminSettings settings);
}
