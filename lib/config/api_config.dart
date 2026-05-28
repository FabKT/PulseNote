class ApiConfig {
  static const _backendBaseUrlFromBuild = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: '',
  );
  static const _appClientTokenFromBuild = String.fromEnvironment(
    'APP_CLIENT_TOKEN',
    defaultValue: '',
  );

  static String get backendBaseUrl {
    final clean = _backendBaseUrlFromBuild.trim();
    final parsed = Uri.tryParse(clean);
    if (parsed == null || parsed.scheme.isEmpty || parsed.host.isEmpty) {
      return '';
    }
    return clean.replaceAll(RegExp(r'/+$'), '');
  }

  static String get appClientToken {
    final clean = _appClientTokenFromBuild.trim();
    return clean;
  }

  static bool get isConfigured => backendBaseUrl.isNotEmpty;
}
