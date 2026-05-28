import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/audio_playback_schedule_model.dart';
import '../models/recording_model.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';
import '../widgets/flat_number_picker.dart';

class ScheduledAudioScreen extends StatelessWidget {
  const ScheduledAudioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        top: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lecture planifiée',
                        style: TextStyle(
                          color: AppTheme.text,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Lancez automatiquement un audio à une heure précise.',
                        style:
                            TextStyle(color: AppTheme.textMuted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showCreateSheet(context),
                  icon: const Icon(Icons.add_alarm_rounded),
                  label: const Text('Ajouter'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: const Color(0xFF04211F),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: Consumer<AppState>(
                builder: (_, state, __) {
                  if (state.audioPlaybackSchedules.isEmpty) {
                    return const _EmptyState();
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 104),
                    itemCount: state.audioPlaybackSchedules.length,
                    itemBuilder: (_, index) {
                      final schedule = state.audioPlaybackSchedules[index];
                      final recording =
                          state.recordingForPlaybackSchedule(schedule);
                      return _PlaybackScheduleCard(
                        title: recording?.title ?? 'Audio introuvable',
                        subtitle: recording == null
                            ? 'Cet enregistrement a été supprimé.'
                            : _recordingSubtitle(recording),
                        time: _fmt(schedule.time),
                        occurrence: schedule.occurrenceLabel,
                        active: schedule.isActive,
                        missing: recording == null,
                        onPlay: recording == null
                            ? null
                            : () => state.playRecordingNow(recording.id),
                        onEdit: () => _showEditSheet(context, schedule),
                        onToggle: () =>
                            state.toggleAudioPlaybackSchedule(schedule.id),
                        onDelete: () =>
                            state.deleteAudioPlaybackSchedule(schedule.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _recordingSubtitle(RecordingModel recording) {
    final date = DateFormat('dd/MM/yyyy · HH:mm').format(recording.createdAt);
    return '$date · ${recording.fileName}';
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateScheduledPlaybackSheet(),
    );
  }

  void _showEditSheet(
    BuildContext context,
    AudioPlaybackScheduleModel schedule,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateScheduledPlaybackSheet(scheduleToEdit: schedule),
    );
  }
}

class _PlaybackScheduleCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String time;
  final String occurrence;
  final bool active;
  final bool missing;
  final VoidCallback? onPlay;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _PlaybackScheduleCard({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.occurrence,
    required this.active,
    required this.missing,
    required this.onPlay,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.panel(
        radius: 18,
        borderColor:
            active ? AppTheme.primary.withValues(alpha: 0.5) : AppTheme.line,
      ),
      child: Row(children: [
        InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: active
                  ? AppTheme.primary.withValues(alpha: 0.15)
                  : AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              missing ? Icons.warning_amber_rounded : Icons.play_arrow_rounded,
              color: missing ? AppTheme.danger : AppTheme.primary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              time,
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              occurrence,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, color: AppTheme.textMuted),
              tooltip: 'Modifier',
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
              tooltip: 'Supprimer',
            ),
          ]),
          Transform.scale(
            scale: 0.86,
            child: Switch(
              value: active,
              onChanged: (_) => onToggle(),
              activeThumbColor: AppTheme.primary,
              activeTrackColor: AppTheme.primary.withValues(alpha: 0.28),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _CreateScheduledPlaybackSheet extends StatefulWidget {
  final AudioPlaybackScheduleModel? scheduleToEdit;

  const _CreateScheduledPlaybackSheet({this.scheduleToEdit});

  @override
  State<_CreateScheduledPlaybackSheet> createState() =>
      _CreateScheduledPlaybackSheetState();
}

class _CreateScheduledPlaybackSheetState
    extends State<_CreateScheduledPlaybackSheet> {
  static const _folderAll = 'all';
  static const _folderRecorded = 'recorded';
  static const _folderImported = 'imported';
  static const _folderMp4ToMp3 = 'mp4_to_mp3';
  static const _folderFavorites = 'favorites';
  static const _folderEnriched = 'enriched';

  String _folderId = _folderAll;
  String? _recordingId;
  bool _folderInitializedFromEdit = false;
  int _hour = TimeOfDay.now().hour;
  int _minute = TimeOfDay.now().minute;
  AudioPlaybackRecurrence _recurrence = AudioPlaybackRecurrence.once;
  DateTime _date = DateTime.now();
  final Set<int> _weekdays = {DateTime.now().weekday};

  @override
  void initState() {
    super.initState();
    final schedule = widget.scheduleToEdit;
    if (schedule == null) return;
    _recordingId = schedule.recordingId;
    _hour = schedule.time.hour;
    _minute = schedule.time.minute;
    _recurrence = schedule.recurrence;
    _date = schedule.date ?? DateTime.now();
    _weekdays
      ..clear()
      ..addAll(schedule.weekdays);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final allRecordings = state.recordings;
    if (_recordingId != null &&
        widget.scheduleToEdit != null &&
        !_folderInitializedFromEdit) {
      _folderId = _folderIdForRecording(state, _recordingId!);
      _folderInitializedFromEdit = true;
    }
    final recordings = _recordingsForFolder(state, _folderId);
    if (_recordingId != null && !recordings.any((r) => r.id == _recordingId)) {
      _recordingId = recordings.isEmpty ? null : recordings.first.id;
    }
    _recordingId ??= recordings.isEmpty ? null : recordings.first.id;

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.scheduleToEdit == null
                ? 'Nouvelle lecture planifiée'
                : 'Modifier la lecture planifiée',
            style: const TextStyle(
              color: AppTheme.text,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 20),
          if (allRecordings.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: AppTheme.panel(radius: 14),
              child: const Text(
                'Créez au moins un enregistrement avant de planifier une lecture.',
                style: TextStyle(color: AppTheme.textMuted),
              ),
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _folderId,
              dropdownColor: AppTheme.surfaceHigh,
              decoration: InputDecoration(
                labelText: 'Dossier',
                filled: true,
                fillColor: AppTheme.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.line),
                ),
              ),
              items: _folderChoices(state)
                  .map(
                    (folder) => DropdownMenuItem(
                      value: folder.id,
                      child: Text(
                        folder.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                _folderId = value ?? _folderAll;
                final folderRecordings = _recordingsForFolder(state, _folderId);
                _recordingId =
                    folderRecordings.isEmpty ? null : folderRecordings.first.id;
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _recordingId,
              dropdownColor: AppTheme.surfaceHigh,
              decoration: InputDecoration(
                labelText: 'Audio',
                filled: true,
                fillColor: AppTheme.surfaceHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppTheme.line),
                ),
              ),
              items: recordings
                  .map(
                    (recording) => DropdownMenuItem(
                      value: recording.id,
                      child: Text(
                        recording.title,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: recordings.isEmpty
                  ? null
                  : (value) => setState(() => _recordingId = value),
            ),
            const SizedBox(height: 18),
            _FlatTimePicker(
              hour: _hour,
              minute: _minute,
              onChanged: (hour, minute) => setState(() {
                _hour = hour;
                _minute = minute;
              }),
            ),
            const SizedBox(height: 18),
            SegmentedButton<AudioPlaybackRecurrence>(
              segments: const [
                ButtonSegment(
                  value: AudioPlaybackRecurrence.once,
                  label: Text('Date pr\u00e9cise'),
                  icon: Icon(Icons.event_rounded),
                ),
                ButtonSegment(
                  value: AudioPlaybackRecurrence.weekly,
                  label: Text('R\u00e9current'),
                  icon: Icon(Icons.repeat_rounded),
                ),
              ],
              selected: {_recurrence},
              onSelectionChanged: (selection) =>
                  setState(() => _recurrence = selection.first),
            ),
            const SizedBox(height: 14),
            if (_recurrence == AudioPlaybackRecurrence.once)
              _DateSelector(date: _date, onTap: _pickDate)
            else
              _WeekdaySelector(
                selected: _weekdays,
                onToggle: (day) => setState(() {
                  if (_weekdays.contains(day)) {
                    _weekdays.remove(day);
                  } else {
                    _weekdays.add(day);
                  }
                }),
              ),
          ],
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  side: const BorderSide(color: AppTheme.line),
                  foregroundColor: AppTheme.textMuted,
                ),
                child: const Text('Annuler'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _recordingId == null
                    ? null
                    : () async {
                        if (_recurrence == AudioPlaybackRecurrence.weekly &&
                            _weekdays.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content:
                                  Text('S\u00e9lectionnez au moins un jour.'),
                            ),
                          );
                          return;
                        }
                        final weekdays = _weekdays.toList()..sort();
                        final schedule = AudioPlaybackScheduleModel(
                          id: widget.scheduleToEdit?.id ??
                              DateTime.now().millisecondsSinceEpoch.toString(),
                          recordingId: _recordingId!,
                          time: TimeOfDay(hour: _hour, minute: _minute),
                          recurrence: _recurrence,
                          date: _recurrence == AudioPlaybackRecurrence.once
                              ? _date
                              : null,
                          weekdays:
                              _recurrence == AudioPlaybackRecurrence.weekly
                                  ? weekdays
                                  : const [],
                          isActive: widget.scheduleToEdit?.isActive ?? true,
                          lastPlayedDateKey:
                              widget.scheduleToEdit?.lastPlayedDateKey,
                        );
                        if (widget.scheduleToEdit == null) {
                          await context
                              .read<AppState>()
                              .addAudioPlaybackSchedule(
                                recordingId: schedule.recordingId,
                                time: schedule.time,
                                recurrence: schedule.recurrence,
                                date: schedule.date,
                                weekdays: schedule.weekdays,
                              );
                        } else {
                          await context
                              .read<AppState>()
                              .updateAudioPlaybackSchedule(schedule);
                        }
                        if (context.mounted) Navigator.pop(context);
                      },
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppTheme.primary,
                  foregroundColor: const Color(0xFF04211F),
                ),
                child: Text(
                  widget.scheduleToEdit == null ? 'Créer' : 'Enregistrer',
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _pickDate() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.primary,
            surface: AppTheme.surface,
          ),
        ),
        child: child!,
      ),
    );
    if (result != null) setState(() => _date = result);
  }

  List<_FolderChoice> _folderChoices(AppState state) => [
        const _FolderChoice(_folderAll, 'Tous les audios'),
        const _FolderChoice(_folderRecorded, 'Audios enregistrés'),
        const _FolderChoice(_folderImported, 'Audios importés'),
        const _FolderChoice(_folderMp4ToMp3, 'MP4 vers MP3'),
        const _FolderChoice(_folderFavorites, 'Favoris'),
        const _FolderChoice(_folderEnriched, 'Transcrits / résumés'),
        ...state.folders.map((folder) => _FolderChoice(folder.id, folder.name)),
      ];

  List<RecordingModel> _recordingsForFolder(AppState state, String folderId) {
    return switch (folderId) {
      _folderRecorded => state.recordings
          .where((r) =>
              r.triggerSource != AppState.importedAudioSource &&
              r.triggerSource != AppState.mp4ToMp3AudioSource)
          .toList(),
      _folderImported => state.recordings
          .where((r) => r.triggerSource == AppState.importedAudioSource)
          .toList(),
      _folderMp4ToMp3 => state.recordings
          .where((r) => r.triggerSource == AppState.mp4ToMp3AudioSource)
          .toList(),
      _folderFavorites => state.recordings.where((r) => r.isFavorite).toList(),
      _folderEnriched => state.recordings
          .where((r) => r.transcription != null || r.summary != null)
          .toList(),
      _folderAll => state.recordings,
      _ => state.recordingsForFolder(folderId),
    };
  }

  String _folderIdForRecording(AppState state, String recordingId) {
    final recording = state.recordingById(recordingId);
    if (recording == null) return _folderAll;
    if (recording.folderId != null) return recording.folderId!;
    if (recording.triggerSource == AppState.importedAudioSource) {
      return _folderImported;
    }
    if (recording.triggerSource == AppState.mp4ToMp3AudioSource) {
      return _folderMp4ToMp3;
    }
    return _folderRecorded;
  }
}

class _FolderChoice {
  final String id;
  final String label;

  const _FolderChoice(this.id, this.label);
}

class _DateSelector extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;

  const _DateSelector({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: AppTheme.panel(radius: 14),
        child: Row(children: [
          const Icon(Icons.calendar_month_rounded, color: AppTheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              DateFormat('dd/MM/yyyy').format(date),
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const Icon(Icons.edit_outlined, color: AppTheme.textMuted, size: 18),
        ]),
      ),
    );
  }
}

class _WeekdaySelector extends StatelessWidget {
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  const _WeekdaySelector({
    required this.selected,
    required this.onToggle,
  });

  static const _days = [
    (1, 'L'),
    (2, 'M'),
    (3, 'M'),
    (4, 'J'),
    (5, 'V'),
    (6, 'S'),
    (7, 'D'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final day in _days)
          ChoiceChip(
            label: Text(day.$2),
            selected: selected.contains(day.$1),
            onSelected: (_) => onToggle(day.$1),
            selectedColor: AppTheme.primary.withValues(alpha: 0.22),
            backgroundColor: AppTheme.surfaceHigh,
            labelStyle: TextStyle(
              color: selected.contains(day.$1)
                  ? AppTheme.primary
                  : AppTheme.textMuted,
              fontWeight: FontWeight.w800,
            ),
            side: BorderSide(
              color:
                  selected.contains(day.$1) ? AppTheme.primary : AppTheme.line,
            ),
          ),
      ],
    );
  }
}

class _FlatTimePicker extends StatelessWidget {
  final int hour;
  final int minute;
  final void Function(int hour, int minute) onChanged;

  const _FlatTimePicker({
    required this.hour,
    required this.minute,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 176,
      decoration: AppTheme.panel(radius: 16),
      child: Stack(children: [
        Center(
          child: Container(
            height: 56,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        Row(children: [
          Expanded(
            child: FlatNumberPicker(
              value: hour,
              max: 23,
              onChanged: (value) => onChanged(value, minute),
            ),
          ),
          const Text(
            ':',
            style: TextStyle(
              color: AppTheme.text,
              fontSize: 34,
              fontWeight: FontWeight.w300,
            ),
          ),
          Expanded(
            child: FlatNumberPicker(
              value: minute,
              max: 59,
              onChanged: (value) => onChanged(hour, value),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
            Icons.schedule_send_rounded,
            size: 64,
            color: AppTheme.primary.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aucune lecture planifiée',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 15),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choisissez un enregistrement et une heure pour lancer sa lecture automatiquement.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ]),
      ),
    );
  }
}
