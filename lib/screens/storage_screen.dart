import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/subscription_tier.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';
import '../widgets/paywall_sheet.dart';

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 Mo';
  const units = ['o', 'Ko', 'Mo', 'Go'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)} ${units[unit]}';
}

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  int? _localBytes;
  int _missingFiles = 0;

  @override
  void initState() {
    super.initState();
    _measureLocalUsage();
  }

  // La taille locale est mesuree sur le disque plutot que lue depuis les
  // metadonnees : les enregistrements crees avant l'ajout du champ `sizeBytes`
  // n'en ont pas, et un fichier peut avoir ete supprime hors de l'app.
  Future<void> _measureLocalUsage() async {
    final recordings = context.read<AppState>().recordings;
    var total = 0;
    var missing = 0;
    for (final recording in recordings) {
      try {
        final file = File(recording.filePath);
        if (await file.exists()) {
          total += await file.length();
        } else {
          missing++;
        }
      } catch (_) {
        missing++;
      }
    }
    if (!mounted) return;
    setState(() {
      _localBytes = total;
      _missingFiles = missing;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.text,
        title: const Text('Stockage'),
      ),
      body: Consumer<AppState>(
        builder: (context, state, _) {
          final isFree = state.tier == SubscriptionTier.free;
          final used = state.cloudUsedBytes;
          final quota = state.freeStorageQuotaBytes;
          final ratio = quota <= 0 ? 0.0 : (used / quota).clamp(0.0, 1.0);
          final pending = state.overQuotaRecordings;

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              // ── Sauvegarde cloud ─────────────────────────────────
              Container(
                padding: const EdgeInsets.all(18),
                decoration: AppTheme.panel(radius: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.cloud_rounded,
                          color: AppTheme.primary, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Sauvegarde cloud',
                          style: TextStyle(
                            color: AppTheme.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        state.tier.label,
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    if (isFree) ...[
                      Text(
                        '${formatBytes(used)} utilisés sur ${formatBytes(quota)}',
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 8,
                          backgroundColor: AppTheme.surfaceHigh,
                          valueColor: AlwaysStoppedAnimation(
                            ratio >= 1 ? AppTheme.danger : AppTheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Au-delà du quota, les nouveaux enregistrements '
                        'restent uniquement sur cet appareil et sont '
                        'supprimés après 3 jours s\'ils ne sont pas exportés.',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        onPressed: () => showPaywall(context),
                        icon: const Icon(Icons.workspace_premium_rounded,
                            size: 18),
                        label: const Text('Sauvegarde illimitée'),
                      ),
                    ] else ...[
                      Text(
                        '${formatBytes(used)} sauvegardés',
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Votre palier ne comporte aucune limite de sauvegarde '
                        'cloud.',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Enregistrements en attente d'export ──────────────
              if (pending.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.danger.withValues(alpha: 0.32),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.schedule_rounded,
                            color: AppTheme.danger, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            pending.length == 1
                                ? '1 enregistrement à sauvegarder'
                                : '${pending.length} enregistrements à sauvegarder',
                            style: const TextStyle(
                              color: AppTheme.danger,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      ...pending.take(5).map((recording) {
                        final deadline = recording.overQuotaDeadline;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                recording.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.text,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              deadline == null
                                  ? ''
                                  : DateFormat('dd/MM à HH:mm')
                                      .format(deadline),
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 11.5,
                              ),
                            ),
                          ]),
                        );
                      }),
                      if (pending.length > 5)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '+ ${pending.length - 5} autre(s)',
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],

              // ── Stockage local ───────────────────────────────────
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: AppTheme.panel(radius: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.smartphone_rounded,
                          color: AppTheme.primary, size: 20),
                      SizedBox(width: 10),
                      Text(
                        'Sur cet appareil',
                        style: TextStyle(
                          color: AppTheme.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    _StatRow(
                      label: 'Espace occupé',
                      value: _localBytes == null
                          ? 'Calcul…'
                          : formatBytes(_localBytes!),
                    ),
                    _StatRow(
                      label: 'Enregistrements',
                      value: '${state.recordings.length}',
                    ),
                    _StatRow(
                      label: 'Dossiers',
                      value: '${state.folders.length}',
                    ),
                    if (_missingFiles > 0)
                      _StatRow(
                        label: 'Fichiers introuvables',
                        value: '$_missingFiles',
                        highlight: true,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Les enregistrements se suppriment un par un depuis l\'écran '
                'Enregistrements. Supprimer un enregistrement le retire aussi '
                'de la sauvegarde cloud.',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _StatRow({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: highlight ? AppTheme.danger : AppTheme.text,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ]),
    );
  }
}
