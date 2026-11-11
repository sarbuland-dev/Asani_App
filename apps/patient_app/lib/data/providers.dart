import 'package:asani_core/asani_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
final queueSimulatorProvider = Provider<QueueSimulator>((ref) => ref.watch(backendProvider));

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
  (ref) => ref.watch(clinicRepositoryProvider).watchRecentClinics(),
);

// ---- queue

typedef DayKey = ({String doctorId, String date});

final queueDayProvider = StreamProvider.family<QueueDay, DayKey>(
  (ref, k) => ref.watch(queueRepositoryProvider).watchDay(k.doctorId, k.date),
);

// ---- tokens

final myTokensProvider = StreamProvider<List<Token>>((ref) => ref.watch(tokenRepositoryProvider).watchMyTokens());

final myActiveTokensProvider = Provider<AsyncValue<List<Token>>>((ref) => ref.watch(myTokensProvider).whenData(
      (list) => list.where((t) => t.status.isActive).toList()
        ..sort((a, b) {
          final byDate = a.date.compareTo(b.date);
          return byDate != 0 ? byDate : a.number.compareTo(b.number);
        }),
    ));

final myPastTokensProvider = Provider<AsyncValue<List<Token>>>((ref) => ref.watch(myTokensProvider).whenData(
      (list) => list.where((t) => !t.status.isActive).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
    ));

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
    final ahead = patientsAhead(d.activeNumbers, token.number);
    return TokenPosition(day: d, ahead: ahead, waitMinutes: estimatedWaitMinutes(ahead, doctor?.avgConsultMinutes ?? 10));
  });
});

// ---- patients / follow-ups

final myPatientsProvider = StreamProvider<List<Patient>>((ref) => ref.watch(patientRepositoryProvider).watchMyPatients());

final myFollowUpsProvider = StreamProvider<List<FollowUp>>((ref) => ref.watch(followUpRepositoryProvider).watchMyFollowUps());

final upcomingFollowUpsProvider = Provider<List<FollowUp>>((ref) {
  final today = dayKey(DateTime.now());
  return (ref.watch(myFollowUpsProvider).value ?? const [])
      .where((f) => f.status == FollowUpStatus.pending && f.dueDate.compareTo(today) >= 0)
      .toList();
});

/// A ticking clock so time-based labels (session started, ended) refresh.
final clockProvider = StreamProvider<DateTime>(
  (ref) => Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now()),
);

DateTime nowFrom(WidgetRef ref) => ref.watch(clockProvider).value ?? DateTime.now();
