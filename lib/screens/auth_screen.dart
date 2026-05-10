import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
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
                  ? 'J’ai déjà un compte'
                  : 'Créer un compte avec e-mail'),
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
        await AuthService.createAccountWithEmail(
          email: _email.text,
          password: _password.text,
        );
      } else {
        await AuthService.signInWithEmail(
          email: _email.text,
          password: _password.text,
        );
      }
    } on FirebaseAuthException catch (error) {
      _showError(_friendlyFirebaseError(error));
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
    } on FirebaseAuthException catch (error) {
      _showError(_friendlyFirebaseError(error));
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

  String _friendlyFirebaseError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'Adresse e-mail invalide.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Identifiants incorrects.';
      case 'email-already-in-use':
        return 'Un compte existe déjà avec cet e-mail.';
      case 'weak-password':
        return 'Le mot de passe est trop faible.';
      default:
        return error.message ?? 'Connexion impossible.';
    }
  }
}

class AuthGate extends StatelessWidget {
  final Widget child;
  const AuthGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.primary),
            ),
          );
        }
        if (snapshot.data == null) return const AuthScreen();
        return child;
      },
    );
  }
}
