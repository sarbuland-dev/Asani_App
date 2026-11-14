import 'package:asani_core/asani_core.dart';

/// Repository contracts. Screens and providers depend only on these, so the
/// demo backend can be swapped for Firebase without touching the UI
/// (ARCHITECTURE.md §4: UI → provider → repository → backend).

enum AuthStatus { signedOut, codeSent, needsProfile, signedIn }

class AuthState {
  const AuthState(this.status, {this.user, this.pendingPhone});
  final AuthStatus status;
  final AppUser? user;
  final String? pendingPhone;
}

abstract interface class AuthRepository {
  Stream<AuthState> watchAuth();
  AuthState get current;
  Future<void> sendCode(String e164Phone);
  Future<void> verifyCode(String code);
  /// First login: creates the account and the "Self" patient profile.
  Future<void> completeProfile({required String name, required int age, required Gender gender});
  Future<void> updateName(String name);
  Future<void> setCity(String city);
  /// Account-wide queue alerts on/off (D-18), synced to every phone.
  Future<void> setQueueAlerts(bool enabled);
  void cancelLogin();
  Future<void> signOut();
  Future<void> deleteAccount();
}

abstract interface class ClinicRepository {
  /// Cities that have at least one visible clinic, A-Z.
  Stream<List<String>> watchCities();
  Stream<List<Clinic>> watchClinics(String city);
  Stream<Clinic?> watchClinic(String clinicId);
  Stream<List<Doctor>> watchDoctors(String clinicId);
  Stream<Doctor?> watchDoctor(String doctorId);
  Stream<List<Clinic>> watchRecentClinics();
  Stream<Map<String, List<Doctor>>> watchDoctorsByClinic();
}

abstract interface class QueueRepository {
  /// doctors/{doctorId}/days/{date}
  Stream<QueueDay> watchDay(String doctorId, String date);
}

class QueueAlert {
  const QueueAlert({required this.tokenId, required this.step, required this.title, required this.body});
  final String tokenId;
  final QueueStep step;
  final String title;
  final String body;
}

abstract interface class TokenRepository {
  Stream<List<Token>> watchMyTokens();
  Stream<Token?> watchToken(String tokenId);
  Future<Token> bookToken({required String clinicId, required String doctorId, required String patientId, required String date});
  Future<void> cancelToken(String tokenId);

  /// Queue notifications (PRD F-06). Real push (FCM) replaces this later.
  Stream<QueueAlert> get alerts;
}

abstract interface class PatientRepository {
  Stream<List<Patient>> watchMyPatients();
  Future<Patient> addPatient({required String name, int? age, required Gender gender, required Relation relation, String? patientPhone});
  Future<void> updatePatient(Patient patient, {int? age});
  Future<void> removePatient(String patientId);
}

abstract interface class FollowUpRepository {
  Stream<List<FollowUp>> watchMyFollowUps();
}

abstract interface class SettingsRepository {
  Stream<AppSettings> watchSettings();
  AppSettings get settings;
  Future<void> update(AppSettings settings);
}

class AppSettings {
  const AppSettings({this.introSeen = false, this.primerShown = false, this.notificationsAllowed = false, this.autoAdvanceQueue = true});
  /// Intro pages (S-00) were shown once (D-16). Unused since the intro was removed (D-28).
  final bool introSeen;
  final bool primerShown;
  final bool notificationsAllowed;

  /// Demo only: the simulated receptionist moves queues forward on a timer.
  final bool autoAdvanceQueue;

  AppSettings copyWith({bool? introSeen, bool? primerShown, bool? notificationsAllowed, bool? autoAdvanceQueue}) => AppSettings(
        introSeen: introSeen ?? this.introSeen,
        primerShown: primerShown ?? this.primerShown,
        notificationsAllowed: notificationsAllowed ?? this.notificationsAllowed,
        autoAdvanceQueue: autoAdvanceQueue ?? this.autoAdvanceQueue,
      );

  Map<String, Object?> toMap() =>
      {'introSeen': introSeen, 'primerShown': primerShown, 'notificationsAllowed': notificationsAllowed, 'autoAdvanceQueue': autoAdvanceQueue};

  factory AppSettings.fromMap(Map m) => AppSettings(
        introSeen: (m['introSeen'] as bool?) ?? false,
        primerShown: (m['primerShown'] as bool?) ?? false,
        notificationsAllowed: (m['notificationsAllowed'] as bool?) ?? false,
        autoAdvanceQueue: (m['autoAdvanceQueue'] as bool?) ?? true,
      );
}

/// Developer controls that stand in for the clinic desktop app (queue-sim).
abstract interface class QueueSimulator {
  Future<void> advanceQueue(String doctorId);
  List<Doctor> doctorsWithMyActiveTokens();
}
