import 'package:flutter/material.dart';

import '../app.dart';
import '../ui/app_theme.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = MenuNavigationScope.of(context);
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
          children: [
            _HeroTile(
              title: 'Abonnez-vous Pro',
              icon: Icons.workspace_premium_rounded,
              colors: const [Color(0xFF20B8FF), Color(0xFF57D9F6)],
              onTap: () {},
            ),
            const SizedBox(height: 18),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 18,
              mainAxisSpacing: 18,
              childAspectRatio: 1.18,
              children: [
                _MenuTile(
                  icon: Icons.library_music_rounded,
                  title: 'Enregistrements',
                  onTap: nav.openRecordings,
                ),
                _MenuTile(
                  icon: Icons.record_voice_over_rounded,
                  title: 'Mots-clés',
                  onTap: nav.openKeywords,
                ),
                _MenuTile(
                  icon: Icons.text_fields_rounded,
                  title: 'Transcription\ninstantanée',
                  onTap: nav.openInstantTranscription,
                ),
                _MenuTile(
                  icon: Icons.folder_special_rounded,
                  title: 'Dossiers',
                  onTap: nav.openFolders,
                ),
                _MenuTile(
                  icon: Icons.person_rounded,
                  title: 'Profil',
                  onTap: nav.openProfile,
                ),
                _MenuTile(
                  icon: Icons.settings_rounded,
                  title: 'Paramètres',
                  onTap: nav.openSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Color> colors;
  final VoidCallback onTap;
  const _HeroTile({
    required this.title,
    required this.icon,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 146,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Stack(children: [
          Positioned(
            right: -12,
            top: -18,
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.26),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
          Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.line.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.text, size: 34),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 16,
                height: 1.08,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
