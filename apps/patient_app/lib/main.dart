import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/config/firebase_setup.dart';
import 'core/push/push_service.dart';
import 'package:asani_core/asani_core.dart';
import 'data/demo/demo_backend.dart';
import 'data/firebase/firebase_auth_repository.dart';
import 'data/firebase/firestore_clinic_repository.dart';
import 'data/firebase/firestore_patient_repository.dart';
import 'data/firebase/firestore_token_repository.dart';
import 'data/firebase/firestore_notification_repository.dart';
import 'data/providers.dart';
import 'data/repositories/repositories.dart';
import 'data/supabase/supabase_auth_repository.dart';
import 'data/supabase/supabase_push_account.dart';
import 'data/supabase/supabase_repositories.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inter is bundled in assets/google_fonts (DESIGN.md §3.2): never fetch it.
  GoogleFonts.config.allowRuntimeFetching = false;
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Demo backend: demo mode, plus device settings in Firebase mode.
  final backend = await DemoBackend.create();

  // Login: Supabase with --dart-define=BACKEND=supabase (D-52), Firebase with BACKEND=firebase, demo otherwise (D-11).
  final overrides = [backendProvider.overrideWithValue(backend)];
  if (Env.useSupabase) {
    try {
      await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);
    } catch (e) {
      runApp(_SetupError('Supabase setup failed.\n\n$e'));
      return;
    }
    backend.stopSimulator(); // the real queue moves from the clinic web (or tools/queue-sim)

    // Push stays on Firebase Cloud Messaging (free Spark plan); the device token goes to Supabase.
    PushService? push;
    try {
      await FirebaseSetup.initForPushOnly();
      push = await _startPush(backend, SupabasePushAccount());
      overrides.add(pushServiceProvider.overrideWithValue(push));
    } catch (e) {
      AppLogger.warn('Push not available: $e');
    }

    // Phase 5 (D-52): login, clinics, doctors, queue, tokens, family, follow-ups and the notifications list.
    final auth = SupabaseAuthRepository(backend, beforeSignOut: push?.unregister);
    overrides.add(authRepositoryProvider.overrideWithValue(auth));
    // A device can only be saved once the account row exists (after profile setup), so register on sign-in.
    if (push != null) {
      final p = push;
      auth.watchAuth().where((s) => s.status == AuthStatus.signedIn).map((s) => s.user?.uid).distinct().listen((_) async {
        if (await p.permission() == PushPermission.granted) await p.register();
      });
    }
    final tokens = SupabaseTokenRepository(alerts: push?.alerts);
    overrides.add(tokenRepositoryProvider.overrideWithValue(tokens));
    overrides.add(clinicRepositoryProvider.overrideWithValue(SupabaseClinicRepository(tokens)));
    overrides.add(queueRepositoryProvider.overrideWithValue(SupabaseQueueRepository()));
    overrides.add(patientRepositoryProvider.overrideWithValue(SupabasePatientRepository()));
    overrides.add(followUpRepositoryProvider.overrideWithValue(SupabaseFollowUpRepository()));
    overrides.add(notificationRepositoryProvider.overrideWithValue(SupabaseNotificationRepository()));
  } else if (Env.useFirebase) {
    try {
      await FirebaseSetup.init();
    } catch (e) {
      // Not configured yet (FIREBASE_SETUP.md): say so instead of a blank screen.
      runApp(_SetupError('Firebase setup is not finished.\n\n$e'));
      return;
    }
    backend.stopSimulator(); // queues move via tools/queue-sim (step 9)

    // Step 10: FCM queue notifications.
    final push = await _startPush(backend, FirebasePushAccount());
    overrides.add(pushServiceProvider.overrideWithValue(push));

    final auth = FirebaseAuthRepository(backend, beforeSignOut: push.unregister);
    overrides.add(authRepositoryProvider.overrideWithValue(auth));
    // Steps 1-2 (DEMO_TO_FIREBASE.txt): clinics and doctors from Firestore.
    final tokens = FirestoreTokenRepository(alerts: push.alerts);
    overrides.add(clinicRepositoryProvider.overrideWithValue(FirestoreClinicRepository(backend, tokens)));
    // Step 3: family profiles in Firestore.
    overrides.add(patientRepositoryProvider.overrideWithValue(FirestorePatientRepository(backend)));
    // Steps 5-8: booking and cancelling via Cloud Functions; tokens and queue days from Firestore.
    overrides.add(tokenRepositoryProvider.overrideWithValue(tokens));
    overrides.add(queueRepositoryProvider.overrideWithValue(FirestoreQueueRepository()));
    // Step 11: follow-ups from Firestore.
    overrides.add(followUpRepositoryProvider.overrideWithValue(FirestoreFollowUpRepository()));
    // D-45: in-app notifications list (written by functions with every push).
    overrides.add(notificationRepositoryProvider.overrideWithValue(FirestoreNotificationRepository()));
  }

  runApp(ProviderScope(overrides: overrides, child: const AsaniApp()));
}

/// FCM queue notifications. The OS permission is the truth: if it was turned off in phone settings,
/// Account shows "Off" (and the primer can ask again).
Future<PushService> _startPush(DemoBackend backend, PushAccount account) async {
  final push = PushService(account: account);
  try {
    await push.init();
    final permission = await push.permission();
    final s = backend.settings;
    if (permission != PushPermission.granted && s.notificationsAllowed) {
      await backend.update(s.copyWith(notificationsAllowed: false));
    } else if (permission == PushPermission.granted && s.primerShown && !s.notificationsAllowed) {
      await backend.update(s.copyWith(notificationsAllowed: true));
    }
  } catch (e) {
    AppLogger.warn('Push setup failed: $e');
  }
  return push;
}

/// Shown instead of a blank screen when the backend cannot start.
class _SetupError extends StatelessWidget {
  const _SetupError(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(padding: const EdgeInsets.all(24), child: Text(message, textAlign: TextAlign.center)),
          ),
        ),
      );
}
