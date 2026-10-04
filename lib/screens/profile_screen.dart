import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../services/account_service.dart';
import '../services/friends_service.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (_, state, __) {
        final user = AuthService.currentUser;
        final metadata = user?.userMetadata ?? const {};
        final photoUrl =
            (metadata['avatar_url'] ?? metadata['picture']) as String?;
        final displayName =
            (metadata['full_name'] ?? metadata['name']) as String?;
        final favorites = state.recordings.where((r) => r.isFavorite).length;
        final transcribed =
            state.recordings.where((r) => r.transcription != null).length;
        final summarized =
            state.recordings.where((r) => r.summary != null).length;

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: AppTheme.background,
            foregroundColor: AppTheme.text,
            title: const Text('Profil'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: AppTheme.panel(radius: 18),
                child: Row(children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppTheme.primary,
                    backgroundImage:
                        photoUrl == null ? null : NetworkImage(photoUrl),
                    child: photoUrl == null
                        ? const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF241A02),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName?.trim().isNotEmpty == true
                              ? displayName!
                              : 'Utilisateur Ultimate Audio Recorder',
                          style: const TextStyle(
                            color: AppTheme.text,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          user?.email ?? 'Espace personnel',
                          style: const TextStyle(color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              const _UsernameTile(),
              const SizedBox(height: 18),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _StatTile('Enregistrements', state.recordings.length),
                  _StatTile('Dossiers', state.folders.length),
                  _StatTile('Favoris', favorites),
                  _StatTile('Transcrits', transcribed),
                  _StatTile('Résumés', summarized),
                  _StatTile('Créneaux', state.schedules.length),
                ],
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: AuthService.signOut,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Se déconnecter'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _confirmAccountDeletion(context, state),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.danger,
                  side: const BorderSide(color: AppTheme.danger),
                ),
                icon: const Icon(Icons.delete_forever_rounded),
                label: const Text('Supprimer mon compte'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmAccountDeletion(
    BuildContext context,
    AppState state,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer définitivement le compte ?'),
        content: const Text(
          'Le compte, les données synchronisées et les fichiers audio cloud '
          'seront supprimés. Cette action est irréversible. Les abonnements '
          'Google Play doivent être résiliés séparément dans Google Play.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await AccountService.deleteAccount();
      await state.clearLocalAccountData();
      await AuthService.signOut();
      messenger.showSnackBar(
        const SnackBar(content: Text('Votre compte a été supprimé.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }
}

class _UsernameTile extends StatefulWidget {
  const _UsernameTile();

  @override
  State<_UsernameTile> createState() => _UsernameTileState();
}

class _UsernameTileState extends State<_UsernameTile> {
  String? _username;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await FriendsService.myProfile();
      if (mounted) {
        setState(() {
          _username = profile.username;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _UsernameDialog(initialValue: _username ?? ''),
    );
    if (value == null || !mounted) return;
    try {
      final profile = await FriendsService.updateUsername(value);
      if (!mounted) return;
      setState(() => _username = profile.username);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nom d’utilisateur mis à jour.')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().contains('username_taken') ||
              error.toString().contains('duplicate key')
          ? 'Ce nom d’utilisateur est déjà utilisé.'
          : 'Impossible de modifier le nom d’utilisateur.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.panel(radius: 14),
      child: ListTile(
        leading: const Icon(Icons.alternate_email_rounded),
        title: const Text(
          'Nom d’utilisateur',
          style: TextStyle(
            color: AppTheme.text,
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(
          _loading
              ? 'Chargement…'
              : _username?.isNotEmpty == true
                  ? '@$_username'
                  : 'À configurer',
        ),
        trailing: IconButton(
          tooltip: 'Modifier',
          onPressed: _loading ? null : _edit,
          icon: const Icon(Icons.edit_rounded),
        ),
      ),
    );
  }
}

class _UsernameDialog extends StatefulWidget {
  final String initialValue;

  const _UsernameDialog({required this.initialValue});

  @override
  State<_UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<_UsernameDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim().toLowerCase().replaceFirst('@', '');
    if (!RegExp(r'^[a-z0-9._]{3,24}$').hasMatch(value)) {
      setState(() =>
          _error = 'Utilisez 3 à 24 lettres, chiffres, points ou tirets bas.');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Choisir un nom d’utilisateur'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        autocorrect: false,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          prefixText: '@',
          hintText: 'mon_pseudo',
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  const _StatTile(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.panel(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: AppTheme.primary,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
