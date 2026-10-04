class ApiConfig {
  static const _backendBaseUrlFromBuild = String.fromEnvironment(
    'BACKEND_BASE_URL',
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

  static bool get isConfigured => backendBaseUrl.isNotEmpty;
}
