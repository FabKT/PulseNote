import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../ui/app_theme.dart';
import 'recordings_screen.dart';

class ImportAudioScreen extends StatefulWidget {
  const ImportAudioScreen({super.key});

  @override
  State<ImportAudioScreen> createState() => _ImportAudioScreenState();
}

class _ImportAudioScreenState extends State<ImportAudioScreen> {
  File? _selectedFile;
  final TextEditingController _nameController = TextEditingController();
  final List<String> _importedRecordingIds = [];
  bool _importing = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fileName = _selectedFile == null
        ? 'Aucun audio sélectionné'
        : _fileName(_selectedFile!.path);

    final state = context.watch<AppState>();
    final importedRecordings = [
      for (final id in _importedRecordingIds)
        if (state.recordingById(id) != null) state.recordingById(id)!,
    ];

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        top: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
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
                  'Importer un audio',
                  style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: AppTheme.panel(radius: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Audio à ajouter',
                    style: TextStyle(
                      color: AppTheme.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 14,
                    ),
                  ),
                  if (_selectedFile != null) ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(color: AppTheme.text),
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: "Nom de l'audio",
                        prefixIcon: Icon(Icons.edit_rounded),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: _importing ? null : _pickAudio,
                      icon: const Icon(Icons.audio_file_rounded),
                      label: const Text('Sélectionner un audio'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: BorderSide(
                          color: AppTheme.primary.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 58,
              child: FilledButton.icon(
                onPressed: _selectedFile == null || _importing ? null : _import,
                icon: _importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF04211F),
                        ),
                      )
                    : const Icon(Icons.file_upload_rounded),
                label: Text(_importing ? 'Import...' : "Importer dans l'app"),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: const Color(0xFF04211F),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            if (importedRecordings.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'Audio importé',
                style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              for (final recording in importedRecordings)
                RecordingCard(recording: recording),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'mp3',
        'm4a',
        'mp4',
        'aac',
        'wav',
        'ogg',
        'flac'
      ],
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _selectedFile = File(path);
      _nameController.text = _baseNameWithoutExtension(path);
    });
  }

  Future<void> _import() async {
    final file = _selectedFile;
    if (file == null) return;
    setState(() => _importing = true);
    try {
      final imported = await context.read<AppState>().importAudioFile(
            filePath: file.path,
            displayName: _nameController.text.trim().isEmpty
                ? _baseNameWithoutExtension(file.path)
                : _nameController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio importé.')),
      );
      setState(() {
        _selectedFile = null;
        _nameController.clear();
        if (imported != null) {
          _importedRecordingIds
            ..remove(imported.id)
            ..insert(0, imported.id);
        }
      });
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import impossible : $message')),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.substring(normalized.lastIndexOf('/') + 1);
  }

  String _baseNameWithoutExtension(String path) {
    final name = _fileName(path);
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }
}
