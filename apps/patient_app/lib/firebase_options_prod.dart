// PLACEHOLDER — replaced by `flutterfire configure` (see docs/02-setup.md §4).
//
// flutterfire configure --project=asani-prod --out=lib/firebase_options_prod.dart ...
//
// Until then, run the prod flavor without --dart-define=BACKEND=supabase (demo backend).
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => throw UnsupportedError(
        'Firebase is not configured for asani-prod yet. '
        'Run flutterfire configure (docs/02-setup.md §4), '
        'or run without --dart-define=BACKEND=supabase to use demo data.',
      );
}
