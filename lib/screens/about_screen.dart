import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/legal_config.dart';
import '../ui/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.text,
        title: const Text('À propos'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Column(children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.primaryDeep, AppTheme.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.mic_rounded,
                color: AppTheme.onPrimary,
                size: 44,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              LegalConfig.appName,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.text,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Version ${LegalConfig.appVersion}',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
            ),
          ]),
          const SizedBox(height: 26),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: AppTheme.panel(radius: 18),
            child: const Text(
              'Enregistreur audio intelligent : enregistrement manuel ou '
              'programmé, déclenchement par mots-clés, transcription et '
              'résumé assistés par intelligence artificielle.',
              style: TextStyle(
                color: AppTheme.textMuted,
                fontSize: 13.5,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _LinkTile(
            icon: Icons.mail_outline_rounded,
            title: 'Contacter le support',
            subtitle: LegalConfig.supportEmail,
            onTap: () => _open(
              context,
              Uri(
                scheme: 'mailto',
                path: LegalConfig.supportEmail,
                queryParameters: {
                  'subject': '${LegalConfig.appName} - Support',
                },
              ),
            ),
          ),
          _LinkTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Politique de confidentialité',
            subtitle: 'Données traitées et conservation',
            onTap: () =>
                _open(context, Uri.parse(LegalConfig.privacyPolicyUrl)),
          ),
          _LinkTile(
            icon: Icons.description_outlined,
            title: "Conditions d'utilisation",
            subtitle: "Règles d'usage et abonnements",
            onTap: () =>
                _open(context, Uri.parse(LegalConfig.termsOfServiceUrl)),
          ),
          const SizedBox(height: 20),
          const Text(
            'Les abonnements sont gérés par Google Play. Le renouvellement et '
            'la résiliation se font depuis votre compte Google Play.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textMuted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// Ouvre une URL externe et signale l'echec plutot que d'ignorer en silence :
// une page legale injoignable doit etre visible de l'utilisateur.
Future<void> _open(BuildContext context, Uri uri) async {
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

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
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
        trailing: const Icon(
          Icons.open_in_new_rounded,
          color: AppTheme.textMuted,
          size: 18,
        ),
      ),
    );
  }
}
