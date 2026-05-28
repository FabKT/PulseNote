import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../services/media_export_service.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';
import 'recordings_screen.dart';

class Mp4ToMp3Screen extends StatefulWidget {
  const Mp4ToMp3Screen({super.key});

  @override
  State<Mp4ToMp3Screen> createState() => _Mp4ToMp3ScreenState();
}

class _Mp4ToMp3ScreenState extends State<Mp4ToMp3Screen> {
  final _mediaExport = MediaExportService();
  File? _selectedFile;
  final TextEditingController _nameController = TextEditingController();
  String? _lastOutputName;
  final List<String> _convertedRecordingIds = [];
  bool _converting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedName = _selectedFile == null
        ? 'Aucun fichier sélectionné'
        : _fileName(_selectedFile!.path);

    final state = context.watch<AppState>();
    final convertedRecordings = [
      for (final id in _convertedRecordingIds)
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
                  'MP4 vers MP3',
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
                    'Fichier MP4',
                    style: TextStyle(
                      color: AppTheme.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    selectedName,
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
                      onPressed: _converting ? null : _pickMp4,
                      icon: const Icon(Icons.video_file_rounded),
                      label: const Text('Sélectionner un MP4'),
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
                onPressed:
                    _selectedFile == null || _converting ? null : _convert,
                icon: _converting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF04211F),
                        ),
                      )
                    : const Icon(Icons.audio_file_rounded),
                label: Text(_converting ? 'Conversion...' : 'Convertir en MP3'),
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
            if (_lastOutputName != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.36),
                  ),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded,
                      color: AppTheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'MP3 enregistré : $_lastOutputName',
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ]),
              ),
            ],
            if (convertedRecordings.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text(
                'Audio converti',
                style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              for (final recording in convertedRecordings)
                RecordingCard(recording: recording),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickMp4() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp4'],
      allowMultiple: false,
      withData: false,
    );
    final path = result?.files.single.path;
    if (path == null) return;
    setState(() {
      _selectedFile = File(path);
      _nameController.text = _baseNameWithoutExtension(path);
      _lastOutputName = null;
    });
  }

  Future<void> _convert() async {
    final input = _selectedFile;
    if (input == null) return;
    final state = context.read<AppState>();

    setState(() => _converting = true);
    try {
      final tempDir = await getTemporaryDirectory();
      final baseName = _nameController.text.trim().isEmpty
          ? _baseNameWithoutExtension(input.path)
          : _nameController.text;
      final outputName = '${_safeName(baseName)}.mp3';
      final output = File(
        '${tempDir.path}/uar_mp3_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );

      final session = await FFmpegKit.executeWithArguments([
        '-y',
        '-i',
        input.path,
        '-vn',
        '-codec:a',
        'libmp3lame',
        '-q:a',
        '2',
        output.path,
      ]);
      final returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode) || !await output.exists()) {
        final logs = await session.getOutput();
        throw Exception(logs?.trim().isEmpty ?? true
            ? 'Conversion impossible.'
            : logs!.trim());
      }

      await _mediaExport.saveAudioToGallery(output.path, outputName);
      final imported = await state.importAudioFile(
        filePath: output.path,
        displayName: baseName,
        triggerSource: AppState.mp4ToMp3AudioSource,
      );
      if (!mounted) return;
      setState(() {
        _lastOutputName = outputName;
        if (imported != null) {
          _convertedRecordingIds
            ..remove(imported.id)
            ..insert(0, imported.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('MP3 ajouté au téléphone.')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Conversion impossible : $message')),
      );
    } finally {
      if (mounted) setState(() => _converting = false);
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

  String _safeName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'audio_converti' : cleaned;
  }
}
