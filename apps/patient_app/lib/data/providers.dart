import 'package:asani_core/asani_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/push/push_service.dart';
import 'demo/demo_backend.dart';
import 'repositories/repositories.dart';

/// The backend instance. Overridden in main() with the created DemoBackend;
/// later a Firebase implementation is plugged in here.
final backendProvider = Provider<DemoBackend>((ref) => throw UnimplementedError('backendProvider not overridden'));

final authRepositoryProvider = Provider<AuthRepository>((ref) => ref.watch(backendProvider));
final clinicRepositoryProvider = Provider<ClinicRepository>((ref) => ref.watch(backendProvider));
final queueRepositoryProvider = Provider<QueueRepository>((ref) => ref.watch(backendProvider));
final tokenRepositoryProvider = Provider<TokenRepository>((ref) => ref.watch(backendProvider));
final patientRepositoryProvider = Provider<PatientRepository>((ref) => ref.watch(backendProvider));
final followUpRepositoryProvider = Provider<FollowUpRepository>((ref) => ref.watch(backendProvider));
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) => ref.watch(backendProvider));
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) => ref.watch(backendProvider));
final queueSimulatorProvider = Provider<QueueSimulator>((ref) => ref.watch(backendProvider));

/// FCM push (Firebase mode only); null in demo mode.
final pushServiceProvider = Provider<PushService?>((ref) => null);

// ---- auth / user

final authStateProvider = StreamProvider<AuthState>((ref) => ref.watch(authRepositoryProvider).watchAuth());

final currentUserProvider = Provider<AppUser?>((ref) => ref.watch(authStateProvider).value?.user);

final settingsProvider = StreamProvider<AppSettings>((ref) => ref.watch(settingsRepositoryProvider).watchSettings());

// ---- clinics

final citiesProvider = StreamProvider<List<String>>((ref) => ref.watch(clinicRepositoryProvider).watchCities());

final selectedCityProvider = Provider<String>((ref) => ref.watch(currentUserProvider)?.city ?? 'Lahore');

final clinicsProvider = StreamProvider.family<List<Clinic>, String>(
  (ref, city) => ref.watch(clinicRepositoryProvider).watchClinics(city),
);

final clinicProvider = StreamProvider.family<Clinic?, String>(
  (ref, id) => ref.watch(clinicRepositoryProvider).watchClinic(id),
);

final doctorsProvider = StreamProvider.family<List<Doctor>, String>(
  (ref, clinicId) => ref.watch(clinicRepositoryProvider).watchDoctors(clinicId),
);

final doctorProvider = StreamProvider.family<Doctor?, String>(
  (ref, id) => ref.watch(clinicRepositoryProvider).watchDoctor(id),
);

final doctorsByClinicProvider = StreamProvider<Map<String, List<Doctor>>>(
  (ref) => ref.watch(clinicRepositoryProvider).watchDoctorsByClinic(),
);

final recentClinicsProvider = StreamProvider<List<Clinic>>(
  (ref) {
    ref.watch(currentUserProvider.select((u) => u?.uid)); // per signed-in user
    return ref.watch(clinicRepositoryProvider).watchRecentClinics();
  },
);

// ---- queue

typedef DayKey = ({String doctorId, String date});

final queueDayProvider = StreamProvider.family<QueueDay, DayKey>(
  (ref, k) => ref.watch(queueRepositoryProvider).watchDay(k.doctorId, k.date),
);

// ---- tokens

final myTokensProvider = StreamProvider<List<Token>>((ref) {
  // Restart on login/logout: the Firestore query is per signed-in user.
  ref.watch(currentUserProvider.select((u) => u?.uid));
  return ref.watch(tokenRepositoryProvider).watchMyTokens();
});

/// D-27: is this token still live for the patient (see `tokenIsLive`)? Uses
/// the minute clock, so a token leaves "Active" 1 h after its session ends.
final tokenIsLiveProvider = Provider<bool Function(Token)>((ref) {
  final now = ref.watch(clockProvider).value ?? pktNow();
  final doctors = {for (final list in (ref.watch(doctorsByClinicProvider).value ?? const {}).values) for (final d in list) d.id: d};
  return (t) => tokenIsLive(t, doctor: doctors[t.doctorId], now: now);
});

final myActiveTokensProvider = Provider<AsyncValue<List<Token>>>((ref) {
  final live = ref.watch(tokenIsLiveProvider);
  return ref.watch(myTokensProvider).whenData(
        (list) => list.where(live).toList()
          ..sort((a, b) {
            final byDate = a.date.compareTo(b.date);
            return byDate != 0 ? byDate : a.number.compareTo(b.number);
          }),
      );
});

/// Older past tokens loaded on demand ("Load older"), beyond the live latest 100.
class OlderTokens extends Notifier<({List<Token> tokens, bool done, bool loading})> {
  @override
  ({List<Token> tokens, bool done, bool loading}) build() {
    ref.watch(currentUserProvider.select((u) => u?.uid)); // reset per signed-in user
    return (tokens: const [], done: false, loading: false);
  }

  Future<void> loadMore() async {
    if (state.done || state.loading) return;
    final all = [...?ref.read(myTokensProvider).value, ...state.tokens];
    if (all.isEmpty) {
      state = (tokens: state.tokens, done: true, loading: false);
      return;
    }
    final oldest = all.map((t) => t.createdAt).reduce((a, b) => a.isBefore(b) ? a : b);
    state = (tokens: state.tokens, done: false, loading: true);
    try {
      final more = await ref.read(tokenRepositoryProvider).loadOlderTokens(oldest);
      state = (tokens: [...state.tokens, ...more], done: more.isEmpty, loading: false);
    } catch (e) {
      AppLogger.warn('load older tokens: $e');
      state = (tokens: state.tokens, done: false, loading: false);
    }
  }
}

final olderTokensProvider = NotifierProvider<OlderTokens, ({List<Token> tokens, bool done, bool loading})>(OlderTokens.new);

/// Finished tokens, plus active ones whose session is over (shown as "Session over").
final myPastTokensProvider = Provider<AsyncValue<List<Token>>>((ref) {
  final live = ref.watch(tokenIsLiveProvider);
  final older = ref.watch(olderTokensProvider).tokens;
  return ref.watch(myTokensProvider).whenData((list) {
    final byId = {for (final t in [...older, ...list]) t.id: t};
    return byId.values.where((t) => !live(t)).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  });
});

final tokenProvider = StreamProvider.family<Token?, String>(
  (ref, id) => ref.watch(tokenRepositoryProvider).watchToken(id),
);

/// Live position for a token: patients ahead + estimated wait (ARCHITECTURE §4).
class TokenPosition {
  const TokenPosition({required this.day, required this.ahead, required this.waitMinutes});
  final QueueDay day;
  final int ahead;
  final int waitMinutes;
}

final tokenPositionProvider = Provider.family<AsyncValue<TokenPosition>, String>((ref, tokenId) {
  final token = ref.watch(tokenProvider(tokenId)).value;
  if (token == null) return const AsyncLoading();
  final doctor = ref.watch(doctorProvider(token.doctorId)).value;
  final day = ref.watch(queueDayProvider((doctorId: token.doctorId, date: token.date)));
  return day.whenData((d) {
    // D-35: a Skipped patient who checked in again is called right after the
    // current patient, so nobody is ahead, whatever the token numbers say.
    final ahead = token.isNextUp ? 0 : patientsAhead(d.activeNumbers, token.number);
    return TokenPosition(day: d, ahead: ahead, waitMinutes: estimatedWaitMinutes(ahead, doctor?.avgConsultMinutes ?? 10));
  });
});

// ---- patients / follow-ups

final myPatientsProvider = StreamProvider<List<Patient>>((ref) {
  // Restart on login/logout: the Firestore query is per signed-in user.
  ref.watch(currentUserProvider.select((u) => u?.uid));
  return ref.watch(patientRepositoryProvider).watchMyPatients();
});

final myFollowUpsProvider = StreamProvider<List<FollowUp>>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.uid)); // per signed-in user
  return ref.watch(followUpRepositoryProvider).watchMyFollowUps();
});

final upcomingFollowUpsProvider = Provider<List<FollowUp>>((ref) {
  final today = dayKey(pktNow());
  return (ref.watch(myFollowUpsProvider).value ?? const [])
      .where((f) => f.status == FollowUpStatus.pending && f.dueDate.compareTo(today) >= 0)
      .toList();
});

/// A ticking clock so time-based labels (session started, ended) refresh.
final clockProvider = StreamProvider<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 30), (_) => pktNow()),
);

DateTime nowFrom(WidgetRef ref) => ref.watch(clockProvider).value ?? pktNow();

// ---- Notifications list (PRD D-43) ----
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.uid)); // per signed-in user
  return ref.watch(notificationRepositoryProvider).watchNotifications();
});

final notificationsSeenAtProvider = StreamProvider<DateTime?>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.uid));
  return ref.watch(notificationRepositoryProvider).watchSeenAt();
});

/// Bell badge: notifications newer than the last time the list was opened.
final unreadNotificationsProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).value ?? const <AppNotification>[];
  final seen = ref.watch(notificationsSeenAtProvider).value;
  return list.where((n) => n.unreadSince(seen)).length;
});
