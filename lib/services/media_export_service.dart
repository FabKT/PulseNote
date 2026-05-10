import 'package:flutter/services.dart';

class MediaExportService {
  static const _channel = MethodChannel('ultimate_audio_recorder/media_export');

  Future<String?> saveAudioToGallery(String filePath, String displayName) {
    return _channel.invokeMethod<String>('saveAudio', {
      'filePath': filePath,
      'displayName': displayName,
    });
  }
}
