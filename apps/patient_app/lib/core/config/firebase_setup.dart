import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options_dev.dart' as dev;
import '../../firebase_options_prod.dart' as prod;
import 'env.dart';

/// Firebase is used ONLY for push (FCM, free Spark plan) since the backend moved to Supabase (D-52):
/// no Firebase Auth, Firestore, Functions or App Check any more.
abstract final class FirebaseSetup {
  static Future<void> initForPushOnly() async {
    final options = Env.isProd ? prod.DefaultFirebaseOptions.currentPlatform : dev.DefaultFirebaseOptions.currentPlatform;
    await Firebase.initializeApp(options: options);
  }
}
