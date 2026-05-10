import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/recording_model.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    _transcriptionCtrl = TextEditingController();
    _summaryCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _transcriptionCtrl.dispose();
    _summaryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    RecordingModel? recording;
    for (final item in state.recordings) {
      if (item.id == widget.recordingId) {
        recording = item;
        break;
      }
    }

    if (recording == null) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Text('Enregistrement introuvable',
              style: TextStyle(color: AppTheme.textMuted)),
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
            onPressed: () => _save(state, recording!),
            icon: const Icon(Icons.save_rounded),
            tooltip: 'Sauvegarder',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(DateFormat('dd/MM/yyyy · HH:mm').format(recording.createdAt),
                style: const TextStyle(color: AppTheme.textMuted)),
            const SizedBox(height: 16),
            SegmentedButton<RecordingDetailSection>(
              segments: const [
                ButtonSegment(
                    value: RecordingDetailSection.transcription,
                    icon: Icon(Icons.text_fields_rounded),
                    label: Text('Transcription')),
                ButtonSegment(
                    value: RecordingDetailSection.summary,
                    icon: Icon(Icons.auto_awesome_rounded),
                    label: Text('Résumé')),
              ],
              selected: {_section},
              onSelectionChanged: (value) =>
                  setState(() => _section = value.first),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
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
            ),
          ]),
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

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copié.')));
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
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Modifications sauvées.')));
  }
}
