import 'package:audio_recorder/models/friend_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('friend profile exposes its public username', () {
    final profile = FriendProfile.fromJson({
      'id': 'friend-1',
      'username': 'fabio.audio',
      'display_name': 'Fabio',
    });

    expect(profile.username, 'fabio.audio');
    expect(profile.email, isEmpty);
  });

  test('folder share keeps its collaboration mode', () {
    final share = FolderShare.fromJson({
      'id': 'share-1',
      'folder_id': 'folder-1',
      'owner_id': 'owner-1',
      'recipient_id': 'friend-1',
      'folder_name': 'Projet',
      'mode': 'live',
      'created_at': '2026-10-02T12:00:00Z',
    });

    expect(share.mode, FolderShareMode.live);
    expect(share.isOwner('owner-1'), isTrue);
    expect(share.isOwner('friend-1'), isFalse);
  });

  test('audio message is decoded with its private storage path', () {
    final message = FriendMessage.fromJson({
      'id': 'message-1',
      'sender_id': 'owner-1',
      'receiver_id': 'friend-1',
      'kind': 'audio',
      'audio_path': 'owner-1/message-1.m4a',
      'created_at': '2026-10-02T12:00:00Z',
    });

    expect(message.kind, FriendMessageKind.audio);
    expect(message.audioPath, 'owner-1/message-1.m4a');
  });

  test('snapshot recording preserves the shared metadata', () {
    final recording = SharedRecording.fromSnapshotRow({
      'source_recording_id': 'recording-1',
      'source_owner_id': 'owner-1',
      'display_name': 'Réunion',
      'storage_path': 'owner-1/recording-1.m4a',
      'duration_ms': 61000,
      'recorded_at': '2026-10-02T12:00:00Z',
    });

    expect(recording.displayName, 'Réunion');
    expect(recording.duration, const Duration(seconds: 61));
  });
}
