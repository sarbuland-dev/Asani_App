import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../data/repositories/repositories.dart';
import '../../features/account/account_screen.dart';
import '../../features/auth/intro_screen.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/auth/phone_screen.dart';
import '../../features/auth/profile_setup_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/booking/booking_screen.dart';
import '../../features/booking/booking_success_screen.dart';
import '../../features/clinic/clinic_screen.dart';
import '../../features/clinic/doctor_profile_screen.dart';
import '../../features/family/family_screen.dart';
import '../../features/family/profile_detail_screen.dart';
import '../../features/family/profile_form_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/notifications/notifications_list_screen.dart';
import '../../features/notifications/primer_screen.dart';
import 'package:asani_core/asani_core.dart';

import '../../features/search/search_tabs_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/token/token_screen.dart';
import '../../features/token/token_slip_screen.dart';
import '../../features/tokens/tokens_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// S-01 stays on screen at least this long on every launch (PRD D-25).
const splashMinDuration = Duration(milliseconds: 1500);

/// Turns true once the splash has been ON SCREEN for [splashMinDuration].
/// The count starts when the splash draws its first frame ([start]), not when
/// the app starts loading: on a slow phone the old timer ran out before the
/// splash was visible, so it was skipped.
class SplashTimer extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    return false;
  }

  void start() {
    if (state || _timer != null) return;
    _timer = Timer(splashMinDuration, () => state = true);
  }
}

final splashDoneProvider = NotifierProvider<SplashTimer, bool>(SplashTimer.new);

/// Re-runs the router redirect whenever the auth state or the splash timer changes.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
    ref.listen(splashDoneProvider, (_, _) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthListenable(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final loc = state.matchedLocation;
      final onLogin = loc.startsWith('/login');
      if (auth.isLoading && !auth.hasValue) return loc == '/splash' ? null : '/splash';
      // Keep the splash for its minimum time. Only holds while we ARE on the
      // splash, so a notification tap that opens a token is never sent back.
      if (loc == '/splash' && !ref.read(splashDoneProvider)) return null;
      final status = auth.value?.status ?? AuthStatus.signedOut;
      switch (status) {
        case AuthStatus.signedOut:
          // First launch: intro pages once, then phone login (D-29).
          if (!ref.read(settingsRepositoryProvider).settings.introSeen) return loc == '/intro' ? null : '/intro';
          return loc == '/login/phone' ? null : '/login/phone';
        case AuthStatus.codeSent:
          return (loc == '/login/otp' || loc == '/login/phone') ? null : '/login/otp';
        case AuthStatus.needsProfile:
          return loc == '/login/profile' ? null : '/login/profile';
        case AuthStatus.signedIn:
          if (onLogin || loc == '/splash' || loc == '/intro') return '/home';
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/intro', builder: (_, _) => const IntroScreen()),
      GoRoute(path: '/login/phone', builder: (_, _) => const PhoneScreen()),
      GoRoute(path: '/login/otp', builder: (_, _) => const OtpScreen()),
      GoRoute(path: '/login/profile', builder: (_, _) => const ProfileSetupScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/tokens', builder: (_, _) => const TokensScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/family', builder: (_, _) => const FamilyScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/account', builder: (_, _) => const AccountScreen())]),
        ],
      ),
      // Clinics | Doctors tabs (D-31): /search?q=… or /search?tab=doctors&speciality=heart
      GoRoute(
        path: '/search',
        builder: (_, s) => SearchTabsScreen(
          initialQuery: s.uri.queryParameters['q'] ?? '',
          doctors: s.uri.queryParameters['tab'] == 'doctors',
          speciality: Speciality.fromKey(s.uri.queryParameters['speciality']),
        ),
      ),
      GoRoute(path: '/clinic/:clinicId', builder: (_, s) => ClinicScreen(clinicId: s.pathParameters['clinicId']!)),
      // S-07b doctor profile (board P3b): from Search by doctor → Book token.
      GoRoute(
        path: '/doctor/:clinicId/:doctorId',
        builder: (_, s) => DoctorProfileScreen(clinicId: s.pathParameters['clinicId']!, doctorId: s.pathParameters['doctorId']!),
      ),
      // Clinic QR deep link (PRD F-11).
      GoRoute(path: '/c/:clinicId', redirect: (_, s) => '/clinic/${s.pathParameters['clinicId']}'),
      GoRoute(
        path: '/book/:clinicId/:doctorId',
        builder: (_, s) => BookingScreen(
          clinicId: s.pathParameters['clinicId']!,
          doctorId: s.pathParameters['doctorId']!,
          initialPatientId: s.uri.queryParameters['patient'],
          initialDate: s.uri.queryParameters['date'],
        ),
      ),
      GoRoute(path: '/booked/:tokenId', builder: (_, s) => BookingSuccessScreen(tokenId: s.pathParameters['tokenId']!)),
      GoRoute(path: '/token/:tokenId', builder: (_, s) => TokenScreen(tokenId: s.pathParameters['tokenId']!)),
      GoRoute(path: '/token/:tokenId/slip', builder: (_, s) => TokenSlipScreen(tokenId: s.pathParameters['tokenId']!)),
      GoRoute(path: '/family/new', builder: (_, _) => const ProfileFormScreen()),
      GoRoute(path: '/family/:patientId', builder: (_, s) => ProfileDetailScreen(patientId: s.pathParameters['patientId']!)),
      GoRoute(path: '/family/:patientId/edit', builder: (_, s) => ProfileFormScreen(patientId: s.pathParameters['patientId'])),
      // S-17 primer as a bottom sheet (board P4, D-50).
      GoRoute(path: '/notifications', pageBuilder: (_, s) => BottomSheetPage(key: s.pageKey, child: PrimerScreen(next: s.uri.queryParameters['next']))),
      GoRoute(path: '/inbox', builder: (_, _) => const NotificationsListScreen()), // S-19, D-45
    ],
  );
});
