import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../data/repositories/repositories.dart';
import '../../features/account/account_screen.dart';
import '../../features/auth/otp_screen.dart';
import '../../features/auth/phone_screen.dart';
import '../../features/auth/profile_setup_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/booking/booking_screen.dart';
import '../../features/booking/booking_success_screen.dart';
import '../../features/clinic/clinic_screen.dart';
import '../../features/family/family_screen.dart';
import '../../features/family/profile_detail_screen.dart';
import '../../features/family/profile_form_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/notifications/primer_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/token/token_screen.dart';
import '../../features/token/token_slip_screen.dart';
import '../../features/tokens/tokens_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// S-01 stays on screen at least this long on every launch (PRD D-25).
const splashMinDuration = Duration(milliseconds: 1500);

/// Turns true once the splash has been shown for [splashMinDuration].
class SplashTimer extends Notifier<bool> {
  @override
  bool build() {
    final timer = Timer(splashMinDuration, () => state = true);
    ref.onDispose(timer.cancel);
    return false;
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
          // Splash → phone login. The intro pages were removed (D-28).
          return loc == '/login/phone' ? null : '/login/phone';
        case AuthStatus.codeSent:
          return (loc == '/login/otp' || loc == '/login/phone') ? null : '/login/otp';
        case AuthStatus.needsProfile:
          return loc == '/login/profile' ? null : '/login/profile';
        case AuthStatus.signedIn:
          if (onLogin || loc == '/splash') return '/home';
          return null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
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
      GoRoute(path: '/search', builder: (_, s) => SearchScreen(initialQuery: s.uri.queryParameters['q'] ?? '')),
      GoRoute(path: '/clinic/:clinicId', builder: (_, s) => ClinicScreen(clinicId: s.pathParameters['clinicId']!)),
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
      GoRoute(path: '/notifications', builder: (_, s) => PrimerScreen(next: s.uri.queryParameters['next'])),
    ],
  );
});
