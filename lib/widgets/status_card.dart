import 'package:flutter/material.dart';
import '../models/schedule_model.dart';
import '../state/app_state.dart';
import '../services/schedule_service.dart';
import '../ui/app_theme.dart';

// Grande carte de statut affiché en haut de l'écran d'accueil.
class StatusCard extends StatelessWidget {
  final AppStatus status;
  final List<ScheduleModel> schedules;

  const StatusCard({super.key, required this.status, required this.schedules});

  @override
  Widget build(BuildContext context) {
    final cfg = _config(status);
    final next = ScheduleService().findNextSchedule(schedules);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cfg.color.withValues(alpha: 0.26),
            AppTheme.surface,
            AppTheme.background,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border:
            Border.all(color: cfg.color.withValues(alpha: 0.45), width: 1.3),
        boxShadow: [
          BoxShadow(
            color: cfg.color.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            // Indicateur animé
            _PulseDot(color: cfg.color, animate: status != AppStatus.idle),
            const SizedBox(width: 10),
            Text(cfg.label,
                style: TextStyle(
                    color: cfg.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            const Spacer(),
            Icon(cfg.icon, color: cfg.color, size: 20),
          ]),
          const SizedBox(height: 8),
          Text(cfg.description,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          if (next != null && status == AppStatus.idle) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.schedule, size: 13, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                'Prochain : ${_fmt(next.startTime)} — ${next.modeLabel}',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  ({String label, String description, Color color, IconData icon}) _config(
          AppStatus s) =>
      switch (s) {
        AppStatus.idle => (
            label: 'Inactif',
            description:
                'Démarrez une session pour activer l\'écoute et la planification.',
            color: AppTheme.textMuted,
            icon: Icons.power_settings_new,
          ),
        AppStatus.sessionActive => (
            label: 'Session active',
            description:
                'En attente d\'un créneau planifié ou d\'un déclenchement manuel.',
            color: AppTheme.primary,
            icon: Icons.radio_button_checked,
          ),
        AppStatus.listening => (
            label: 'En écoute...',
            description:
                'Surveillance active — un mot-clé déclenchera l\'enregistrement.',
            color: AppTheme.accent,
            icon: Icons.hearing,
          ),
        AppStatus.recording => (
            label: 'Enregistrement en cours',
            description: 'Audio en cours de capture et de sauvegarde.',
            color: AppTheme.danger,
            icon: Icons.fiber_manual_record,
          ),
      };
}

// Point pulsant pour les états actifs
class _PulseDot extends StatefulWidget {
  final Color color;
  final bool animate;
  const _PulseDot({required this.color, required this.animate});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.5, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: widget.color, shape: BoxShape.circle));
    }
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: _anim.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
