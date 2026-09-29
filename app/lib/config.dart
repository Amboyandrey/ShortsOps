/// Build-time configuration; pass with --dart-define-from-file=env.json (see README).
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  /// Web OAuth client ID from the Google Cloud project that owns the YouTube API; Android sign-in needs it.
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  static bool get isComplete => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;
}
