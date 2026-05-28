import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/recording_model.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';
import '../widgets/audio_waveform.dart';

enum RecordingDetailSection { transcription, summary }

class RecordingDetailScreen extends StatefulWidget {
  final String recordingId;
  final RecordingDetailSection initialSection;

  const RecordingDetailScreen({
    super.key,
    required this.recordingId,
    required this.initialSection,
  });

  @override
  State<RecordingDetailScreen> createState() => _RecordingDetailScreenState();
}

class _RecordingDetailScreenState extends State<RecordingDetailScreen> {
  late RecordingDetailSection _section;
  late final TextEditingController _transcriptionCtrl;
  late final TextEditingController _summaryCtrl;
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _isPlaying = false;
  bool _loadingText = false;
  Duration _position = Duration.zero;
  Duration _playbackDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    _transcriptionCtrl = TextEditingController();
    _summaryCtrl = TextEditingController();
    _configurePlayer();
    _subs.addAll([
      _player.onPlayerStateChanged.listen((state) {
        if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
      }),
      _player.onPositionChanged.listen((position) {
        if (mounted) setState(() => _position = position);
      }),
      _player.onDurationChanged.listen((duration) {
        if (mounted) setState(() => _playbackDuration = duration);
      }),
      _player.onPlayerComplete.listen((_) {
        if (!mounted) return;
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }),
    ]);
  }

  @override
  void dispose() {
    _transcriptionCtrl.dispose();
    _summaryCtrl.dispose();
    for (final sub in _subs) {
      sub.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final recording = state.recordingById(widget.recordingId);

    if (recording == null) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Text(
            'Enregistrement introuvable',
            style: TextStyle(color: AppTheme.textMuted),
          ),
        ),
      );
    }

    _syncControllers(recording);
    final activeText = _section == RecordingDetailSection.transcription
        ? _transcriptionCtrl.text
        : _summaryCtrl.text;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.text,
        title: const Text('Détail audio'),
        actions: [
          IconButton(
            onPressed: () => _copy(activeText),
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copier',
          ),
          IconButton(
            onPressed: () => _save(state, recording),
            icon: const Icon(Icons.save_rounded),
            tooltip: 'Sauvegarder',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('dd/MM/yyyy · HH:mm').format(recording.createdAt),
                style: const TextStyle(color: AppTheme.textMuted),
              ),
              const SizedBox(height: 14),
              _DetailAudioPlayer(
                recording: recording,
                isPlaying: _isPlaying,
                position: _position,
                duration: _durationFor(recording),
                progress: _progressFor(recording),
                onPlay: () => _togglePlayback(recording),
                onSeek: _seekByFraction,
              ),
              const SizedBox(height: 12),
              Row(children: [
                _DetailIconButton(
                  icon: Icons.download_rounded,
                  tooltip: 'Ajouter à la galerie',
                  onPressed: () => _saveAudioToGallery(state, recording),
                ),
                const SizedBox(width: 10),
                _DetailIconButton(
                  icon: Icons.folder_special_rounded,
                  tooltip: 'Classer',
                  onPressed: () => _assignFolder(state, recording),
                ),
                const Spacer(),
                _DetailIconButton(
                  icon: Icons.delete_outline,
                  tooltip: 'Supprimer',
                  danger: true,
                  onPressed: () => _confirmDelete(context, state, recording),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: _SectionButton(
                    icon: Icons.text_fields_rounded,
                    label: 'Transcription',
                    selected: _section == RecordingDetailSection.transcription,
                    onTap: () => setState(
                      () => _section = RecordingDetailSection.transcription,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SectionButton(
                    icon: Icons.auto_awesome_rounded,
                    label: 'Résumé',
                    selected: _section == RecordingDetailSection.summary,
                    onTap: () => setState(
                      () => _section = RecordingDetailSection.summary,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 14),
              Expanded(
                child: Stack(children: [
                  TextField(
                    controller: _section == RecordingDetailSection.transcription
                        ? _transcriptionCtrl
                        : _summaryCtrl,
                    expands: true,
                    maxLines: null,
                    minLines: null,
                    textAlignVertical: TextAlignVertical.top,
                    style: const TextStyle(color: AppTheme.text, height: 1.45),
                    decoration: InputDecoration(
                      hintText: _section == RecordingDetailSection.transcription
                          ? 'La transcription apparaîtra ici.'
                          : 'Le résumé apparaîtra ici.',
                      hintStyle: const TextStyle(color: AppTheme.textMuted),
                      filled: true,
                      fillColor: AppTheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: AppTheme.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: AppTheme.line),
                      ),
                    ),
                  ),
                  if (activeText.trim().isEmpty)
                    Center(
                      child: _loadingText
                          ? const CircularProgressIndicator(
                              color: AppTheme.primary,
                            )
                          : FilledButton.icon(
                              onPressed: () => _generateCurrentText(
                                state,
                                recording,
                              ),
                              icon: Icon(
                                _section == RecordingDetailSection.transcription
                                    ? Icons.text_fields_rounded
                                    : Icons.auto_awesome_rounded,
                              ),
                              label: Text(
                                _section == RecordingDetailSection.transcription
                                    ? 'Lancer la transcription'
                                    : 'Lancer le résumé',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.primary,
                                foregroundColor: const Color(0xFF04211F),
                              ),
                            ),
                    ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _configurePlayer() async {
    await _player.setPlayerMode(PlayerMode.mediaPlayer);
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          stayAwake: true,
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
  }

  void _syncControllers(RecordingModel recording) {
    final transcription = recording.transcription ?? '';
    final summary = recording.summary ?? '';
    if (_transcriptionCtrl.text != transcription) {
      _transcriptionCtrl.text = transcription;
    }
    if (_summaryCtrl.text != summary) {
      _summaryCtrl.text = summary;
    }
  }

  Duration _durationFor(RecordingModel recording) =>
      _playbackDuration > Duration.zero
          ? _playbackDuration
          : recording.duration ?? Duration.zero;

  double _progressFor(RecordingModel recording) {
    final duration = _durationFor(recording);
    if (duration.inMilliseconds <= 0) return 0;
    return (_position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copié.')),
    );
  }

  Future<void> _save(AppState state, RecordingModel recording) async {
    await state.updateRecordingText(
      id: recording.id,
      transcription: _transcriptionCtrl.text.trim().isEmpty
          ? null
          : _transcriptionCtrl.text.trim(),
      summary:
          _summaryCtrl.text.trim().isEmpty ? null : _summaryCtrl.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Modifications sauvées.')),
    );
  }

  Future<void> _generateCurrentText(
    AppState state,
    RecordingModel recording,
  ) async {
    setState(() => _loadingText = true);
    try {
      if (_section == RecordingDetailSection.transcription) {
        await state.transcribeRecording(recording.id);
      } else {
        if (recording.transcription == null) {
          await state.transcribeRecording(recording.id);
        }
        await state.summarizeRecording(recording.id);
      }
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action impossible : $message')),
      );
    } finally {
      if (mounted) setState(() => _loadingText = false);
    }
  }

  Future<void> _togglePlayback(RecordingModel recording) async {
    final file = File(recording.filePath);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fichier audio introuvable.')),
      );
      return;
    }
    if (_isPlaying) {
      await _player.pause();
      return;
    }
    if (_position > Duration.zero && _position < _durationFor(recording)) {
      await _player.resume();
    } else {
      setState(() => _position = Duration.zero);
      await _player.play(
        DeviceFileSource(recording.filePath),
        mode: PlayerMode.mediaPlayer,
      );
    }
  }

  Future<void> _seekByFraction(double fraction) async {
    final recording =
        context.read<AppState>().recordingById(widget.recordingId);
    if (recording == null) return;
    final duration = _durationFor(recording);
    if (duration.inMilliseconds <= 0) return;
    final target = Duration(
      milliseconds: (duration.inMilliseconds * fraction).round(),
    );
    await _player.seek(target);
    if (!_isPlaying) await _togglePlayback(recording);
  }

  Future<void> _saveAudioToGallery(
    AppState state,
    RecordingModel recording,
  ) async {
    final path = await state.saveRecordingToGallery(recording.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path == null
              ? 'Sauvegarde impossible.'
              : 'Vidéo audio ajoutée à la galerie.',
        ),
      ),
    );
  }

  Future<void> _assignFolder(AppState state, RecordingModel recording) async {
    if (state.folders.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Créez d'abord un dossier depuis le menu."),
        ),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
                child: Text(
                  'Classer dans un dossier',
                  style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.folder_off_rounded),
                title: const Text('Aucun dossier'),
                onTap: () async {
                  await state.assignRecordingToFolder(recording.id, null);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              ...state.folders.map(
                (folder) => ListTile(
                  leading: const Icon(Icons.folder_special_rounded),
                  title: Text(folder.name),
                  trailing: recording.folderId == folder.id
                      ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                      : null,
                  onTap: () async {
                    await state.assignRecordingToFolder(
                        recording.id, folder.id);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext ctx,
    AppState state,
    RecordingModel recording,
  ) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Supprimer cet enregistrement ?',
          style: TextStyle(color: AppTheme.text),
        ),
        content: const Text(
          'Action irréversible.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () async {
              await state.deleteRecording(recording.id);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) Navigator.pop(context);
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

class _DetailAudioPlayer extends StatelessWidget {
  final RecordingModel recording;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final double progress;
  final VoidCallback onPlay;
  final ValueChanged<double> onSeek;

  const _DetailAudioPlayer({
    required this.recording,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.progress,
    required this.onPlay,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.panel(radius: 18),
      child: Row(children: [
        IconButton.filled(
          onPressed: onPlay,
          icon:
              Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
          style: IconButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: const Color(0xFF04211F),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${_fmt(position)}/${_fmt(duration)}',
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            AudioWaveform(
              samples: recording.waveform,
              active: isPlaying,
              liveLevel: isPlaying ? 0.36 : 0,
              height: 46,
              progress: progress,
              onSeekFraction: onSeek,
            ),
          ]),
        ),
      ]),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _DetailIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool danger;

  const _DetailIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppTheme.danger : AppTheme.primary;
    return IconButton.outlined(
      onPressed: onPressed,
      icon: Icon(icon, color: color),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        side: BorderSide(color: color.withValues(alpha: 0.55)),
      ),
    );
  }
}

class _SectionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SectionButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withValues(alpha: 0.15)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.primary.withValues(alpha: 0.62)
                : AppTheme.line,
            width: 1.5,
          ),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: selected ? AppTheme.primary : AppTheme.textMuted),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? AppTheme.primary : AppTheme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
