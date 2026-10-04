enum FriendRequestStatus { pending, accepted, declined }

enum FriendMessageKind { text, audio, folder }

enum FolderShareMode { live, snapshot }

class FriendProfile {
  final String id;
  final String email;
  final String username;
  final String displayName;
  final String? avatarUrl;

  const FriendProfile({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.avatarUrl,
  });

  factory FriendProfile.fromJson(Map<String, dynamic> json) => FriendProfile(
        id: json['id'] as String,
        email: json['email'] as String? ?? '',
        username: json['username'] as String? ?? '',
        displayName: json['display_name'] as String? ?? 'Utilisateur',
        avatarUrl: json['avatar_url'] as String?,
      );
}

class FriendRequest {
  final String id;
  final FriendProfile profile;
  final bool incoming;
  final FriendRequestStatus status;
  final DateTime createdAt;

  const FriendRequest({
    required this.id,
    required this.profile,
    required this.incoming,
    required this.status,
    required this.createdAt,
  });
}

class FriendMessage {
  final String id;
  final String senderId;
  final String receiverId;
  final FriendMessageKind kind;
  final String? body;
  final String? audioPath;
  final String? folderShareId;
  final DateTime createdAt;

  const FriendMessage({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.kind,
    required this.createdAt,
    this.body,
    this.audioPath,
    this.folderShareId,
  });

  factory FriendMessage.fromJson(Map<String, dynamic> json) => FriendMessage(
        id: json['id'] as String,
        senderId: json['sender_id'] as String,
        receiverId: json['receiver_id'] as String,
        kind: FriendMessageKind.values.firstWhere(
          (value) => value.name == json['kind'],
          orElse: () => FriendMessageKind.text,
        ),
        body: json['body'] as String?,
        audioPath: json['audio_path'] as String?,
        folderShareId: json['folder_share_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class FolderShare {
  final String id;
  final String folderId;
  final String ownerId;
  final String recipientId;
  final String folderName;
  final FolderShareMode mode;
  final DateTime createdAt;

  const FolderShare({
    required this.id,
    required this.folderId,
    required this.ownerId,
    required this.recipientId,
    required this.folderName,
    required this.mode,
    required this.createdAt,
  });

  bool isOwner(String userId) => ownerId == userId;

  factory FolderShare.fromJson(Map<String, dynamic> json) => FolderShare(
        id: json['id'] as String,
        folderId: json['folder_id'] as String,
        ownerId: json['owner_id'] as String,
        recipientId: json['recipient_id'] as String,
        folderName: json['folder_name'] as String,
        mode: FolderShareMode.values.firstWhere(
          (value) => value.name == json['mode'],
          orElse: () => FolderShareMode.snapshot,
        ),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

class SharedRecording {
  final String id;
  final String displayName;
  final String? storagePath;
  final Duration? duration;
  final DateTime createdAt;
  final String ownerId;

  const SharedRecording({
    required this.id,
    required this.displayName,
    required this.createdAt,
    required this.ownerId,
    this.storagePath,
    this.duration,
  });

  factory SharedRecording.fromRecordingRow(Map<String, dynamic> json) =>
      SharedRecording(
        id: json['id'] as String,
        displayName: json['display_name'] as String? ?? 'Audio partagé',
        storagePath: json['storage_path'] as String?,
        duration: json['duration_ms'] == null
            ? null
            : Duration(milliseconds: json['duration_ms'] as int),
        createdAt: DateTime.parse(json['created_at'] as String),
        ownerId: json['user_id'] as String,
      );

  factory SharedRecording.fromSnapshotRow(Map<String, dynamic> json) =>
      SharedRecording(
        id: json['source_recording_id'] as String,
        displayName: json['display_name'] as String? ?? 'Audio partagé',
        storagePath: json['storage_path'] as String?,
        duration: json['duration_ms'] == null
            ? null
            : Duration(milliseconds: json['duration_ms'] as int),
        createdAt: DateTime.parse(json['recorded_at'] as String),
        ownerId: json['source_owner_id'] as String,
      );
}
