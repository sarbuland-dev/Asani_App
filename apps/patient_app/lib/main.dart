import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'core/config/firebase_setup.dart';
import 'data/demo/demo_backend.dart';
import 'data/firebase/firebase_auth_repository.dart';
import 'data/firebase/firestore_clinic_repository.dart';
import 'data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Doctors, queues, tokens and family: demo data until they move to Firebase.
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
    final auth = FirebaseAuthRepository(backend);
    overrides.add(authRepositoryProvider.overrideWithValue(auth));
    // Step 1 (DEMO_TO_FIREBASE.txt): clinics from Firestore; doctors still demo.
    overrides.add(clinicRepositoryProvider.overrideWithValue(FirestoreClinicRepository(backend)));
  }

  runApp(ProviderScope(overrides: overrides, child: const AsaniApp()));
}
