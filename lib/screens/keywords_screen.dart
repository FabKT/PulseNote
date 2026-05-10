import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/keyword_model.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';
import '../widgets/keyword_card.dart';

class KeywordsScreen extends StatelessWidget {
  const KeywordsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        top: false,
        child: Consumer<AppState>(
          builder: (_, state, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Header(
                keywordCount: state.keywordCount,
              ),
              Expanded(
                child: state.keywords.isEmpty
                    ? const _EmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        itemCount: state.keywords.length,
                        itemBuilder: (ctx, i) {
                          final kw = state.keywords[i];
                          return KeywordCard(
                            keyword: kw,
                            onEdit: () =>
                                _showKeywordDialog(ctx, state, existing: kw),
                            onDelete: () => _confirmDelete(ctx, state, kw.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: Consumer<AppState>(
        builder: (ctx, state, _) => FloatingActionButton.extended(
          onPressed: () {
            final err = state.canAddKeyword();
            if (err != null) {
              ScaffoldMessenger.of(ctx)
                  .showSnackBar(SnackBar(content: Text(err)));
              return;
            }
            _showKeywordDialog(ctx, state);
          },
          backgroundColor: AppTheme.primary,
          foregroundColor: const Color(0xFF04211F),
          icon: const Icon(Icons.add),
          label: const Text('Ajouter'),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, AppState state, String id) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Supprimer ce mot-clé ?',
            style: TextStyle(color: AppTheme.text)),
        content: const Text(
            'Il sera retiré de tous les créneaux qui l\'utilisent.',
            style: TextStyle(color: AppTheme.textMuted)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              state.removeKeyword(id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  Future<void> _showKeywordDialog(BuildContext ctx, AppState state,
      {KeywordModel? existing}) async {
    await showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _KeywordSheet(state: state, existing: existing),
    );
  }
}

// ─── En-tête ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final int keywordCount;
  const _Header({required this.keywordCount});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Expanded(
            child: Text('Mots-clés',
                style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 28,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
        const SizedBox(height: 4),
        Text('$keywordCount / ${AppState.maxKeywords} enregistrés',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 14)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: AppTheme.primary, size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ajoutez jusqu\'à 3 mots-clés. Enregistrez votre voix pour chacun afin d\'améliorer la détection.',
                  style: TextStyle(color: AppTheme.primary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─── État vide ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.record_voice_over_outlined,
            size: 72, color: AppTheme.primary.withValues(alpha: 0.18)),
        const SizedBox(height: 16),
        const Text('Aucun mot-clé',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 16)),
        const SizedBox(height: 8),
        const Text('Appuyez sur + pour en ajouter un.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
      ]),
    );
  }
}

// ─── Bottom sheet création / édition d'un mot-clé ────────────────────────────

class PremiumLockedStatePlaceholder extends StatelessWidget {
  final VoidCallback onUpgrade;
  const PremiumLockedStatePlaceholder({super.key, required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    return Center(
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
          const Text('Déclenchement par mots-clés',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Cette automatisation fait partie de Ultimate Premium.',
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

class _KeywordSheet extends StatefulWidget {
  final AppState state;
  final KeywordModel? existing;
  const _KeywordSheet({required this.state, this.existing});

  @override
  State<_KeywordSheet> createState() => _KeywordSheetState();
}

class _KeywordSheetState extends State<_KeywordSheet> {
  late final TextEditingController _ctrl;
  String? _samplePath;
  bool _recording = false;
  int _countdown = 3;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.existing?.text ?? '');
    _samplePath = widget.existing?.audioSamplePath;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_recording) return;
    setState(() {
      _recording = true;
      _countdown = 3;
    });
    // Compte à rebours visible avant l'enregistrement
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 1) {
        t.cancel();
      } else {
        setState(() => _countdown--);
      }
    });
    final path = await widget.state.recordKeywordSample();
    _countdownTimer?.cancel();
    setState(() {
      _recording = false;
      _samplePath = path;
    });
  }

  void _save() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Entrez un mot-clé.')));
      return;
    }
    if (widget.existing != null) {
      widget.state.updateKeyword(
          widget.existing!.copyWith(text: text, audioSamplePath: _samplePath));
    } else {
      widget.state.addKeyword(KeywordModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        audioSamplePath: _samplePath,
      ));
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppTheme.line, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 20),
        Text(
          widget.existing != null ? 'Modifier le mot-clé' : 'Nouveau mot-clé',
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),

        // Étape 1 : texte
        const _StepLabel(number: '1', text: 'Texte du mot-clé'),
        const SizedBox(height: 10),
        TextField(
          controller: _ctrl,
          style: const TextStyle(color: Colors.white, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Ex : "démarre", "note", "enregistre"',
            hintStyle: const TextStyle(color: AppTheme.textMuted),
            filled: true,
            fillColor: AppTheme.surfaceHigh,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppTheme.primary)),
          ),
        ),
        const SizedBox(height: 20),

        // Étape 2 : enregistrement de l'échantillon
        const _StepLabel(number: '2', text: 'Échantillon vocal (3 secondes)'),
        const SizedBox(height: 10),
        _SampleRecorder(
          isRecording: _recording,
          countdown: _countdown,
          hasSample: _samplePath != null,
          onRecord: _startRecording,
        ),
        const SizedBox(height: 24),

        // Boutons
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
              onPressed: _recording ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text('Enregistrer'),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _StepLabel extends StatelessWidget {
  final String number;
  final String text;
  const _StepLabel({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      CircleAvatar(
          radius: 11,
          backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
          child: Text(number,
              style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold))),
      const SizedBox(width: 8),
      Text(text,
          style: const TextStyle(
              color: AppTheme.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w500)),
    ]);
  }
}

class _SampleRecorder extends StatelessWidget {
  final bool isRecording;
  final int countdown;
  final bool hasSample;
  final VoidCallback onRecord;
  const _SampleRecorder({
    required this.isRecording,
    required this.countdown,
    required this.hasSample,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isRecording ? null : onRecord,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isRecording
              ? AppTheme.danger.withValues(alpha: 0.1)
              : AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isRecording
                ? AppTheme.danger.withValues(alpha: 0.5)
                : hasSample
                    ? AppTheme.primary.withValues(alpha: 0.4)
                    : Colors.white12,
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (isRecording) ...[
            const Icon(Icons.fiber_manual_record,
                color: AppTheme.danger, size: 18),
            const SizedBox(width: 10),
            Text('Enregistrement… $countdown s',
                style: const TextStyle(
                    color: AppTheme.danger, fontWeight: FontWeight.w600)),
          ] else if (hasSample) ...[
            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 10),
            const Text('Échantillon enregistré — Appuyer pour refaire',
                style: TextStyle(color: Colors.greenAccent, fontSize: 13)),
          ] else ...[
            const Icon(Icons.mic, color: AppTheme.primary, size: 18),
            const SizedBox(width: 10),
            const Text('Appuyer pour enregistrer',
                style: TextStyle(color: AppTheme.primary)),
          ],
        ]),
      ),
    );
  }
}
