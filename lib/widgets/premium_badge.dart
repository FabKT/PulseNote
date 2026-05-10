import 'package:flutter/material.dart';
import '../ui/app_theme.dart';

class PremiumBadge extends StatelessWidget {
  final String label;
  const PremiumBadge({super.key, this.label = 'Premium'});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.42)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.workspace_premium_rounded,
            size: 13, color: AppTheme.accent),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 10,
                fontWeight: FontWeight.w800)),
      ]),
    );
  }
}
