import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (_, state, __) {
        final user = AuthService.currentUser;
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
                    backgroundImage: user?.photoURL == null
                        ? null
                        : NetworkImage(user!.photoURL!),
                    child: user?.photoURL == null
                        ? const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF04211F),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName?.trim().isNotEmpty == true
                              ? user!.displayName!
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
            ],
          ),
        );
      },
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
