class SupabaseConfig {
  static const _urlFromBuild = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const _anonKeyFromBuild = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );
  static const _googleWebClientIdFromBuild = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  static String get url => _urlFromBuild.trim();
  static String get anonKey => _anonKeyFromBuild.trim();
  static String get googleWebClientId => _googleWebClientIdFromBuild.trim();

  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty;
}
