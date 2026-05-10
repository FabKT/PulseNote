import 'package:flutter/material.dart';
import '../models/schedule_model.dart';
import '../models/keyword_model.dart';
import '../ui/app_theme.dart';

// Carte affichée dans la liste des créneaux planifiés.
class ScheduleCard extends StatelessWidget {
  final ScheduleModel schedule;
  final List<KeywordModel> allKeywords;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const ScheduleCard({
    super.key,
    required this.schedule,
    required this.allKeywords,
    required this.onToggle,
    required this.onDelete,
  });

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  bool get _isNowActive => schedule.isCurrentlyActive();

  Color get _modeColor => schedule.mode == ScheduleMode.autoRecord
      ? const Color(0xFF4A9EDB)
      : const Color(0xFFDB9A4A);

  @override
  Widget build(BuildContext context) {
    final linkedKeywords =
        allKeywords.where((k) => schedule.keywordIds.contains(k.id)).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.panel(
        borderColor: _isNowActive
            ? AppTheme.primary.withValues(alpha: 0.7)
            : AppTheme.line,
        gradient: _isNowActive
            ? [
                AppTheme.primary.withValues(alpha: 0.14),
                AppTheme.surface,
              ]
            : null,
        radius: 18,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              // Plage horaire
              Text(
                '${_fmt(schedule.startTime)} – ${_fmt(schedule.endTime)}',
                style: const TextStyle(
                    color: AppTheme.text,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // Badge mode
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _modeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _modeColor.withValues(alpha: 0.45)),
                ),
                child: Text(
                  schedule.modeLabelShort,
                  style: TextStyle(
                      color: _modeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            // Indicateur "actif maintenant"
            if (_isNowActive)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: AppTheme.primary, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  const Text('Actif maintenant',
                      style: TextStyle(color: AppTheme.primary, fontSize: 11)),
                ]),
              ),
            // Mots-clés associés (mode keywordTrigger)
            if (schedule.mode == ScheduleMode.keywordTrigger &&
                linkedKeywords.isNotEmpty)
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: linkedKeywords
                    .map((k) => Chip(
                          label: Text(k.text,
                              style: const TextStyle(fontSize: 11)),
                          backgroundColor:
                              AppTheme.accent.withValues(alpha: 0.12),
                          side: const BorderSide(
                              color: AppTheme.accent, width: 0.5),
                          padding: EdgeInsets.zero,
                          labelPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            const SizedBox(height: 10),
            Row(children: [
              const Spacer(),
              // Interrupteur activer/désactiver
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: schedule.isActive,
                  onChanged: (_) => onToggle(),
                  activeThumbColor: AppTheme.primary,
                  activeTrackColor: AppTheme.primary.withValues(alpha: 0.28),
                ),
              ),
              // Supprimer
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppTheme.danger, size: 20),
                onPressed: onDelete,
                tooltip: 'Supprimer',
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
