class LegalConfig {
  // Site statique publie sur Netlify (voir privacy_policy_site/). Les deux
  // pages doivent rester accessibles publiquement : Google Play verifie que
  // l'URL de politique de confidentialite declaree dans la fiche repond.
  static const String privacyPolicyUrl =
      'https://zippy-pithivier-16e4a6.netlify.app/';
  static const String termsOfServiceUrl =
      'https://zippy-pithivier-16e4a6.netlify.app/conditions.html';
  static const String accountDeletionUrl =
      'https://zippy-pithivier-16e4a6.netlify.app/suppression-compte.html';

  static const String supportEmail = 'tayoufabiokamogne@gmail.com';

  // A garder synchronise avec `version:` dans pubspec.yaml.
  static const String appVersion = '1.0.0';
  static const String appName = 'Ultimate Audio Recorder';
}
