import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../models/premium_feature.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';

Future<void> showPaywall(
  BuildContext context, {
  required PremiumFeature feature,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaywallSheet(feature: feature),
  );
}

class _PaywallSheet extends StatelessWidget {
  final PremiumFeature feature;
  const _PaywallSheet({required this.feature});

  @override
  Widget build(BuildContext context) {
    final features = [
      PremiumFeature.recordingTranscription,
      PremiumFeature.aiSummary,
      PremiumFeature.keywordTrigger,
      PremiumFeature.advancedSearch,
      PremiumFeature.advancedExports,
      PremiumFeature.unlimitedHistory,
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
      child: SafeArea(
        top: false,
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
          const Text('Passez à Ultimate Premium',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 22,
                  fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(feature.description,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.line),
            ),
            child: Column(
              children: features
                  .map((item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 7),
                        child: Row(children: [
                          Icon(
                            item == feature
                                ? Icons.lock_open_rounded
                                : Icons.check_circle_rounded,
                            color: item == feature
                                ? AppTheme.accent
                                : AppTheme.primary,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(item.title,
                                style: const TextStyle(
                                    color: AppTheme.text,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ]),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 18),
          Consumer<AppState>(
            builder: (context, state, _) {
              final price = state.premiumPrice;
              final canBuy = state.purchaseAvailable &&
                  !state.purchaseLoading &&
                  !state.purchasePending &&
                  price.isNotEmpty;

              return Column(children: [
                if (state.purchaseError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppTheme.danger.withValues(alpha: 0.28)),
                    ),
                    child: Text(state.purchaseError!,
                        style: const TextStyle(
                            color: AppTheme.danger, fontSize: 12)),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: canBuy
                        ? () async {
                            await state.buyPremium();
                          }
                        : null,
                    icon: state.purchasePending || state.purchaseLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.workspace_premium_rounded),
                    label: Text(price.isEmpty
                        ? 'Achat Premium indisponible'
                        : "S'abonner - $price"),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: const Color(0xFF281604),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: state.purchasePending
                      ? null
                      : () => state.restorePremiumPurchase(),
                  child: const Text('Restaurer mon achat'),
                ),
                if (kDebugMode) ...[
                  const Divider(color: AppTheme.line, height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await state.setPremiumEnabled(true);
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.bolt_rounded),
                      label: const Text('Mode test : activer Premium'),
                    ),
                  ),
                ],
              ]);
            },
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Plus tard'),
          ),
        ]),
      ),
    );
  }
}
