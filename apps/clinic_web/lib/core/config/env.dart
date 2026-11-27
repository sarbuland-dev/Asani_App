/// Build-time settings (`--dart-define`):
///
/// ```
/// flutter run -d chrome                                                   # demo backend (in-memory)
/// flutter run -d chrome --web-port 8092 --dart-define=BACKEND=supabase    # Supabase asani-dev (D-52)
/// ```
abstract final class Env {
  static const String backend = String.fromEnvironment('BACKEND', defaultValue: 'demo');
  static const String env = String.fromEnvironment('ENV', defaultValue: 'dev');

  static bool get useSupabase => backend == 'supabase';
  static bool get isProd => env == 'prod';

  /// Supabase project (D-52). Public values (RLS protects the data). Defaults = asani-dev.
  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://lgnbxxcmogbbzmuqyrgu.supabase.co');
  static const String supabaseKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'sb_publishable_Hgin4aABXeUBXqu02QODMg_81Loge4G');
}
