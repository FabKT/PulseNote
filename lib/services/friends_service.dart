import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/api_config.dart';
import '../config/supabase_config.dart';
import '../models/friend_models.dart';
import '../models/recording_model.dart';
import '../models/secure_folder_model.dart';
import 'api_auth.dart';

class FriendsService {
  FriendsService._();

  static SupabaseClient get _client => Supabase.instance.client;
  static User get _user {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Connexion requise.');
    return user;
  }

  static String get currentUserId => _user.id;

  static Future<void> ensureProfile() async {
    final user = _user;
    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final displayName =
        (metadata['full_name'] ?? metadata['name'])?.toString().trim();
    final profile = {
      'id': user.id,
      'email': user.email?.trim().toLowerCase() ?? '',
      'display_name': displayName?.isNotEmpty == true
          ? displayName
          : user.email?.split('@').first ?? 'Utilisateur',
      'avatar_url': (metadata['avatar_url'] ?? metadata['picture'])?.toString(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    final existing = await _client
        .from('profiles')
        .select('id')
        .eq('id', user.id)
        .maybeSingle();
    if (existing == null) {
      await _client.from('profiles').insert({
        ...profile,
        'username': _defaultUsername(user),
      });
    } else {
      await _client.from('profiles').update(profile).eq('id', user.id);
    }
  }

  static String _defaultUsername(User user) {
    final raw = (user.email?.split('@').first ?? 'utilisateur').toLowerCase();
    var base = raw.replaceAll(RegExp(r'[^a-z0-9._]'), '');
    if (base.length < 3) base = 'utilisateur';
    if (base.length > 16) base = base.substring(0, 16);
    return '${base}_${user.id.replaceAll('-', '').substring(0, 6)}';
  }

  static Future<FriendProfile> myProfile() async {
    await ensureProfile();
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', currentUserId)
        .single();
    return FriendProfile.fromJson(row);
  }

  static Future<FriendProfile> updateUsername(String username) async {
    final normalized = username.trim().toLowerCase().replaceFirst('@', '');
    final row = await _client.rpc(
      'set_my_username',
      params: {'p_username': normalized},
    );
    return FriendProfile.fromJson(Map<String, dynamic>.from(row as Map));
  }

  static Future<List<FriendProfile>> friends() async {
    final rows = await _client.rpc('list_friends');
    return List<Map<String, dynamic>>.from(rows as List)
        .map(FriendProfile.fromJson)
        .toList();
  }

  static Future<FriendProfile?> findByUsername(String username) async {
    final rows = await _client.rpc(
      'find_profile_by_username',
      params: {
        'p_username': username.trim().toLowerCase().replaceFirst('@', ''),
      },
    );
    final list = List<Map<String, dynamic>>.from(rows as List);
    return list.isEmpty ? null : FriendProfile.fromJson(list.first);
  }

  static Future<void> sendFriendRequest(String receiverId) async {
    await _client.from('friend_requests').insert({
      'sender_id': currentUserId,
      'receiver_id': receiverId,
    });
  }

  static Future<List<FriendRequest>> requests() async {
    final rows = List<Map<String, dynamic>>.from(
      await _client.rpc('list_friend_requests') as List,
    );
    return rows
        .map(
          (row) => FriendRequest(
            id: row['request_id'] as String,
            profile: FriendProfile.fromJson({
              'id': row['profile_id'],
              'email': row['email'],
              'username': row['username'],
              'display_name': row['display_name'],
              'avatar_url': row['avatar_url'],
            }),
            incoming: row['incoming'] as bool,
            status: FriendRequestStatus.values.firstWhere(
              (value) => value.name == row['status'],
              orElse: () => FriendRequestStatus.pending,
            ),
            createdAt: DateTime.parse(row['created_at'] as String),
          ),
        )
        .toList();
  }

  static Future<void> answerRequest(String requestId, bool accept) async {
    await _client.rpc(
      'answer_friend_request',
      params: {'p_request_id': requestId, 'p_accept': accept},
    );
  }

  static Stream<List<FriendMessage>> messages(String friendId) {
    return _client
        .from('friend_messages')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map(
          (rows) => rows
              .where(
                (row) =>
                    (row['sender_id'] == currentUserId &&
                        row['receiver_id'] == friendId) ||
                    (row['sender_id'] == friendId &&
                        row['receiver_id'] == currentUserId),
              )
              .map(FriendMessage.fromJson)
              .toList(),
        );
  }

  static Future<void> sendText(String friendId, String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    await _client.from('friend_messages').insert({
      'sender_id': currentUserId,
      'receiver_id': friendId,
      'kind': FriendMessageKind.text.name,
      'body': clean,
    });
  }

  static Future<void> sendAudio(String friendId, File file) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final ext = file.path.contains('.') ? file.path.split('.').last : 'm4a';
    final path = '$currentUserId/$id.$ext';
    await _client.storage.from('friend-audio').upload(path, file);
    try {
      await _client.from('friend_messages').insert({
        'sender_id': currentUserId,
        'receiver_id': friendId,
        'kind': FriendMessageKind.audio.name,
        'audio_path': path,
      });
    } catch (_) {
      await _client.storage.from('friend-audio').remove([path]);
      rethrow;
    }
  }

  static Future<File> downloadMessageAudio(FriendMessage message) async {
    final path = message.audioPath;
    if (path == null) throw StateError('Audio indisponible.');
    final bytes = await _client.storage.from('friend-audio').download(path);
    final dir = await getTemporaryDirectory();
    final ext = path.split('.').last;
    final file = File('${dir.path}/friend_${message.id}.$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<FolderShare> shareFolder({
    required String friendId,
    required SecureFolderModel folder,
    required FolderShareMode mode,
    required List<RecordingModel> recordings,
  }) async {
    final shareRow = await _client
        .from('folder_shares')
        .insert({
          'folder_id': folder.id,
          'owner_id': currentUserId,
          'recipient_id': friendId,
          'folder_name': folder.name,
          'mode': mode.name,
        })
        .select()
        .single();
    final share = FolderShare.fromJson(shareRow);

    if (mode == FolderShareMode.snapshot && recordings.isNotEmpty) {
      await _client.from('folder_share_items').insert(
            recordings
                .map(
                  (recording) => {
                    'share_id': share.id,
                    'source_recording_id': recording.id,
                    'source_owner_id': currentUserId,
                    'display_name': recording.displayName,
                    'storage_path': recording.storagePath,
                    'duration_ms': recording.duration?.inMilliseconds,
                    'recorded_at': recording.createdAt.toIso8601String(),
                  },
                )
                .toList(),
          );
    }

    await _client.from('friend_messages').insert({
      'sender_id': currentUserId,
      'receiver_id': friendId,
      'kind': FriendMessageKind.folder.name,
      'body': folder.name,
      'folder_share_id': share.id,
    });
    return share;
  }

  static Future<FolderShare> folderShare(String id) async {
    final row =
        await _client.from('folder_shares').select().eq('id', id).single();
    return FolderShare.fromJson(row);
  }

  static Future<List<FolderShare>> sharedFolders() async {
    final rows = await _client
        .from('folder_shares')
        .select()
        .or('owner_id.eq.$currentUserId,recipient_id.eq.$currentUserId')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List)
        .map(FolderShare.fromJson)
        .toList();
  }

  // Partages d'un de mes dossiers. Liste vide si personne n'est connecte :
  // sans compte, aucun dossier ne peut etre partage.
  static Future<List<FolderShare>> sharesOfMyFolder(String folderId) async {
    if (!SupabaseConfig.isConfigured) return const [];
    final user = _client.auth.currentUser;
    if (user == null) return const [];
    final rows = await _client
        .from('folder_shares')
        .select()
        .eq('folder_id', folderId)
        .eq('owner_id', user.id);
    return List<Map<String, dynamic>>.from(rows as List)
        .map(FolderShare.fromJson)
        .toList();
  }

  // Un dossier partage ne se supprime pas, il se quitte. Le backend donne a
  // l'autre partie une copie independante de son contenu avant de retirer le
  // partage (voir POST /shares/:id/leave). Quand le proprietaire quitte, tous
  // les partages du dossier prennent fin.
  static Future<void> leaveSharedFolder(FolderShare share) async {
    if (!ApiConfig.isConfigured) {
      throw StateError('Backend de production non configuré.');
    }
    final response = await http
        .post(
          Uri.parse('${ApiConfig.backendBaseUrl}/shares/${share.id}/leave'),
          headers: await ApiAuth.headers(),
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Impossible de quitter ce dossier.';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['error'] is String) message = body['error'];
      } catch (_) {}
      throw StateError(message);
    }
  }

  static Future<List<SharedRecording>> sharedRecordings(
    FolderShare share,
  ) async {
    if (share.mode == FolderShareMode.live) {
      final rows = await _client
          .from('recordings')
          .select()
          .eq('folder_id', share.folderId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(rows as List)
          .map(SharedRecording.fromRecordingRow)
          .toList();
    }
    final rows = await _client
        .from('folder_share_items')
        .select()
        .eq('share_id', share.id)
        .order('recorded_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows as List)
        .map(SharedRecording.fromSnapshotRow)
        .toList();
  }

  static Future<File> downloadSharedRecording(SharedRecording recording) async {
    final path = recording.storagePath;
    if (path == null) throw StateError('Fichier audio indisponible.');
    final bytes = await _client.storage.from('recordings-audio').download(path);
    final dir = await getTemporaryDirectory();
    final ext = path.split('.').last;
    final file = File('${dir.path}/shared_${recording.id}.$ext');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static Future<void> addRecordingToLiveFolder({
    required FolderShare share,
    required RecordingModel recording,
  }) async {
    if (share.mode != FolderShareMode.live) {
      throw StateError('Ce dossier est un partage individuel.');
    }
    final source = File(recording.filePath);
    if (!await source.exists()) throw StateError('Fichier audio introuvable.');
    final id = '${currentUserId}_${DateTime.now().microsecondsSinceEpoch}';
    final ext = recording.filePath.contains('.')
        ? recording.filePath.split('.').last
        : 'm4a';
    final storagePath = '$currentUserId/$id.$ext';
    await _client.storage.from('recordings-audio').upload(storagePath, source);
    await _client.from('recordings').insert({
      'id': id,
      'user_id': currentUserId,
      'storage_path': storagePath,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'duration_ms': recording.duration?.inMilliseconds,
      'trigger_source': 'friend_share',
      'waveform': recording.waveform,
      'display_name': recording.displayName,
      'is_favorite': false,
      'folder_id': share.folderId,
      'transcription': recording.transcription,
      'summary': recording.summary,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
