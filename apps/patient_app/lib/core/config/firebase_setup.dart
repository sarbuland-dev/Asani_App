import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../../firebase_options_dev.dart' as dev;
import '../../firebase_options_prod.dart' as prod;
import 'package:asani_core/asani_core.dart';
import 'env.dart';

/// Firebase region for Functions (docs: asia-south1, Mumbai).
const firebaseRegion = 'asia-south1';

abstract final class FirebaseSetup {
  static Future<void> init() async {
    final options = Env.isProd ? prod.DefaultFirebaseOptions.currentPlatform : dev.DefaultFirebaseOptions.currentPlatform;
    await Firebase.initializeApp(options: options);
    await _activateAppCheck();
    await _connectEmulators();
    if (Env.authTestMode && !Env.isProd) {
      // No reCAPTCHA; only Firebase test phone numbers work (FIREBASE_SETUP.md).
      await FirebaseAuth.instance.setSettings(appVerificationDisabledForTesting: true);
      AppLogger.warn('AUTH_TEST_MODE on: reCAPTCHA disabled, test numbers only');
    }
  }

  /// App Check (ARCHITECTURE.md §6): prod functions only accept calls from
  /// the real app. Play Integrity on Android, App Attest on iOS; dev uses the
  /// debug provider (dev functions don't enforce it). Web preview: skipped.
  static Future<void> _activateAppCheck() async {
    if (kIsWeb || Env.useEmulator) return;
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: Env.isProd ? const AndroidPlayIntegrityProvider() : const AndroidDebugProvider(),
        providerApple: Env.isProd ? const AppleAppAttestProvider() : const AppleDebugProvider(),
      );
    } catch (e) {
      AppLogger.warn('App Check not active: $e');
    }
  }

  static String get _emulatorHost {
    if (Env.emulatorHost.isNotEmpty) return Env.emulatorHost; // real phone
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return '10.0.2.2'; // Android emulator
    return 'localhost';
  }

  /// Only with --dart-define=USE_EMULATOR=true, and never in prod (AGENTS.md §7).
  static Future<void> _connectEmulators() async {
    if (Env.isProd) return;
    // A host given with EMULATOR_HOST is used as is: on a real phone with
    // `adb reverse tcp:5001 tcp:5001`, 127.0.0.1 must NOT become 10.0.2.2
    // (that address only exists inside the Android emulator).
    final remap = Env.emulatorHost.isEmpty;
    if (Env.useFunctionsEmulator && !Env.useEmulator) {
      FirebaseFunctions.instanceFor(region: firebaseRegion)
          .useFunctionsEmulator(_emulatorHost, 5001, automaticHostMapping: remap);
      AppLogger.info('Functions emulator at $_emulatorHost:5001 (Auth and Firestore: dev project)');
      return;
    }
    if (!Env.useEmulator) return;
    final host = _emulatorHost;
    await FirebaseAuth.instance.useAuthEmulator(host, 9099, automaticHostMapping: remap);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080, automaticHostMapping: remap);
    FirebaseFunctions.instanceFor(region: firebaseRegion).useFunctionsEmulator(host, 5001, automaticHostMapping: remap);
    AppLogger.info('Firebase emulators connected at $host');
  }
}
