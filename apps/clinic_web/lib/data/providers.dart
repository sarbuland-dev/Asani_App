import 'dart:async';

import 'package:asani_core/asani_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'clinic_repository.dart';
import 'models.dart';

/// Overridden in main.dart (demo today, Firebase later).
final repositoryProvider = Provider<ClinicRepository>((ref) => throw UnimplementedError('repositoryProvider not overridden'));

/// Bumps on every backend change so the screens below rebuild live
/// (the Firebase version will use Firestore streams instead).
class RepoTick extends Notifier<int> {
  @override
  int build() {
    final sub = ref.watch(repositoryProvider).changes.listen((_) => state++);
    ref.onDispose(sub.cancel);
    return 0;
  }
}

final repoTickProvider = NotifierProvider<RepoTick, int>(RepoTick.new);

/// Re-reads [read] whenever the backend changes.
T _live<T>(Ref ref, T Function(ClinicRepository r) read) {
  ref.watch(repoTickProvider);
  return read(ref.watch(repositoryProvider));
}

/// Pakistan date "today", re-checked every minute (crossing midnight).
final todayProvider = StreamProvider<String>((ref) async* {
  yield dayKey(pktNow());
  yield* Stream.periodic(const Duration(minutes: 1), (_) => dayKey(pktNow())).distinct();
});

String _today(Ref ref) => ref.watch(todayProvider).value ?? dayKey(pktNow());

final currentUserProvider = Provider<UserAccount?>((ref) => _live(ref, (r) => r.currentUser));

/// D-52: opened from an invite / reset email link → choose a password first.
final needsNewPasswordProvider = Provider<bool>((ref) => _live(ref, (r) => r.needsNewPassword));

final clinicProvider = Provider.family<ClinicAccount?, String>((ref, id) => _live(ref, (r) => r.clinic(id)));
final clinicsProvider = Provider<List<ClinicAccount>>((ref) => _live(ref, (r) => r.clinics()));
final adminDataLoadingProvider = Provider<bool>((ref) => _live(ref, (r) => r.adminDataLoading));

final doctorsProvider = Provider.family<List<Doctor>, String>((ref, clinicId) => _live(ref, (r) => r.doctors(clinicId)));
final allDoctorsProvider =
    Provider.family<List<Doctor>, String>((ref, clinicId) => _live(ref, (r) => r.doctors(clinicId, includeInactive: true)));

final queueDayProvider = Provider.family<QueueDay, (String, String)>(
    (ref, a) => _live(ref, (r) => r.queueDay(a.$1, a.$2, _today(ref))));

/// Today's tokens of a clinic.
final todayTokensProvider = Provider.family<List<QueueToken>, String>(
    (ref, clinicId) => _live(ref, (r) => r.tokens(clinicId, _today(ref))));

final tokensOnProvider = Provider.family<List<QueueToken>, (String, String)>((ref, a) => _live(ref, (r) => r.tokens(a.$1, a.$2)));

final tokenProvider = Provider.family<QueueToken?, String>((ref, id) => _live(ref, (r) => r.tokenById(id)));

final clinicPatientProvider =
    Provider.family<ClinicPatient?, (String, String)>((ref, a) => _live(ref, (r) => r.clinicPatient(a.$1, a.$2)));

final followUpsProvider = Provider.family<List<FollowUp>, String>((ref, clinicId) => _live(ref, (r) => r.followUps(clinicId)));

final clinicLoginProvider = Provider.family<UserAccount?, String>((ref, clinicId) => _live(ref, (r) => r.clinicLogin(clinicId)));

final invoicesProvider = Provider.family<List<Invoice>, String?>((ref, clinicId) => _live(ref, (r) => r.invoices(clinicId: clinicId)));

final activityProvider = Provider.family<List<ActivityLog>, String?>((ref, clinicId) => _live(ref, (r) => r.activity(clinicId: clinicId)));

final adminSettingsProvider = Provider<AdminSettings>((ref) => _live(ref, (r) => r.settings));

final patientProvider = Provider.family<Patient?, String>((ref, id) => _live(ref, (r) => r.patient(id)));

/// Follow-up status as staff see it: a pending one past its date is Missed.
FollowUpStatus effectiveFollowUpStatus(FollowUp f, String today) =>
    f.status == FollowUpStatus.pending && f.dueDate.compareTo(today) < 0 ? FollowUpStatus.missed : f.status;

/// Ticks every second while some screen needs a countdown (Undo Next).
final secondTickerProvider = StreamProvider.autoDispose<int>((ref) => Stream.periodic(const Duration(seconds: 1), (i) => i));

/// Shows the "New" highlight on app bookings for two minutes.
bool isNewBooking(QueueToken t) =>
    t.source == TokenSource.app && t.status == TokenStatus.booked && pktNow().difference(t.token.createdAt).inSeconds < 120;

/// Small helper for fire-and-forget futures in callbacks.
void unawaitedSafe(Future<void> f) => unawaited(f.catchError((_) {}));

/// When each doctor was added (D-19): the Super Admin's New doctors card / marks.
final doctorAddedAtProvider = Provider<Map<String, DateTime>>((ref) => _live(ref, (r) => r.doctorAddedAt()));

/// A doctor counts as "new" for 7 days after the clinic adds it (A-01).
bool isNewDoctor(DateTime? addedAt) => addedAt != null && pktNow().difference(addedAt).inDays < 7;

/// D-32 / A-09: same-doctor suggestions (Super Admin only).
final linkSuggestionsProvider = Provider<List<LinkSuggestion>>((ref) => _live(ref, (r) => r.linkSuggestions()));
