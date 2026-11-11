// PLACEHOLDER — replaced by `flutterfire configure` (see apps/patient_app/FIREBASE_SETUP.md).
//
// flutterfire configure --project=asani-prod --out=lib/firebase_options_prod.dart ...
//
// Until then, run the app without --dart-define=BACKEND=firebase (demo backend).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw UnsupportedError(
        'Firebase is not configured for asani-prod yet. '
        'Run flutterfire configure (apps/patient_app/FIREBASE_SETUP.md), '
        'or run without --dart-define=BACKEND=firebase to use demo data.',
      );
}
