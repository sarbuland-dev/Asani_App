import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/firebase_setup.dart';
import 'data/clinic_repository.dart';
import 'data/demo_clinic_repository.dart';
import 'data/firebase_clinic_repository.dart';
import 'data/providers.dart';

/// Asani Clinic Web (PRD-CLINIC-WEB): clinic dashboard + super admin.
///
/// `--dart-define=BACKEND=firebase`: real Firebase (same project as the
/// patient app). Without it: the in-memory demo backend.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ClinicRepository repo;
  if (Env.useFirebase) {
    try {
      await FirebaseSetup.init();
      repo = await FirebaseClinicRepository.create();
    } catch (e) {
      runApp(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Firebase setup is not finished.\n\n$e', textAlign: TextAlign.center)))),
      ));
      return;
    }
  } else {
    repo = DemoClinicRepository();
  }
  runApp(ProviderScope(
    overrides: [repositoryProvider.overrideWithValue(repo)],
    child: const ClinicWebApp(),
  ));
}
