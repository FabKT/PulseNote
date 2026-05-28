import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/api_config.dart';
import 'api_auth.dart';

class TranscriptionService {
  Future<String> transcribeAudio(String filePath) async {
    if (ApiConfig.isConfigured) {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Fichier audio introuvable.');
      }
      final size = await file.length();
      if (size <= 44) {
        throw Exception('Fichier audio vide ou invalide.');
      }

      await _wakeBackend();
      return _transcribeWithRetry(filePath);
    }

    await Future.delayed(const Duration(seconds: 2));
    final fileName = filePath.split(RegExp(r'[/\\]')).last;
    return '[ Transcription simulée ]\n\n'
        'Ceci représente le contenu transcrit de "$fileName".\n\n'
        'Configurez BACKEND_BASE_URL au build pour utiliser le backend réel.';
  }

  Future<String> _transcribeWithRetry(String filePath) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _sendTranscriptionRequest(filePath);
      } on TimeoutException {
        // Retry once below.
      } on SocketException {
        // Retry once below.
      } on http.ClientException {
        // Retry once below.
      }

      if (attempt == 0) {
        await Future.delayed(const Duration(seconds: 2));
        await _wakeBackend();
      }
    }

    throw Exception(
      'Connexion interrompue pendant l envoi audio. '
      'Vérifiez votre réseau, gardez l app ouverte, puis réessayez.',
    );
  }

  Future<String> _sendTranscriptionRequest(String filePath) async {
    final client = http.Client();
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.backendBaseUrl}/transcribe'),
      );
      request.headers.addAll(await ApiAuth.headers());
      request.headers['Connection'] = 'close';
      request.files.add(await http.MultipartFile.fromPath(
        'audio',
        filePath,
        filename: _fileName(filePath),
        contentType: _audioContentType(filePath),
      ));

      final streamed =
          await client.send(request).timeout(const Duration(minutes: 20));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['text'] as String? ?? '';
      }
      throw Exception(_errorFromResponse(
        response.body,
        fallback: 'Transcription impossible (${response.statusCode}).',
      ));
    } finally {
      client.close();
    }
  }

  Future<void> _wakeBackend() async {
    try {
      await http
          .get(Uri.parse('${ApiConfig.backendBaseUrl}/health'))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      // The transcription request below will surface the real failure if needed.
    }
  }

  String _errorFromResponse(String body, {required String fallback}) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final details = json['details'];
      if (details is Map<String, dynamic>) {
        final message = details['message'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
      final error = json['error'];
      if (error is String && error.trim().isNotEmpty) return error.trim();
    } catch (_) {
      // Keep the fallback below.
    }
    return fallback;
  }

  String _fileName(String filePath) => filePath.split(RegExp(r'[/\\]')).last;

  MediaType _audioContentType(String filePath) {
    final extension = filePath.split('.').last.toLowerCase();
    return switch (extension) {
      'wav' => MediaType('audio', 'wav'),
      'mp3' => MediaType('audio', 'mpeg'),
      'm4a' => MediaType('audio', 'mp4'),
      'aac' => MediaType('audio', 'aac'),
      'ogg' => MediaType('audio', 'ogg'),
      'flac' => MediaType('audio', 'flac'),
      _ => MediaType('application', 'octet-stream'),
    };
  }
}
