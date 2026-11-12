/// Build-time settings, passed with `--dart-define`.
///
/// ```
/// flutter run                                              # demo backend (no Firebase)
/// flutter run --flavor dev --dart-define=BACKEND=firebase  # Firebase asani-dev
/// flutter run --flavor dev --dart-define=BACKEND=firebase --dart-define=USE_EMULATOR=true
/// ```
abstract final class Env {
  /// dev | prod (docs/02 §4).
  static const String env = String.fromEnvironment('ENV', defaultValue: 'dev');

  /// demo = in-app demo data (D-11); firebase = Firebase Auth + Firestore.
  static const String backend = String.fromEnvironment('BACKEND', defaultValue: 'demo');

  static const bool useEmulator = bool.fromEnvironment('USE_EMULATOR', defaultValue: false);

  /// Only Cloud Functions on the local emulator; Auth and Firestore stay on the
  /// real dev project. Used until the project is on the Blaze plan.
  static const bool useFunctionsEmulator = bool.fromEnvironment('USE_FUNCTIONS_EMULATOR', defaultValue: false);

  /// Physical phone: your PC's Wi-Fi IP, e.g. 192.168.1.5.
  /// Empty = 10.0.2.2 on the Android emulator, localhost elsewhere.
  static const String emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '');

  /// Dev testing only: skips reCAPTCHA / app checks so Firebase *test* phone
  /// numbers log in instantly. Real numbers do not work in this mode.
  /// Ignored in prod.
  static const bool authTestMode = bool.fromEnvironment('AUTH_TEST_MODE', defaultValue: false);

  static bool get isProd => env == 'prod';
  static bool get useFirebase => backend == 'firebase';
  static bool get isDemo => !useFirebase;
}
