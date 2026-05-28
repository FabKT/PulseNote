import 'package:flutter/material.dart';

import '../ui/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.text,
        title: const Text('Paramètres'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: const [
          _SettingsTile(
            icon: Icons.workspace_premium_rounded,
            title: "Gestion de l'abonnement",
            subtitle: 'Offre Pro, renouvellement et restauration.',
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_rounded,
            title: 'Politique de confidentialité',
            subtitle: 'Données audio, transcription et conservation.',
          ),
          _SettingsTile(
            icon: Icons.description_rounded,
            title: "Conditions d'utilisation",
            subtitle: "Règles d'usage de l'application.",
          ),
          _SettingsTile(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            subtitle: 'Alertes de session et enregistrements planifiés.',
          ),
          _SettingsTile(
            icon: Icons.storage_rounded,
            title: 'Stockage',
            subtitle: 'Gestion locale des audios et exports.',
          ),
          _SettingsTile(
            icon: Icons.info_rounded,
            title: 'À propos',
            subtitle: 'Version, support et informations légales.',
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.panel(radius: 16),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.primary),
        title: Text(title, style: const TextStyle(color: AppTheme.text)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppTheme.textMuted),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }
}
