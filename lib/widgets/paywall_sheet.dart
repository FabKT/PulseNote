import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../models/premium_feature.dart';
import '../models/subscription_tier.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';

Future<void> showPaywall(
  BuildContext context, {
  PremiumFeature? feature,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaywallSheet(feature: feature),
  );
}

class _PaywallSheet extends StatelessWidget {
  final PremiumFeature? feature;
  const _PaywallSheet({this.feature});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: AppTheme.accent, size: 30),
            ),
            const SizedBox(height: 16),
            const Text('Choisissez votre formule',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900)),
            if (feature != null) ...[
              const SizedBox(height: 8),
              Text(feature!.description,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ],
            const SizedBox(height: 20),
            Consumer<AppState>(
              builder: (context, state, _) {
                if (state.purchaseError != null) {
                  return Column(children: [
                    _ErrorBanner(message: state.purchaseError!),
                    const SizedBox(height: 12),
                    _plans(context, state),
                  ]);
                }
                return _plans(context, state);
              },
            ),
            const SizedBox(height: 8),
            Consumer<AppState>(
              builder: (context, state, _) => TextButton(
                onPressed: state.purchasePending
                    ? null
                    : () => state.restorePremiumPurchase(),
                child: const Text('Restaurer mes achats'),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Plus tard'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _plans(BuildContext context, AppState state) {
    return Column(children: [
      if (state.tier == SubscriptionTier.pro) ...[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.30),
            ),
          ),
          child: Text(
            '${state.creditsRemaining} crédits IA disponibles',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      _PlanCard(
        tier: SubscriptionTier.free,
        title: 'Gratuit',
        price: '0€',
        current: state.tier == SubscriptionTier.free,
        highlighted: false,
        features: const [
          'Enregistrements normaux',
          'Créneaux programmés (horaire)',
          'Dossiers',
          'Import audio',
          'MP4 vers MP3',
          '500 Mo de sauvegarde cloud',
        ],
      ),
      const SizedBox(height: 12),
      _PlanCard(
        tier: SubscriptionTier.plus,
        title: 'Plus',
        price: state.priceFor(SubscriptionTier.plus).isEmpty
            ? '2,99€/mois'
            : '${state.priceFor(SubscriptionTier.plus)}/mois',
        current: state.tier == SubscriptionTier.plus,
        highlighted: feature?.requiredTier == SubscriptionTier.plus,
        features: const [
          'Lecture continue',
          'Créneaux programmés (mots-clés)',
          'Lecture planifiée',
        ],
        onBuy: state.tier == SubscriptionTier.plus
            ? null
            : () => state.buyTier(SubscriptionTier.plus),
        loading: state.purchasePending || state.purchaseLoading,
      ),
      const SizedBox(height: 12),
      _PlanCard(
        tier: SubscriptionTier.pro,
        title: 'Pro',
        price: state.priceFor(SubscriptionTier.pro).isEmpty
            ? '9,99€/mois'
            : '${state.priceFor(SubscriptionTier.pro)}/mois',
        current: state.tier == SubscriptionTier.pro,
        highlighted: feature?.requiredTier == SubscriptionTier.pro,
        features: const [
          'Tout Plus, et en plus :',
          'Transcription audio',
          'Résumé IA',
          '1 000 crédits IA renouvelés chaque mois',
        ],
        onBuy: state.tier == SubscriptionTier.pro
            ? null
            : () => state.buyTier(SubscriptionTier.pro),
        loading: state.purchasePending || state.purchaseLoading,
      ),
      if (kDebugMode) ...[
        const SizedBox(height: 12),
        const Divider(color: AppTheme.line, height: 24),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => state.setTier(SubscriptionTier.free),
              child: const Text('Test : Gratuit'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => state.setTier(SubscriptionTier.plus),
              child: const Text('Test : Plus'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => state.setTier(SubscriptionTier.pro),
              child: const Text('Test : Pro'),
            ),
          ),
        ]),
      ],
    ]);
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.28)),
      ),
      child: Text(message,
          style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final SubscriptionTier tier;
  final String title;
  final String price;
  final bool current;
  final bool highlighted;
  final List<String> features;
  final VoidCallback? onBuy;
  final bool loading;

  const _PlanCard({
    required this.tier,
    required this.title,
    required this.price,
    required this.current,
    required this.highlighted,
    required this.features,
    this.onBuy,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isFree = tier == SubscriptionTier.free;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted ? AppTheme.accent : AppTheme.line,
          width: highlighted ? 1.6 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title,
              style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w900)),
          const Spacer(),
          Text(price,
              style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        ...features.map((f) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppTheme.primary, size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(f,
                      style: const TextStyle(
                          color: AppTheme.text, fontSize: 12.5)),
                ),
              ]),
            )),
        if (!isFree) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: current || loading ? null : onBuy,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: const Color(0xFF281604),
              ),
              child: loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(current ? 'Palier actuel' : "S'abonner"),
            ),
          ),
        ] else if (current) ...[
          const SizedBox(height: 8),
          const Text('Palier actuel',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ],
      ]),
    );
  }
}
