import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/recording_model.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';
import '../widgets/audio_waveform.dart';
import 'recording_detail_screen.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        top: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Header(onQueryChanged: (value) => setState(() => _query = value)),
          Expanded(
            child: Consumer<AppState>(
              builder: (_, state, __) {
                final recordings = state.searchRecordings(_query);
                if (state.recordings.isEmpty) return const _EmptyState();
                if (recordings.isEmpty) return const _NoSearchResults();
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 104),
                  itemCount: recordings.length,
                  itemBuilder: (_, i) =>
                      RecordingCard(recording: recordings[i]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final ValueChanged<String> onQueryChanged;
  const _Header({required this.onQueryChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'Enregistrements',
          style: TextStyle(
            color: AppTheme.text,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Consumer<AppState>(
          builder: (_, state, __) => Text(
            '${state.recordings.length} fichier(s)',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 14),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          onChanged: onQueryChanged,
          style: const TextStyle(color: AppTheme.text, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Rechercher dans les transcriptions',
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: AppTheme.surfaceHigh,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ]),
    );
  }
}

class RecordingCard extends StatefulWidget {
  final RecordingModel recording;
  final bool removableFromFolder;
  const RecordingCard({
    super.key,
    required this.recording,
    this.removableFromFolder = false,
  });

  @override
  State<RecordingCard> createState() => _RecordingCardState();
}

class _RecordingCardState extends State<RecordingCard> {
  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _loading = false;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _playbackDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
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

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Duration get _duration => _playbackDuration > Duration.zero
      ? _playbackDuration
      : widget.recording.duration ?? Duration.zero;

  double get _progress => _duration.inMilliseconds <= 0
      ? 0
      : (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0);

  String _fmt(Duration? d) {
    if (d == null) return '--:--';
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.recording;
    final date = DateFormat('dd/MM/yyyy').format(r.createdAt);
    final time = DateFormat('HH:mm').format(r.createdAt);
    final elapsed = _position > Duration.zero || _isPlaying
        ? '${_fmt(_position)}/${_fmt(_duration)}'
        : _fmt(_duration);

    return Consumer<AppState>(
      builder: (context, state, _) => InkWell(
        onTap: () => _openDetail(RecordingDetailSection.transcription),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.panel(radius: 18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.title,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$date · $time · ${r.fileName}',
                      style:
                          const TextStyle(color: Colors.white38, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _IconAction(
                icon: Icons.edit_rounded,
                color: AppTheme.textMuted,
                tooltip: 'Renommer',
                onPressed: () => _rename(state),
              ),
              _IconAction(
                icon: r.isFavorite
                    ? Icons.star_rounded
                    : Icons.star_border_rounded,
                color: r.isFavorite ? AppTheme.primary : AppTheme.textMuted,
                tooltip: 'Favori',
                onPressed: () => state.toggleFavorite(r.id),
              ),
              _IconAction(
                icon: Icons.folder_special_rounded,
                color: AppTheme.primary,
                tooltip: 'Classer',
                onPressed: () => _assignFolder(state),
              ),
              _IconAction(
                icon: Icons.download_rounded,
                color: AppTheme.primary,
                tooltip: 'Ajouter à la galerie',
                onPressed: () => _saveAudioToGallery(state),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              SizedBox(
                width: 58,
                child: Column(children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      elapsed,
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  IconButton.filled(
                    onPressed: _togglePlayback,
                    icon: Icon(
                      _isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: const Color(0xFF04211F),
                    ),
                    tooltip: _isPlaying ? 'Pause' : 'Lire',
                  ),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AudioWaveform(
                  samples: r.waveform,
                  active: _isPlaying,
                  liveLevel: _isPlaying ? 0.36 : 0,
                  height: 52,
                  progress: _progress,
                  onSeekFraction: _seekByFraction,
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Badge(label: r.triggerLabel, color: AppTheme.surfaceMuted),
                if (r.folderId != null)
                  _Badge(
                    label: _folderLabel(state, r.folderId!),
                    color: AppTheme.accent.withValues(alpha: 0.16),
                    textColor: AppTheme.accent,
                  ),
                if (r.transcription != null)
                  _Badge(
                    label: 'Transcrit',
                    color: AppTheme.primary.withValues(alpha: 0.16),
                    textColor: AppTheme.primary,
                  ),
                if (r.summary != null)
                  _Badge(
                    label: 'Résumé',
                    color: AppTheme.blue.withValues(alpha: 0.16),
                    textColor: AppTheme.blue,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: CircularProgressIndicator(color: AppTheme.primary),
                ),
              )
            else
              Row(children: [
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.text_fields_rounded,
                    label: r.transcription != null ? 'Ouvrir' : 'Transcrire',
                    onTap: () => r.transcription != null
                        ? _openDetail(RecordingDetailSection.transcription)
                        : _transcribe(state),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ActionBtn(
                    icon: Icons.auto_awesome_rounded,
                    label: r.summary != null ? 'Résumé' : 'Résumer',
                    onTap: () => r.summary != null
                        ? _openDetail(RecordingDetailSection.summary)
                        : _summarize(state),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  icon: Icon(
                    widget.removableFromFolder
                        ? Icons.remove_circle_outline
                        : Icons.delete_outline,
                    color: AppTheme.danger,
                  ),
                  onPressed: widget.removableFromFolder
                      ? () => state.assignRecordingToFolder(
                            widget.recording.id,
                            null,
                          )
                      : () => _confirmDelete(context, state),
                  tooltip: widget.removableFromFolder
                      ? 'Retirer du dossier'
                      : 'Supprimer',
                ),
              ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _togglePlayback() async {
    final file = File(widget.recording.filePath);
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
    if (_position > Duration.zero && _position < _duration) {
      await _player.resume();
    } else {
      setState(() => _position = Duration.zero);
      await _player.play(
        DeviceFileSource(widget.recording.filePath),
        mode: PlayerMode.mediaPlayer,
      );
    }
  }

  Future<void> _seekByFraction(double fraction) async {
    if (_duration.inMilliseconds <= 0) return;
    final target = Duration(
      milliseconds: (_duration.inMilliseconds * fraction).round(),
    );
    await _player.seek(target);
    if (!_isPlaying) await _togglePlayback();
  }

  Future<void> _transcribe(AppState state) async {
    setState(() => _loading = true);
    try {
      await state.transcribeRecording(widget.recording.id);
      if (!mounted) return;
      _openDetail(RecordingDetailSection.transcription);
    } catch (error) {
      _showError('Transcription impossible', error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _summarize(AppState state) async {
    setState(() => _loading = true);
    try {
      if (widget.recording.transcription == null) {
        await state.transcribeRecording(widget.recording.id);
      }
      await state.summarizeRecording(widget.recording.id);
      if (!mounted) return;
      _openDetail(RecordingDetailSection.summary);
    } catch (error) {
      _showError('Resume impossible', error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String title, Object error) {
    if (!mounted) return;
    final message = error.toString().replaceFirst('Exception: ', '');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title : $message')),
    );
  }

  Future<void> _saveAudioToGallery(AppState state) async {
    final path = await state.saveRecordingToGallery(widget.recording.id);
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

  Future<void> _rename(AppState state) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _RenameRecordingDialog(initialName: widget.recording.title),
    );
    if (name == null) return;
    await state.renameRecording(widget.recording.id, name);
  }

  String _folderLabel(AppState state, String folderId) {
    for (final folder in state.folders) {
      if (folder.id == folderId) return folder.name;
    }
    return 'Dossier';
  }

  Future<void> _assignFolder(AppState state) async {
    if (state.folders.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Créez d'abord un dossier depuis le menu.")),
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
                  await state.assignRecordingToFolder(
                      widget.recording.id, null);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
              ...state.folders.map(
                (folder) => ListTile(
                  leading: const Icon(Icons.folder_special_rounded),
                  title: Text(folder.name),
                  trailing: widget.recording.folderId == folder.id
                      ? const Icon(Icons.check_rounded, color: AppTheme.primary)
                      : null,
                  onTap: () async {
                    await state.assignRecordingToFolder(
                      widget.recording.id,
                      folder.id,
                    );
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

  void _openDetail(RecordingDetailSection section) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecordingDetailScreen(
          recordingId: widget.recording.id,
          initialSection: section,
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, AppState state) {
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
            onPressed: () {
              state.deleteRecording(widget.recording.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

class _RenameRecordingDialog extends StatefulWidget {
  final String initialName;

  const _RenameRecordingDialog({required this.initialName});

  @override
  State<_RenameRecordingDialog> createState() => _RenameRecordingDialogState();
}

class _RenameRecordingDialogState extends State<_RenameRecordingDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text(
        "Nommer l'enregistrement",
        style: TextStyle(color: AppTheme.text),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        style: const TextStyle(color: AppTheme.text),
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(labelText: 'Nom'),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Sauver'),
        ),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;
  const _IconAction({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: color),
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color? textColor;
  const _Badge({required this.label, required this.color, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor ?? AppTheme.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.55)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
          Icons.mic_none,
          size: 72,
          color: AppTheme.primary.withValues(alpha: 0.18),
        ),
        const SizedBox(height: 16),
        const Text(
          'Aucun enregistrement',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 16),
        ),
      ]),
    );
  }
}

class _NoSearchResults extends StatelessWidget {
  const _NoSearchResults();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Aucun résultat',
        style: TextStyle(color: AppTheme.textMuted, fontSize: 15),
      ),
    );
  }
}
