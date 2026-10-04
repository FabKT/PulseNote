import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../models/friend_models.dart';
import '../models/recording_model.dart';
import '../models/secure_folder_model.dart';
import '../services/friends_service.dart';
import '../state/app_state.dart';
import '../ui/app_theme.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  bool _loading = true;
  String? _error;
  List<FriendProfile> _friends = const [];
  List<FriendRequest> _requests = const [];
  List<FolderShare> _shares = const [];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    try {
      await FriendsService.ensureProfile();
      final values = await Future.wait([
        FriendsService.friends(),
        FriendsService.requests(),
        FriendsService.sharedFolders(),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = values[0] as List<FriendProfile>;
        _requests = values[1] as List<FriendRequest>;
        _shares = values[2] as List<FolderShare>;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: AppTheme.background,
          foregroundColor: AppTheme.text,
          title: const Text('Amis'),
          actions: [
            IconButton(
              onPressed: _showAddFriend,
              tooltip: 'Ajouter un ami',
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Amis'),
              Tab(text: 'Demandes'),
              Tab(text: 'Dossiers'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onRetry: _refresh)
                : TabBarView(
                    children: [
                      _FriendsTab(friends: _friends),
                      _RequestsTab(requests: _requests, onChanged: _refresh),
                      _SharedFoldersTab(shares: _shares, onChanged: _refresh),
                    ],
                  ),
      ),
    );
  }

  Future<void> _showAddFriend() async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddFriendDialog(),
    );
    if (sent == true && mounted) {
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Demande envoyée.')),
        );
      }
    }
  }
}

class _AddFriendDialog extends StatefulWidget {
  const _AddFriendDialog();

  @override
  State<_AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<_AddFriendDialog> {
  final _controller = TextEditingController();
  bool _searching = false;
  bool _sending = false;
  FriendProfile? _result;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final username = _controller.text.trim().replaceFirst('@', '');
    if (!RegExp(r'^[a-zA-Z0-9._]{3,24}$').hasMatch(username)) {
      setState(() => _error =
          'Le nom d’utilisateur doit contenir 3 à 24 lettres, chiffres, points ou tirets bas.');
      return;
    }
    setState(() {
      _searching = true;
      _result = null;
      _error = null;
    });
    try {
      final profile = await FriendsService.findByUsername(username);
      if (!mounted) return;
      setState(() {
        _result = profile;
        if (profile == null) _error = 'Aucun utilisateur trouvé.';
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _send() async {
    final result = _result;
    if (result == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await FriendsService.sendFriendRequest(result.id);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = _friendlyError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _searching || _sending;
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Ajouter un ami'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Nom d’utilisateur',
                hintText: 'exemple_24',
                prefixText: '@',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
              onChanged: (_) {
                if (_result != null || _error != null) {
                  setState(() {
                    _result = null;
                    _error = null;
                  });
                }
              },
              onSubmitted: (_) {
                if (!busy) _search();
              },
            ),
            const SizedBox(height: 14),
            if (busy) const LinearProgressIndicator(),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppTheme.danger),
              ),
            ],
            if (_result != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _Avatar(profile: _result!),
                title: Text(_result!.displayName),
                subtitle: Text('@${_result!.username}'),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const Text('Annuler'),
        ),
        if (_result == null)
          FilledButton.icon(
            onPressed: busy ? null : _search,
            icon: const Icon(Icons.search_rounded),
            label: const Text('Rechercher'),
          )
        else
          FilledButton.icon(
            onPressed: busy ? null : _send,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Envoyer'),
          ),
      ],
    );
  }
}

class _FriendsTab extends StatelessWidget {
  final List<FriendProfile> friends;
  const _FriendsTab({required this.friends});

  @override
  Widget build(BuildContext context) {
    if (friends.isEmpty) {
      return const _EmptyState(
        icon: Icons.people_outline_rounded,
        title: 'Aucun ami pour le moment',
        subtitle: 'Ajoutez une personne avec son nom d’utilisateur.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      itemCount: friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final friend = friends[index];
        return Container(
          decoration: AppTheme.panel(radius: 12),
          child: ListTile(
            leading: _Avatar(profile: friend),
            title: Text(
              friend.displayName,
              style: const TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text('@${friend.username}'),
            trailing: const Icon(Icons.chat_bubble_outline_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ConversationScreen(friend: friend),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RequestsTab extends StatelessWidget {
  final List<FriendRequest> requests;
  final Future<void> Function() onChanged;
  const _RequestsTab({required this.requests, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const _EmptyState(
        icon: Icons.mark_email_read_outlined,
        title: 'Aucune demande',
        subtitle: 'Les invitations reçues et envoyées apparaîtront ici.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      itemCount: requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final request = requests[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: AppTheme.panel(radius: 12),
          child: Row(
            children: [
              _Avatar(profile: request.profile),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.profile.displayName,
                      style: const TextStyle(
                        color: AppTheme.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '@${request.profile.username} · '
                      '${request.incoming ? 'Invitation reçue' : 'Invitation envoyée'}',
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                  ],
                ),
              ),
              if (request.incoming) ...[
                IconButton(
                  tooltip: 'Refuser',
                  onPressed: () => _answer(context, request, false),
                  icon: const Icon(Icons.close_rounded, color: AppTheme.danger),
                ),
                IconButton.filled(
                  tooltip: 'Accepter',
                  onPressed: () => _answer(context, request, true),
                  icon: const Icon(Icons.check_rounded),
                ),
              ] else
                const Icon(Icons.schedule_rounded, color: AppTheme.textMuted),
            ],
          ),
        );
      },
    );
  }

  Future<void> _answer(
    BuildContext context,
    FriendRequest request,
    bool accept,
  ) async {
    try {
      await FriendsService.answerRequest(request.id, accept);
      await onChanged();
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    }
  }
}

class _SharedFoldersTab extends StatelessWidget {
  final List<FolderShare> shares;
  final VoidCallback onChanged;
  const _SharedFoldersTab({required this.shares, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    if (shares.isEmpty) {
      return const _EmptyState(
        icon: Icons.folder_shared_outlined,
        title: 'Aucun dossier partagé',
        subtitle: 'Partagez un dossier depuis une conversation.',
      );
    }
    final userId = FriendsService.currentUserId;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      itemCount: shares.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final share = shares[index];
        final live = share.mode == FolderShareMode.live;
        return Container(
          decoration: AppTheme.panel(radius: 12),
          child: ListTile(
            leading: Icon(
              live ? Icons.sync_rounded : Icons.content_copy_rounded,
              color: AppTheme.primary,
            ),
            title: Text(
              share.folderName,
              style: const TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              '${live ? 'Partage complet' : 'Partage individuel'} · '
              '${share.isOwner(userId) ? 'Envoyé' : 'Reçu'}',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final left = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => SharedFolderScreen(share: share),
                ),
              );
              if (left == true) onChanged();
            },
          ),
        );
      },
    );
  }
}

class ConversationScreen extends StatefulWidget {
  final FriendProfile friend;
  const ConversationScreen({super.key, required this.friend});

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _textController = TextEditingController();
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _sending = false;
  String? _recordingPath;

  @override
  void dispose() {
    _textController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.text,
        titleSpacing: 0,
        title: Row(
          children: [
            _Avatar(profile: widget.friend, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.friend.displayName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _sending ? null : _showShareFolder,
            tooltip: 'Partager un dossier',
            icon: const Icon(Icons.folder_shared_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<FriendMessage>>(
                stream: FriendsService.messages(widget.friend.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _ErrorState(
                      message: _friendlyError(snapshot.error!),
                      onRetry: () => setState(() {}),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final messages = snapshot.data!;
                  if (messages.isEmpty) {
                    return const _EmptyState(
                      icon: Icons.chat_bubble_outline_rounded,
                      title: 'Nouvelle conversation',
                      subtitle: 'Envoyez un message, un audio ou un dossier.',
                    );
                  }
                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[messages.length - 1 - index];
                      return _MessageBubble(
                        message: message,
                        mine: message.senderId == FriendsService.currentUserId,
                      );
                    },
                  );
                },
              ),
            ),
            if (_recording)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PulseDot(),
                    SizedBox(width: 8),
                    Text(
                      'Enregistrement en cours',
                      style: TextStyle(color: AppTheme.danger),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border: Border(top: BorderSide(color: AppTheme.line)),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _sending ? null : _toggleRecording,
                    tooltip: _recording ? 'Envoyer l’audio' : 'Message audio',
                    style: IconButton.styleFrom(
                      backgroundColor:
                          _recording ? AppTheme.danger : AppTheme.surfaceHigh,
                    ),
                    icon: Icon(
                      _recording ? Icons.stop_rounded : Icons.mic_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Écrire un message',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _sendText,
                    tooltip: 'Envoyer',
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendText() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    setState(() => _sending = true);
    try {
      await FriendsService.sendText(widget.friend.id, text);
      _textController.clear();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      final path = await _recorder.stop();
      if (mounted) setState(() => _recording = false);
      final finalPath = path ?? _recordingPath;
      if (finalPath == null) return;
      setState(() => _sending = true);
      try {
        await FriendsService.sendAudio(widget.friend.id, File(finalPath));
      } catch (error) {
        _showError(error);
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      return;
    }

    if (!await _recorder.hasPermission()) {
      _showError('Autorisation du microphone refusée.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/friend_message_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    if (mounted) {
      setState(() {
        _recordingPath = path;
        _recording = true;
      });
    }
  }

  Future<void> _showShareFolder() async {
    final state = context.read<AppState>();
    if (state.folders.isEmpty) {
      _showError('Créez d’abord un dossier à partager.');
      return;
    }
    final draft = await showModalBottomSheet<_ShareDraft>(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      builder: (context) => _ShareFolderSheet(folders: state.folders),
    );
    if (draft == null || !mounted) return;
    setState(() => _sending = true);
    try {
      await FriendsService.shareFolder(
        friendId: widget.friend.id,
        folder: draft.folder,
        mode: draft.mode,
        recordings: state.recordingsForFolder(draft.folder.id),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_friendlyError(error))),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final FriendMessage message;
  final bool mine;
  const _MessageBubble({required this.message, required this.mine});

  @override
  Widget build(BuildContext context) {
    final alignment = mine ? Alignment.centerRight : Alignment.centerLeft;
    final background = mine ? AppTheme.primaryDeep : AppTheme.surfaceHigh;
    return Align(
      alignment: alignment,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 310),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.kind == FriendMessageKind.text)
              Text(
                message.body ?? '',
                style: const TextStyle(color: AppTheme.text, fontSize: 15),
              )
            else if (message.kind == FriendMessageKind.audio)
              _AudioMessage(message: message)
            else
              _FolderMessage(message: message),
            const SizedBox(height: 5),
            Text(
              DateFormat('HH:mm').format(message.createdAt.toLocal()),
              style: TextStyle(
                color: AppTheme.text.withValues(alpha: 0.64),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioMessage extends StatefulWidget {
  final FriendMessage message;
  const _AudioMessage({required this.message});

  @override
  State<_AudioMessage> createState() => _AudioMessageState();
}

class _AudioMessageState extends State<_AudioMessage> {
  final _player = AudioPlayer();
  bool _loading = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _loading ? null : _toggle,
          icon: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        const Icon(Icons.graphic_eq_rounded, color: AppTheme.text, size: 44),
        const SizedBox(width: 6),
        const Text('Audio', style: TextStyle(color: AppTheme.text)),
      ],
    );
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      if (mounted) setState(() => _playing = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final file = await FriendsService.downloadMessageAudio(widget.message);
      await _player.play(DeviceFileSource(file.path));
      if (mounted) setState(() => _playing = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _FolderMessage extends StatelessWidget {
  final FriendMessage message;
  const _FolderMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: message.folderShareId == null
          ? null
          : () async {
              try {
                final share =
                    await FriendsService.folderShare(message.folderShareId!);
                if (context.mounted) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SharedFolderScreen(share: share),
                    ),
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(_friendlyError(error))),
                  );
                }
              }
            },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_shared_rounded, color: AppTheme.text),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message.body ?? 'Dossier partagé',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.text,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, size: 18),
        ],
      ),
    );
  }
}

class SharedFolderScreen extends StatefulWidget {
  final FolderShare share;
  const SharedFolderScreen({super.key, required this.share});

  @override
  State<SharedFolderScreen> createState() => _SharedFolderScreenState();
}

class _SharedFolderScreenState extends State<SharedFolderScreen> {
  final _player = AudioPlayer();
  bool _loading = true;
  List<SharedRecording> _recordings = const [];
  String? _playingId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
    _refresh();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final recordings = await FriendsService.sharedRecordings(widget.share);
      if (mounted) {
        setState(() {
          _recordings = recordings;
          _error = null;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = _friendlyError(error);
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.share.mode == FolderShareMode.live;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        foregroundColor: AppTheme.text,
        title: Text(widget.share.folderName),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            onPressed: () async {
              final left = await leaveSharedFolderFlow(context, widget.share);
              if (left && context.mounted) Navigator.pop(context, true);
            },
            tooltip: 'Quitter ce dossier',
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      floatingActionButton: live
          ? FloatingActionButton.extended(
              onPressed: _addRecording,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter un audio'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: AppTheme.panel(radius: 12),
              child: Row(
                children: [
                  Icon(
                    live ? Icons.sync_rounded : Icons.content_copy_rounded,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          live ? 'Partage complet' : 'Partage individuel',
                          style: const TextStyle(
                            color: AppTheme.text,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          live
                              ? 'Les nouveaux audios sont visibles par les deux personnes.'
                              : 'Cette copie reste indépendante des changements futurs.',
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorState(message: _error!, onRetry: _refresh)
                    : _recordings.isEmpty
                        ? const _EmptyState(
                            icon: Icons.audio_file_outlined,
                            title: 'Dossier vide',
                            subtitle: 'Aucun audio partagé pour le moment.',
                          )
                        : ListView.separated(
                            padding: EdgeInsets.fromLTRB(
                              20,
                              0,
                              20,
                              live ? 104 : 32,
                            ),
                            itemCount: _recordings.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final recording = _recordings[index];
                              return Container(
                                decoration: AppTheme.panel(radius: 12),
                                child: ListTile(
                                  leading: IconButton.filledTonal(
                                    onPressed: recording.storagePath == null
                                        ? null
                                        : () => _play(recording),
                                    icon: Icon(
                                      _playingId == recording.id
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                    ),
                                  ),
                                  title: Text(
                                    recording.displayName,
                                    style: const TextStyle(
                                      color: AppTheme.text,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${DateFormat('dd/MM/yyyy HH:mm').format(recording.createdAt.toLocal())}'
                                    '${recording.duration == null ? '' : ' · ${_formatDuration(recording.duration!)}'}',
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Future<void> _play(SharedRecording recording) async {
    if (_playingId == recording.id) {
      await _player.pause();
      setState(() => _playingId = null);
      return;
    }
    try {
      final file = await FriendsService.downloadSharedRecording(recording);
      await _player.play(DeviceFileSource(file.path));
      if (mounted) setState(() => _playingId = recording.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    }
  }

  Future<void> _addRecording() async {
    final recordings = context.read<AppState>().recordings;
    if (recordings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun audio disponible.')),
      );
      return;
    }
    final selected = await showModalBottomSheet<RecordingModel>(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Ajouter un audio',
                style: TextStyle(
                  color: AppTheme.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            ...recordings.map(
              (recording) => ListTile(
                leading: const Icon(Icons.audio_file_rounded),
                title: Text(recording.title),
                subtitle: Text(recording.triggerLabel),
                onTap: () => Navigator.pop(context, recording),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    try {
      await FriendsService.addRecordingToLiveFolder(
        share: widget.share,
        recording: selected,
      );
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    }
  }
}

class _ShareFolderSheet extends StatefulWidget {
  final List<SecureFolderModel> folders;
  const _ShareFolderSheet({required this.folders});

  @override
  State<_ShareFolderSheet> createState() => _ShareFolderSheetState();
}

class _ShareFolderSheetState extends State<_ShareFolderSheet> {
  late SecureFolderModel _folder = widget.folders.first;
  FolderShareMode _mode = FolderShareMode.live;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Partager un dossier',
              style: TextStyle(
                color: AppTheme.text,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<SecureFolderModel>(
              initialValue: _folder,
              decoration: const InputDecoration(labelText: 'Dossier'),
              items: widget.folders
                  .map(
                    (folder) => DropdownMenuItem(
                      value: folder,
                      child: Text(folder.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _folder = value);
              },
            ),
            const SizedBox(height: 14),
            SegmentedButton<FolderShareMode>(
              segments: const [
                ButtonSegment(
                  value: FolderShareMode.live,
                  icon: Icon(Icons.sync_rounded),
                  label: Text('Complet'),
                ),
                ButtonSegment(
                  value: FolderShareMode.snapshot,
                  icon: Icon(Icons.content_copy_rounded),
                  label: Text('Individuel'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (value) =>
                  setState(() => _mode = value.first),
            ),
            const SizedBox(height: 12),
            Text(
              _mode == FolderShareMode.live
                  ? 'Les ajouts futurs seront visibles par les deux personnes.'
                  : 'Une copie indépendante du contenu actuel sera partagée.',
              style: const TextStyle(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  _ShareDraft(folder: _folder, mode: _mode),
                ),
                icon: const Icon(Icons.folder_shared_rounded),
                label: const Text('Partager'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareDraft {
  final SecureFolderModel folder;
  final FolderShareMode mode;
  const _ShareDraft({required this.folder, required this.mode});
}

class _Avatar extends StatelessWidget {
  final FriendProfile profile;
  final double radius;
  const _Avatar({required this.profile, this.radius = 22});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.primaryDeep,
      backgroundImage:
          profile.avatarUrl == null ? null : NetworkImage(profile.avatarUrl!),
      child: profile.avatarUrl == null
          ? Text(
              profile.displayName.isEmpty
                  ? '?'
                  : profile.displayName[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.textMuted, size: 54),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.text,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                color: AppTheme.danger, size: 48),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 10,
      height: 10,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.danger,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// Un dossier partage ne se supprime pas : on le quitte, et l'autre partie en
// garde une copie independante. Renvoie true si le dossier a ete quitte.
Future<bool> leaveSharedFolderFlow(
  BuildContext context,
  FolderShare share,
) async {
  final isOwner = share.isOwner(FriendsService.currentUserId);
  final live = share.mode == FolderShareMode.live;
  final String message;
  if (isOwner) {
    message = 'Le dossier disparaîtra de votre bibliothèque. Vos audios '
        'restent disponibles, sans dossier. Les personnes avec qui il est '
        'partagé gardent une copie de son contenu.';
  } else if (live) {
    message = 'Vous n’aurez plus accès à ce dossier. Les audios que vous y '
        'avez ajoutés restent dans votre bibliothèque, et le propriétaire en '
        'garde une copie.';
  } else {
    message = 'Vous n’aurez plus accès à cette copie du dossier.';
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text(
        'Quitter « ${share.folderName} » ?',
        style: const TextStyle(color: AppTheme.text),
      ),
      content: Text(
        message,
        style: const TextStyle(color: AppTheme.textMuted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
          child: const Text('Quitter'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final state = context.read<AppState>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    await FriendsService.leaveSharedFolder(share);
    await state.detachFolderLocally(share.folderId);
    messenger.showSnackBar(
      SnackBar(content: Text('Vous avez quitté « ${share.folderName} ».')),
    );
    return true;
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text(_friendlyError(error))),
    );
    return false;
  }
}

String _friendlyError(Object error) {
  final text =
      error.toString().replaceFirst('PostgrestException(message: ', '');
  if (text.contains('relation') && text.contains('does not exist')) {
    return 'La mise à jour Supabase de la fonction Amis doit être appliquée.';
  }
  if (text.contains('find_profile_by_username') ||
      text.contains('set_my_username') ||
      text.contains('username')) {
    return 'La mise à jour des noms d’utilisateur doit être appliquée à Supabase.';
  }
  if (text.contains('duplicate key')) {
    return 'Cette demande existe déjà.';
  }
  if (text.contains('not authenticated') ||
      text.contains('Connexion requise')) {
    return 'Connectez-vous pour utiliser la fonction Amis.';
  }
  return text.length > 180 ? '${text.substring(0, 180)}…' : text;
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
