import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;

import '../state/app_state.dart';
import '../ui/app_theme.dart';
import '../widgets/audio_waveform.dart';
import '../widgets/status_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _handledCreatedRecordingSignal = 0;

  void _maybeAskRecordingName(AppState state) {
    final signal = state.createdRecordingSignal;
    final id = state.lastCreatedRecordingId;
    if (signal == 0 || signal == _handledCreatedRecordingSignal || id == null) {
      return;
    }
    _handledCreatedRecordingSignal = signal;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final liveState = context.read<AppState>();
      final recording = liveState.recordingById(id);
      if (recording == null) return;
      if (recording.displayName?.trim().isNotEmpty == true) return;
      if (recording.triggerSource?.startsWith('schedule:') == true) return;

      final controller = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text(
            'Nom de l\'audio',
            style: TextStyle(color: AppTheme.text),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            style: const TextStyle(color: AppTheme.text),
            decoration: InputDecoration(
              hintText: 'Ex. Note rapide',
              filled: true,
              fillColor: AppTheme.surfaceHigh,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Plus tard'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (name == null || name.trim().isEmpty) return;
      await liveState.renameRecording(id, name);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        top: false,
        child: Consumer<AppState>(
          builder: (_, state, __) {
            _maybeAskRecordingName(state);
            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 720;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 84),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Capture vocale intelligente',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 14),
                      StatusCard(
                          status: state.status, schedules: state.schedules),
                      if (state.status == AppStatus.listening) ...[
                        const SizedBox(height: 10),
                        _KeywordListeningCard(state: state),
                      ],
                      SizedBox(height: compact ? 10 : 16),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, orbConstraints) {
                            final maxByWidth = orbConstraints.maxWidth - 56;
                            final maxByHeight = orbConstraints.maxHeight -
                                (compact ? 42.0 : 50.0);
                            final limit = compact ? 188.0 : 220.0;
                            final size = math.min(
                                math.min(maxByWidth, maxByHeight), limit);
                            return Center(
                              child: _LiveAudioOrb(
                                state: state,
                                size: math.max(112.0, size),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: compact ? 14 : 20),
                      _SessionButton(state: state),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _KeywordListeningCard extends StatelessWidget {
  final AppState state;

  const _KeywordListeningCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final error = state.lastKeywordDetectionError;
    final recognized = state.lastKeywordRecognitionText.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error == null ? Icons.hearing_rounded : Icons.warning_amber_rounded,
            color: error == null ? AppTheme.accent : AppTheme.danger,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error != null
                  ? 'Erreur reconnaissance vocale : $error'
                  : recognized.isEmpty
                      ? 'Écoute des mots-clés active'
                      : 'Dernier texte reconnu : "$recognized"',
              style: TextStyle(
                color: error != null ? AppTheme.danger : AppTheme.textMuted,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveAudioOrb extends StatelessWidget {
  final AppState state;
  final double size;
  const _LiveAudioOrb({required this.state, required this.size});

  @override
  Widget build(BuildContext context) {
    final active = state.status == AppStatus.recording;
    final listening = state.status == AppStatus.listening;
    final label = active
        ? 'Enregistrement en cours'
        : listening
            ? 'En écoute'
            : state.status == AppStatus.sessionActive
                ? 'Session prête'
                : 'Prêt à capturer';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: AudioWaveform(
            samples: state.liveWaveform,
            liveLevel: state.currentAudioLevel,
            active: active || listening,
            circular: true,
            height: size,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: active ? AppTheme.primary : AppTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SessionButton extends StatelessWidget {
  final AppState state;
  const _SessionButton({required this.state});

  @override
  Widget build(BuildContext context) {
    final active = state.status != AppStatus.idle;
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton.icon(
        onPressed: active ? state.stopSession : state.startSession,
        icon: Icon(active ? Icons.stop_rounded : Icons.play_arrow_rounded),
        label: Text(
          active ? 'Arrêter la session' : 'Démarrer la session',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: active ? AppTheme.danger : AppTheme.primary,
          foregroundColor: active ? Colors.white : const Color(0xFF04211F),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
