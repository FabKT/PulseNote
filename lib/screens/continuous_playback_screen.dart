import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/premium_feature.dart';
import '../models/recording_model.dart';
import '../models/subscription_tier.dart';
import '../services/continuous_playback_service.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';
import '../widgets/audio_waveform.dart';
import '../widgets/feature_lock_screen.dart';
import 'import_audio_screen.dart';

class ContinuousPlaybackScreen extends StatefulWidget {
  const ContinuousPlaybackScreen({super.key});

  @override
  State<ContinuousPlaybackScreen> createState() =>
      _ContinuousPlaybackScreenState();
}

class _ContinuousPlaybackScreenState extends State<ContinuousPlaybackScreen> {
  final _playback = ContinuousPlaybackService.instance;
  String? _selectedRecordingId;

  @override
  void dispose() {
    _playback.stopIfUnlocked();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.tier.hasContinuousPlayback) {
      return const FeatureLockScreen(
        feature: PremiumFeature.continuousPlayback,
        title: 'Lecture continue',
      );
    }
    final recordings = state.recordings;
    _selectedRecordingId ??= _playback.recordingId ??
        (recordings.isEmpty ? null : recordings.first.id);
    final selectedRecording = _selectedRecording(state);

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        top: true,
        child: AnimatedBuilder(
          animation: _playback,
          builder: (context, _) {
            final effectiveDuration = _playback.duration > Duration.zero
                ? _playback.duration
                : selectedRecording?.duration ?? Duration.zero;
            final progress = effectiveDuration.inMilliseconds <= 0
                ? 0.0
                : (_playback.position.inMilliseconds /
                        effectiveDuration.inMilliseconds)
                    .clamp(0.0, 1.0);

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Row(children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppTheme.text,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Lecture continue',
                      style: TextStyle(
                        color: AppTheme.text,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: AppTheme.panel(radius: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(
                          Icons.all_inclusive_rounded,
                          color: AppTheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            selectedRecording?.title ?? 'Aucun audio choisi',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.text,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: () => _toggleLock(),
                          icon: Icon(
                            _playback.locked
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                          ),
                          tooltip: _playback.locked
                              ? 'Lecture verrouillée'
                              : 'Lecture non verrouillée',
                          style: IconButton.styleFrom(
                            backgroundColor: _playback.locked
                                ? AppTheme.primary
                                : AppTheme.surfaceHigh,
                            foregroundColor: _playback.locked
                                ? const Color(0xFF04211F)
                                : AppTheme.textMuted,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        _playback.locked
                            ? 'Verrouillée : continue hors de cette page et en arrière-plan.'
                            : 'Non verrouillée : s’arrête quand vous quittez cette page.',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),
                      AudioWaveform(
                        samples: selectedRecording?.waveform ?? const [],
                        active: _playback.isPlaying,
                        liveLevel: _playback.isPlaying ? 0.36 : 0,
                        height: 68,
                        progress: progress,
                        onSeekFraction: selectedRecording == null
                            ? null
                            : (fraction) => _playback.seekByFraction(fraction),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        Text(
                          '${_fmt(_playback.position)} / ${_fmt(effectiveDuration)}',
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _playback.isPlaying ? 'En lecture' : 'En pause',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ]),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: FilledButton.icon(
                          onPressed:
                              selectedRecording == null || _playback.loading
                                  ? null
                                  : () => _toggle(selectedRecording),
                          icon: _playback.loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF04211F),
                                  ),
                                )
                              : Icon(
                                  _playback.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                          label: Text(
                            _playback.isPlaying
                                ? 'Mettre en pause'
                                : 'Démarrer la lecture continue',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.primary,
                            foregroundColor: const Color(0xFF04211F),
                            textStyle: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: _openImportAudio,
                    icon: const Icon(Icons.file_upload_rounded),
                    label: const Text('Importer un audio'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.primary,
                      side: BorderSide(
                        color: AppTheme.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Choisir un audio',
                  style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                if (recordings.isEmpty)
                  const _EmptyAudioState()
                else
                  for (final recording in recordings)
                    _AudioChoiceTile(
                      recording: recording,
                      selected: recording.id == _selectedRecordingId,
                      onTap: () => _selectRecording(recording),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  RecordingModel? _selectedRecording(AppState state) {
    final id = _selectedRecordingId;
    if (id == null) return null;
    return state.recordingById(id);
  }

  Future<void> _toggle(RecordingModel recording) async {
    try {
      await _playback.toggle(recording);
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<void> _selectRecording(RecordingModel recording) async {
    setState(() => _selectedRecordingId = recording.id);
    await _playback.select(recording);
  }

  Future<void> _toggleLock() async {
    await _playback.setLocked(!_playback.locked);
  }

  void _openImportAudio() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ImportAudioScreen()),
    );
  }

  String _fmt(Duration duration) {
    if (duration <= Duration.zero) return '--:--';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }
}

class _AudioChoiceTile extends StatelessWidget {
  final RecordingModel recording;
  final bool selected;
  final VoidCallback onTap;

  const _AudioChoiceTile({
    required this.recording,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd/MM/yyyy · HH:mm').format(recording.createdAt);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.panel(
          radius: 16,
          borderColor: selected
              ? AppTheme.primary.withValues(alpha: 0.65)
              : AppTheme.line,
        ),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.primary.withValues(alpha: 0.18)
                  : AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              selected ? Icons.check_circle_rounded : Icons.audio_file_rounded,
              color: selected ? AppTheme.primary : AppTheme.textMuted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                recording.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '$date · ${recording.triggerLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _EmptyAudioState extends StatelessWidget {
  const _EmptyAudioState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: AppTheme.panel(radius: 16),
      child: const Text(
        'Aucun audio disponible. Importez un audio ou créez un enregistrement.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppTheme.textMuted),
      ),
    );
  }
}
