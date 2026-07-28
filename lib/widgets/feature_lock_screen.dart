import 'package:flutter/material.dart';

import '../models/premium_feature.dart';
import '../ui/app_theme.dart';
import 'paywall_sheet.dart';

// Écran plein-cadre affiché à la place d'une fonctionnalité verrouillée par
// palier d'abonnement (lecture continue, import audio, MP4 vers MP3,
// lecture planifiée...). Mêmes visuels que PremiumLockedStatePlaceholder /
// PremiumLockedScheduleStatePlaceholder, réutilisable pour les écrans
// entiers plutôt qu'un seul état interne.
class FeatureLockScreen extends StatelessWidget {
  final PremiumFeature feature;
  final String title;
  const FeatureLockScreen({
    super.key,
    required this.feature,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.text,
        title: Text(title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded,
                  color: AppTheme.accent, size: 34),
            ),
            const SizedBox(height: 18),
            Text(feature.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(feature.description,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => showPaywall(context, feature: feature),
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text('Voir les formules'),
            ),
          ]),
        ),
      ),
    );
  }
}
