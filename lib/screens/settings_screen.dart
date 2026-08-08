import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/legal_config.dart';
import '../ui/app_theme.dart';
import '../widgets/paywall_sheet.dart';
import 'about_screen.dart';
import 'notifications_screen.dart';
import 'storage_screen.dart';

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
        children: [
          _SettingsTile(
            icon: Icons.workspace_premium_rounded,
            title: "Gestion de l'abonnement",
            subtitle: 'Offres Plus et Pro, renouvellement et restauration.',
            onTap: () => showPaywall(context),
          ),
          _SettingsTile(
            icon: Icons.notifications_rounded,
            title: 'Notifications',
            subtitle: 'Autorisations micro, notifications et arrière-plan.',
            onTap: () => _push(context, const NotificationsScreen()),
          ),
          _SettingsTile(
            icon: Icons.storage_rounded,
            title: 'Stockage',
            subtitle: 'Espace occupé et quota de sauvegarde cloud.',
            onTap: () => _push(context, const StorageScreen()),
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_rounded,
            title: 'Politique de confidentialité',
            subtitle: 'Données audio, transcription et conservation.',
            external: true,
            onTap: () =>
                _openUrl(context, Uri.parse(LegalConfig.privacyPolicyUrl)),
          ),
          _SettingsTile(
            icon: Icons.description_rounded,
            title: "Conditions d'utilisation",
            subtitle: "Règles d'usage de l'application.",
            external: true,
            onTap: () =>
                _openUrl(context, Uri.parse(LegalConfig.termsOfServiceUrl)),
          ),
          _SettingsTile(
            icon: Icons.info_rounded,
            title: 'À propos',
            subtitle: 'Version, support et informations légales.',
            onTap: () => _push(context, const AboutScreen()),
          ),
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _openUrl(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text('Impossible d\'ouvrir : $uri')),
      );
    }
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool external;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.external = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.panel(radius: 16),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppTheme.primary),
        title: Text(title, style: const TextStyle(color: AppTheme.text)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: AppTheme.textMuted),
        ),
        trailing: Icon(
          external ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
          color: AppTheme.textMuted,
          size: external ? 18 : 24,
        ),
      ),
    );
  }
}
