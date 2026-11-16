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
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inter is bundled in assets/google_fonts (DESIGN.md §3.2): never fetch it.
  GoogleFonts.config.allowRuntimeFetching = false;
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Demo backend: demo mode, plus device settings in Firebase mode.
  final backend = await DemoBackend.create();

  // Login: Firebase with --dart-define=BACKEND=firebase, demo otherwise (D-11).
  final overrides = [backendProvider.overrideWithValue(backend)];
  if (Env.useFirebase) {
    try {
      await FirebaseSetup.init();
    } catch (e) {
      // Not configured yet (FIREBASE_SETUP.md): say so instead of a blank screen.
      runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Firebase setup is not finished.\n\n$e', textAlign: TextAlign.center),
            ),
          ),
        ),
      ));
      return;
    }
    backend.stopSimulator(); // queues move via tools/queue-sim (step 9)

    // Step 10: FCM queue notifications.
    final push = PushService();
    try {
      await push.init();
      // The OS permission is the truth: if it was turned off in phone settings,
      // show "Off" in Account (and the primer can ask again).
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
  }

  runApp(ProviderScope(overrides: overrides, child: const AsaniApp()));
}
