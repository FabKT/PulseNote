import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class AuthService {
  AuthService._();

  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static SupabaseClient get _client => Supabase.instance.client;

  static Stream<AuthState> get authStateChanges =>
      _client.auth.onAuthStateChange;
  static User? get currentUser => _client.auth.currentUser;

  static Future<void> initializeSupabase() async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
  }

  static Future<void> initializeGoogleSignIn() async {
    await _googleSignIn.initialize(
      serverClientId: SupabaseConfig.googleWebClientId.isEmpty
          ? null
          : SupabaseConfig.googleWebClientId,
    );
  }

  static Future<String?> idToken() async {
    var session = _client.auth.currentSession;
    // Au retour d'arriere-plan, le rafraichissement automatique peut ne pas
    // encore avoir tourne : un jeton echu serait refuse par le backend.
    if (session != null && session.isExpired) {
      try {
        session = (await _client.auth.refreshSession()).session;
      } catch (_) {
        return null;
      }
    }
    return session?.accessToken;
  }

  static Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  // Lien qui rouvre l'app depuis un email Supabase (confirmation
  // d'inscription, reinitialisation du mot de passe). supabase_flutter le
  // traite seul (detectSessionInUri). A declarer dans Supabase >
  // Authentication > URL Configuration > Redirect URLs, et dans le filtre
  // d'intent de AndroidManifest.xml.
  static const String authCallbackUrl =
      'com.fabkt.ultimateaudiorecorder://login-callback/';

  static Future<AuthResponse> createAccountWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: authCallbackUrl,
    );
  }

  static Future<void> sendPasswordReset(String email) {
    return _client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: authCallbackUrl,
    );
  }

  static Future<void> updatePassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
  }

  static Future<AuthResponse> signInWithGoogle() async {
    final account = await _googleSignIn.authenticate();
    final auth = account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      throw const AuthException('Connexion Google impossible (idToken manquant).');
    }
    return _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
  }

  static Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _client.auth.signOut();
  }
}
