/// Build-time settings, passed with `--dart-define`.
///
/// ```
/// flutter run                                              # demo backend (in-app demo data)
/// flutter run --flavor dev --dart-define=BACKEND=supabase  # Supabase asani-dev (D-52)
/// ```
abstract final class Env {
  /// dev | prod (docs/02 §4).
  static const String env = String.fromEnvironment('ENV', defaultValue: 'dev');

  /// demo = in-app demo data (D-11); supabase = Supabase (D-52).
  static const String backend = String.fromEnvironment('BACKEND', defaultValue: 'demo');

  /// Supabase project (D-52). Both values are public (the anon / publishable key is safe in the app;
  /// Row Level Security protects the data). Defaults = the asani-dev project.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://lgnbxxcmogbbzmuqyrgu.supabase.co');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_Hgin4aABXeUBXqu02QODMg_81Loge4G');

  static bool get isProd => env == 'prod';
  static bool get useSupabase => backend == 'supabase';
  static bool get isDemo => !useSupabase;
}
