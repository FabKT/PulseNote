import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../ui/app_theme.dart';
import '../widgets/audio_waveform.dart';
import '../widgets/status_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        top: false,
        child: Consumer<AppState>(
          builder: (_, state, __) => LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 720;
              final orbSize = (constraints.maxHeight - 260).clamp(130.0, 248.0);
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
                    Expanded(
                      child: Center(
                        child: _LiveAudioOrb(state: state, size: orbSize),
                      ),
                    ),
                    _SessionButton(state: state),
                  ],
                ),
              );
            },
          ),
        ),
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
        if (state.liveTranscriptionEnabled) ...[
          const SizedBox(height: 8),
          Container(
            width: size,
            constraints: const BoxConstraints(maxHeight: 64),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Text(
              state.liveTranscription.isEmpty
                  ? 'Transcription en direct...'
                  : state.liveTranscription,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ),
        ],
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
