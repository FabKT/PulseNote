import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/schedule_model.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';
import '../widgets/schedule_card.dart';
import '../widgets/custom_time_picker.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              tabs: _tabs,
              onCreate: () => _showCreateDialog(context),
            ),
            Expanded(
              child: Consumer<AppState>(
                builder: (_, state, __) {
                  final mode = _tabs.index == 0
                      ? ScheduleMode.autoRecord
                      : ScheduleMode.keywordTrigger;
                  final filtered =
                      state.schedules.where((s) => s.mode == mode).toList();

                  if (filtered.isEmpty) {
                    return _EmptyState(mode: mode);
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) => ScheduleCard(
                      schedule: filtered[i],
                      allKeywords: state.keywords,
                      onToggle: () => state.toggleSchedule(filtered[i].id),
                      onDelete: () =>
                          _confirmDelete(ctx, state, filtered[i].id),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, AppState state, String id) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Supprimer ce créneau ?',
            style: TextStyle(color: AppTheme.text)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              state.removeSchedule(id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext ctx) async {
    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateScheduleSheet(
          initialMode: _tabs.index == 0
              ? ScheduleMode.autoRecord
              : ScheduleMode.keywordTrigger),
    );
  }
}

// ─── En-tête avec tabs ────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final TabController tabs;
  final VoidCallback onCreate;
  const _Header({required this.tabs, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('Planification',
                style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 28,
                    fontWeight: FontWeight.bold)),
          ),
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_alarm),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: const Color(0xFF04211F),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            label: const Text('Ajouter'),
          ),
        ]),
        const SizedBox(height: 4),
        const Text('Gérez vos créneaux d\'enregistrement',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
          ),
          child: TabBar(
            controller: tabs,
            indicator: BoxDecoration(
              color: AppTheme.primaryDeep,
              borderRadius: BorderRadius.circular(12),
            ),
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: AppTheme.text,
            unselectedLabelColor: AppTheme.textMuted,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            tabs: const [
              Tab(text: 'Enregistrement auto'),
              Tab(text: 'Déclenchement mot-clé'),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}

// ─── État vide ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final ScheduleMode mode;
  const _EmptyState({required this.mode});

  @override
  Widget build(BuildContext context) {
    final isAuto = mode == ScheduleMode.autoRecord;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
            isAuto ? Icons.play_circle_outline : Icons.hearing_outlined,
            size: 64,
            color: AppTheme.primary.withValues(alpha: 0.16),
          ),
          const SizedBox(height: 16),
          Text(
            isAuto
                ? 'Aucun enregistrement automatique'
                : 'Aucun déclenchement par mot-clé',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isAuto
                ? 'L\'app démarre l\'enregistrement automatiquement dans la plage horaire.'
                : 'L\'app écoute vos mots-clés et enregistre dès qu\'un est détecté.',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ]),
      ),
    );
  }
}

// ─── Bottom sheet de création d'un créneau ────────────────────────────────────

class PremiumLockedScheduleStatePlaceholder extends StatelessWidget {
  final VoidCallback onUpgrade;
  const PremiumLockedScheduleStatePlaceholder({
    super.key,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock_rounded,
              size: 58, color: AppTheme.accent.withValues(alpha: 0.82)),
          const SizedBox(height: 16),
          const Text('Planification par mot-clé',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Créez des sessions qui écoutent un mot-clé et déclenchent l’enregistrement automatiquement.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onUpgrade,
            icon: const Icon(Icons.workspace_premium_rounded),
            label: const Text('Voir Premium'),
          ),
        ]),
      ),
    );
  }
}

class _CreateScheduleSheet extends StatefulWidget {
  final ScheduleMode initialMode;
  const _CreateScheduleSheet({required this.initialMode});

  @override
  State<_CreateScheduleSheet> createState() => _CreateScheduleSheetState();
}

class _CreateScheduleSheetState extends State<_CreateScheduleSheet> {
  late ScheduleMode _mode;
  TimeOfDay _start = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 22, minute: 0);
  final Set<String> _selectedKeywordIds = {};

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final result = await CustomTimePicker.show(context,
        initialStart: _start, initialEnd: _end);
    if (result != null) {
      setState(() {
        _start = result.start;
        _end = result.end;
      });
    }
  }

  void _save(AppState state) {
    if (_mode == ScheduleMode.keywordTrigger && state.keywords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Ajoutez au moins un mot-clé avant de créer ce type de créneau.')));
      return;
    }
    if (_mode == ScheduleMode.keywordTrigger && _selectedKeywordIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Sélectionnez au moins un mot-clé enregistré pour ce créneau.')));
      return;
    }
    state.addSchedule(ScheduleModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      startTime: _start,
      endTime: _end,
      mode: _mode,
      keywordIds: _selectedKeywordIds.toList(),
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppTheme.line,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          const Text('Nouveau créneau',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),

          // Sélection du mode
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Mode',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _ModeButton(
              label: 'Enregistrement\nauto',
              icon: Icons.play_circle_outline,
              color: const Color(0xFF4A9EDB),
              selected: _mode == ScheduleMode.autoRecord,
              onTap: () => setState(() => _mode = ScheduleMode.autoRecord),
            )),
            const SizedBox(width: 10),
            Expanded(
                child: _ModeButton(
              label: 'Déclenchement\nmot-clé',
              icon: Icons.hearing_outlined,
              color: const Color(0xFFDB9A4A),
              selected: _mode == ScheduleMode.keywordTrigger,
              onTap: () => setState(() => _mode = ScheduleMode.keywordTrigger),
            )),
          ]),
          const SizedBox(height: 8),
          Text(
            _mode == ScheduleMode.autoRecord
                ? 'L\'app démarre l\'enregistrement automatiquement à l\'heure définie.'
                : 'L\'app écoute vos mots-clés et enregistre dès qu\'un est détecté.',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 20),

          // Plage horaire
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Horaires',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickTime,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(children: [
                const Icon(Icons.schedule, color: AppTheme.primary, size: 20),
                const SizedBox(width: 12),
                Text('${_fmt(_start)}  →  ${_fmt(_end)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                const Icon(Icons.edit_outlined,
                    color: AppTheme.textMuted, size: 16),
              ]),
            ),
          ),

          // Sélection des mots-clés (mode keywordTrigger uniquement)
          if (_mode == ScheduleMode.keywordTrigger) ...[
            const SizedBox(height: 20),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Mots-clés à écouter (optionnel)',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            ),
            const SizedBox(height: 8),
            if (state.keywords.isEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_outlined,
                      color: Colors.orange, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Aucun mot-clé. Ajoutez-en dans l\'onglet Mots-clés d\'abord.',
                      style: TextStyle(color: Colors.orange, fontSize: 12),
                    ),
                  ),
                ]),
              )
            else
              ...state.keywords.map((k) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('"${k.text}"',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                    subtitle: Text(
                        k.isRecorded
                            ? 'Échantillon enregistré'
                            : 'Pas d\'échantillon',
                        style: TextStyle(
                            color: k.isRecorded
                                ? AppTheme.primary
                                : AppTheme.danger,
                            fontSize: 11)),
                    value: _selectedKeywordIds.contains(k.id),
                    onChanged: k.isRecorded
                        ? (v) => setState(() {
                              if (v == true) {
                                _selectedKeywordIds.add(k.id);
                              } else {
                                _selectedKeywordIds.remove(k.id);
                              }
                            })
                        : null,
                    activeColor: AppTheme.primary,
                  )),
          ],

          const SizedBox(height: 28),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: AppTheme.line),
                  foregroundColor: AppTheme.textMuted,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Annuler'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => _save(state),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Créer le créneau'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color.withValues(alpha: 0.6) : AppTheme.line,
            width: 1.5,
          ),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: selected ? color : AppTheme.textMuted, size: 22),
          ]),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: selected ? color : AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
