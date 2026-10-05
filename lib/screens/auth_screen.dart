import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _createAccount = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 34, 24, 24),
          children: [
            const SizedBox(height: 36),
            const Icon(
              Icons.graphic_eq_rounded,
              color: AppTheme.primary,
              size: 54,
            ),
            const SizedBox(height: 18),
            const Text(
              'Ultimate Audio Recorder',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.text,
                fontSize: 31,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Connectez-vous pour synchroniser les fonctions IA.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 34),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              style: const TextStyle(color: AppTheme.text),
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Icons.mail_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              style: const TextStyle(color: AppTheme.text),
              decoration: const InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _loading ? null : _submitEmail,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _createAccount ? 'Créer mon compte' : 'Me connecter'),
              ),
            ),
            TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() => _createAccount = !_createAccount),
              child: Text(_createAccount
                  ? "J'ai déjà un compte"
                  : 'Créer un compte avec e-mail'),
            ),
            if (!_createAccount)
              TextButton(
                onPressed: _loading ? null : _sendPasswordReset,
                child: const Text('Mot de passe oublié ?'),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loading ? null : _submitGoogle,
              icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
              label: const Text('Continuer avec Google'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                foregroundColor: AppTheme.text,
                side: const BorderSide(color: AppTheme.primaryDeep),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitEmail() async {
    setState(() => _loading = true);
    try {
      if (_createAccount) {
        final response = await AuthService.createAccountWithEmail(
          email: _email.text,
          password: _password.text,
        );
        // Confirmation d'email activee : pas de session tant que le lien
        // recu par email n'a pas ete ouvert.
        if (response.session == null) {
          if (mounted) setState(() => _createAccount = false);
          _showError(
            'Compte créé. Ouvrez le lien reçu par e-mail sur ce téléphone '
            'pour confirmer votre adresse, puis connectez-vous.',
          );
          return;
        }
      } else {
        await AuthService.signInWithEmail(
          email: _email.text,
          password: _password.text,
        );
      }
      if (mounted && AuthService.currentUser != null) {
        await context.read<AppState>().refreshEntitlement();
      }
    } on AuthException catch (error) {
      _showError(_friendlySupabaseError(error));
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      _showError('Saisissez d’abord votre adresse e-mail.');
      return;
    }
    setState(() => _loading = true);
    try {
      await AuthService.sendPasswordReset(email);
      _showError(
        'Si un compte existe pour $email, un lien de réinitialisation vient '
        'd’être envoyé. Ouvrez-le sur ce téléphone.',
      );
    } on AuthException catch (error) {
      _showError(_friendlySupabaseError(error));
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() => _loading = true);
    try {
      await AuthService.signInWithGoogle();
      if (mounted) await context.read<AppState>().refreshEntitlement();
    } on AuthException catch (error) {
      _showError(_friendlySupabaseError(error));
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _friendlySupabaseError(AuthException error) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'Identifiants incorrects.';
      case 'user_already_exists':
      case 'email_exists':
        return 'Un compte existe déjà avec cet e-mail.';
      case 'weak_password':
        return 'Le mot de passe est trop faible.';
      case 'email_not_confirmed':
        return 'Confirmez d’abord votre adresse avec le lien reçu par e-mail.';
      case 'over_email_send_rate_limit':
        return 'Trop d’e-mails envoyés. Réessayez dans quelques minutes.';
      case 'email_address_invalid':
      case 'validation_failed':
        return 'Adresse e-mail invalide.';
      default:
        return error.message;
    }
  }
}

class AuthGate extends StatelessWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isConfigured) return child;
    return StreamBuilder<AuthState>(
      stream: AuthService.authStateChanges,
      initialData: AuthState(
        AuthChangeEvent.initialSession,
        Supabase.instance.client.auth.currentSession,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          );
        }
        if (snapshot.data?.session?.user == null) return const AuthScreen();
        // Lien "mot de passe oublie" ouvert : session temporaire, on impose
        // le choix d'un nouveau mot de passe avant d'entrer dans l'app.
        if (snapshot.data?.event == AuthChangeEvent.passwordRecovery) {
          return const PasswordRecoveryScreen();
        }
        return child;
      },
    );
  }
}

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 70, 24, 24),
          children: [
            const Icon(
              Icons.lock_reset_rounded,
              color: AppTheme.primary,
              size: 54,
            ),
            const SizedBox(height: 18),
            const Text(
              'Nouveau mot de passe',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.text,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 30),
            TextField(
              controller: _password,
              obscureText: true,
              style: const TextStyle(color: AppTheme.text),
              decoration: const InputDecoration(
                labelText: 'Nouveau mot de passe',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmation,
              obscureText: true,
              style: const TextStyle(color: AppTheme.text),
              decoration: const InputDecoration(
                labelText: 'Confirmer le mot de passe',
                prefixIcon: Icon(Icons.lock_outline_rounded),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enregistrer'),
              ),
            ),
            TextButton(
              onPressed: _loading ? null : AuthService.signOut,
              child: const Text('Annuler'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_password.text.length < 6) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Le mot de passe doit contenir au moins 6 caractères.'),
      ));
      return;
    }
    if (_password.text != _confirmation.text) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Les deux mots de passe ne correspondent pas.'),
      ));
      return;
    }
    setState(() => _loading = true);
    try {
      // Declenche l'evenement userUpdated : AuthGate affiche alors l'app.
      await AuthService.updatePassword(_password.text);
      messenger.showSnackBar(
        const SnackBar(content: Text('Mot de passe mis à jour.')),
      );
    } on AuthException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
