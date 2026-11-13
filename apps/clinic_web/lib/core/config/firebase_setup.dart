import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:asani_core/asani_core.dart';

/// Build-time settings (`--dart-define`), same names as the patient app:
///
/// ```
/// flutter run -d chrome                                   # demo backend (no Firebase)
/// flutter run -d chrome --dart-define=BACKEND=firebase \
///   --dart-define=USE_FUNCTIONS_EMULATOR=true             # dev project + local functions
/// flutter run -d chrome --dart-define=BACKEND=firebase \
///   --dart-define=USE_EMULATOR=true                       # everything on emulators
/// ```
abstract final class Env {
  static const String backend = String.fromEnvironment('BACKEND', defaultValue: 'demo');
  static const String env = String.fromEnvironment('ENV', defaultValue: 'dev');
  static const bool useEmulator = bool.fromEnvironment('USE_EMULATOR', defaultValue: false);
  static const bool useFunctionsEmulator = bool.fromEnvironment('USE_FUNCTIONS_EMULATOR', defaultValue: false);
  static const String emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

  static bool get useFirebase => backend == 'firebase';
  static bool get isProd => env == 'prod';
}

/// Functions region (ARCHITECTURE.md §5).
const firebaseRegion = 'asia-south1';

/// The dev project (asani-b2b17). Same web app as the patient app's web build;
/// these keys are public client identifiers, not secrets. Prod options will be
/// generated with `flutterfire configure` before launch (never committed).
const _devWeb = FirebaseOptions(
  apiKey: 'AIzaSyBlZsb5LLpUh3X_KbJJzZLUoT8RGwDFgpA',
  appId: '1:835282537903:web:df86d01cf0e5b4665df35a',
  messagingSenderId: '835282537903',
  projectId: 'asani-b2b17',
  authDomain: 'asani-b2b17.firebaseapp.com',
  storageBucket: 'asani-b2b17.firebasestorage.app',
);

abstract final class FirebaseSetup {
  static Future<void> init() async {
    if (Env.isProd) throw StateError('Prod Firebase options are not set up yet (AGENTS.md §7).');
    await Firebase.initializeApp(options: _devWeb);
    // Stay logged in on this browser until Log out (PRD §5.4).
    await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
    final host = Env.emulatorHost;
    if (Env.useEmulator) {
      await FirebaseAuth.instance.useAuthEmulator(host, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
      FirebaseFunctions.instanceFor(region: firebaseRegion).useFunctionsEmulator(host, 5001);
      AppLogger.info('Firebase emulators at $host');
    } else if (Env.useFunctionsEmulator) {
      FirebaseFunctions.instanceFor(region: firebaseRegion).useFunctionsEmulator(host, 5001);
      AppLogger.info('Functions emulator at $host:5001 (Auth and Firestore: dev project)');
    }
  }
}
