import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../ui/app_theme.dart';
import '../widgets/audio_waveform.dart';

class InstantTranscriptionScreen extends StatelessWidget {
  const InstantTranscriptionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        top: false,
        child: Consumer<AppState>(
          builder: (_, state, __) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 104),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Transcription instantanée',
                  style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 27,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Lance un enregistrement manuel et affiche le texte en direct.',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
                const SizedBox(height: 20),
                Center(
                  child: SizedBox(
                    width: 230,
                    child: AudioWaveform(
                      samples: state.liveWaveform,
                      liveLevel: state.currentAudioLevel,
                      active: state.status == AppStatus.recording,
                      circular: true,
                      height: 230,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (state.status == AppStatus.recording &&
                    !state.liveTranscriptionEnabled &&
                    state.lastLiveTranscriptionError != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.danger.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      state.lastLiveTranscriptionError!,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.panel(radius: 18),
                    child: SingleChildScrollView(
                      child: Text(
                        state.liveTranscription.trim().isEmpty
                            ? 'La transcription apparaîtra ici pendant l’enregistrement.'
                            : state.liveTranscription,
                        style: const TextStyle(
                          color: AppTheme.text,
                          height: 1.45,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: state.status == AppStatus.recording
                      ? FilledButton.icon(
                          onPressed: state.stopRecording,
                          icon: const Icon(Icons.stop_rounded),
                          label: const Text('Arrêter'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.danger,
                            foregroundColor: Colors.white,
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: state.startRecording,
                          icon: const Icon(Icons.mic_rounded),
                          label: const Text('Démarrer la transcription'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
