import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/recording_model.dart';
import '../models/secure_folder_model.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';
import 'recordings_screen.dart';

class FoldersScreen extends StatelessWidget {
  const FoldersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final favorites = state.recordings.where((r) => r.isFavorite).toList();
        final enriched = state.recordings
            .where((r) => r.transcription != null || r.summary != null)
            .toList();
        final imported = state.recordings
            .where((r) => r.triggerSource == AppState.importedAudioSource)
            .toList();
        final mp4ToMp3 = state.recordings
            .where((r) => r.triggerSource == AppState.mp4ToMp3AudioSource)
            .toList();
        final recorded = state.recordings
            .where((r) =>
                r.triggerSource != AppState.importedAudioSource &&
                r.triggerSource != AppState.mp4ToMp3AudioSource)
            .toList();

        return Scaffold(
          backgroundColor: AppTheme.background,
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showCreateFolder(context, state),
            icon: const Icon(Icons.create_new_folder_rounded),
            label: const Text('Créer'),
          ),
          body: SafeArea(
            top: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dossiers',
                        style: TextStyle(
                          color: AppTheme.text,
                          fontSize: 27,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Favoris, transcriptions et dossiers protégés.',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: GridView.count(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 112),
                    crossAxisCount: 3,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.82,
                    children: [
                      _SmartFolderCard(
                        icon: Icons.star_rounded,
                        title: 'Favoris',
                        recordings: favorites,
                      ),
                      _SmartFolderCard(
                        icon: Icons.notes_rounded,
                        title: 'Transcrits\nrésumés',
                        recordings: enriched,
                      ),
                      _SmartFolderCard(
                        icon: Icons.mic_rounded,
                        title: 'Audios\nenregistrés',
                        recordings: recorded,
                      ),
                      _SmartFolderCard(
                        icon: Icons.file_upload_rounded,
                        title: 'Audios\nimportés',
                        recordings: imported,
                      ),
                      _SmartFolderCard(
                        icon: Icons.transform_rounded,
                        title: 'MP4 vers\nMP3',
                        recordings: mp4ToMp3,
                      ),
                      ...state.folders.map(
                        (folder) => _FolderCard(folder: folder),
                      ),
                      _EmptyFolderCard(
                        onTap: () => _showCreateFolder(context, state),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCreateFolder(BuildContext context, AppState state) async {
    final nameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var usePassword = false;

    final result = await showModalBottomSheet<_FolderDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nouveau dossier',
                  style: TextStyle(
                    color: AppTheme.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameCtrl,
                  style: const TextStyle(color: AppTheme.text),
                  decoration:
                      const InputDecoration(labelText: 'Nom du dossier'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Nom requis'
                      : null,
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: usePassword,
                  activeThumbColor: AppTheme.primary,
                  title: const Text(
                    'Protéger par mot de passe',
                    style: TextStyle(color: AppTheme.text),
                  ),
                  onChanged: (value) =>
                      setSheetState(() => usePassword = value),
                ),
                if (usePassword) ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: passwordCtrl,
                    obscureText: true,
                    style: const TextStyle(color: AppTheme.text),
                    decoration:
                        const InputDecoration(labelText: 'Mot de passe'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Mot de passe requis'
                        : null,
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(
                        ctx,
                        _FolderDraft(
                          name: nameCtrl.text,
                          pin: usePassword ? passwordCtrl.text : null,
                        ),
                      );
                    },
                    child: const Text('Créer le dossier'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    nameCtrl.dispose();
    passwordCtrl.dispose();

    if (result == null) return;
    await state.createFolder(name: result.name, pin: result.pin);
  }
}

class _FolderDraft {
  final String name;
  final String? pin;

  const _FolderDraft({required this.name, this.pin});
}

class _SmartFolderCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<RecordingModel> recordings;
  const _SmartFolderCard({
    required this.icon,
    required this.title,
    required this.recordings,
  });

  @override
  Widget build(BuildContext context) {
    return _FolderGridTile(
      icon: icon,
      title: title,
      count: recordings.length,
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              FolderListScreen(title: title, recordings: recordings),
        ),
      ),
    );
  }
}

class _FolderCard extends StatelessWidget {
  final SecureFolderModel folder;
  const _FolderCard({required this.folder});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return _FolderGridTile(
      icon: folder.hasPin ? Icons.folder_special_rounded : Icons.folder_rounded,
      title: folder.name,
      count: state.recordingsForFolder(folder.id).length,
      onTap: () => _open(context, state),
      onLongPress: () => _confirmDelete(context, state),
    );
  }

  Future<void> _open(BuildContext context, AppState state) async {
    if (!folder.hasPin) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FolderDetailScreen(folderId: folder.id),
        ),
      );
      return;
    }

    final pinCtrl = TextEditingController();
    final unlocked = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Mot de passe',
          style: TextStyle(color: AppTheme.text),
        ),
        content: TextField(
          controller: pinCtrl,
          obscureText: true,
          autofocus: true,
          style: const TextStyle(color: AppTheme.text),
          decoration: const InputDecoration(labelText: 'Mot de passe'),
          onSubmitted: (_) => Navigator.pop(
            ctx,
            state.verifyFolderPin(folder.id, pinCtrl.text),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              state.verifyFolderPin(folder.id, pinCtrl.text),
            ),
            child: const Text('Ouvrir'),
          ),
        ],
      ),
    );
    pinCtrl.dispose();

    if (!context.mounted) return;
    if (unlocked == true) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FolderDetailScreen(folderId: folder.id),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mot de passe incorrect.')),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Supprimer ce dossier ?',
          style: TextStyle(color: AppTheme.text),
        ),
        content: const Text(
          'Les audios restent disponibles, ils seront seulement retirés du dossier.',
          style: TextStyle(color: AppTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.deleteFolder(folder.id);
  }
}

class _FolderGridTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _FolderGridTile({
    required this.icon,
    required this.title,
    required this.count,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.line.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppTheme.text, size: 30),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                height: 1.08,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$count audio',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFolderCard extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyFolderCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.line.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.create_new_folder_outlined,
              color: AppTheme.textMuted.withValues(alpha: 0.65),
              size: 28,
            ),
            const SizedBox(height: 10),
            const Text(
              'Nouveau',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class FolderDetailScreen extends StatelessWidget {
  final String folderId;
  const FolderDetailScreen({super.key, required this.folderId});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    SecureFolderModel? folder;
    for (final item in state.folders) {
      if (item.id == folderId) {
        folder = item;
        break;
      }
    }
    if (folder == null) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Text(
            'Dossier introuvable',
            style: TextStyle(color: AppTheme.textMuted),
          ),
        ),
      );
    }
    return FolderListScreen(
      title: folder.name,
      recordings: state.recordingsForFolder(folderId),
      folderId: folderId,
    );
  }
}

class FolderListScreen extends StatelessWidget {
  final String title;
  final String? folderId;
  final List<RecordingModel> recordings;
  const FolderListScreen({
    super.key,
    required this.title,
    required this.recordings,
    this.folderId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.text,
        title: Text(title),
      ),
      body: recordings.isEmpty
          ? const _EmptyFolderDetail()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              itemCount: recordings.length,
              itemBuilder: (_, index) => RecordingCard(
                recording: recordings[index],
                removableFromFolder: folderId != null,
              ),
            ),
    );
  }
}

class _EmptyFolderDetail extends StatelessWidget {
  const _EmptyFolderDetail();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'Aucun audio dans ce dossier.',
        style: TextStyle(color: AppTheme.textMuted),
      ),
    );
  }
}
