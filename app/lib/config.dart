/// Build-time configuration; pass with --dart-define-from-file=env.json (see README).
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isComplete => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
