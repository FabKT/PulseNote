import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../config/api_config.dart';

class TranscriptionService {
  WebSocketChannel? _liveChannel;
  StreamSubscription<dynamic>? _liveSub;
  void Function(String delta)? _onLiveDelta;
  void Function(String transcript)? _onLiveCompleted;
  bool _liveReady = false;
  bool _liveFailed = false;
  String? _lastLiveError;

  String? get lastLiveError => _lastLiveError;

  void resetLiveSession() {
    _liveFailed = false;
    _liveReady = false;
    _lastLiveError = null;
  }

  Future<bool> startLiveSession({
    required void Function(String delta) onDelta,
    required void Function(String transcript) onCompleted,
  }) async {
    if (!ApiConfig.isConfigured) {
      _lastLiveError =
          'Backend non configure. Ajoutez BACKEND_BASE_URL et APP_CLIENT_TOKEN au lancement.';
      return false;
    }
    await stopLiveSession();
    resetLiveSession();
    _onLiveDelta = onDelta;
    _onLiveCompleted = onCompleted;

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.backendBaseUrl}/realtime/transcription-session'),
        headers: {'x-app-token': ApiConfig.appClientToken},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _lastLiveError = _errorFromResponse(
          response.body,
          fallback:
              'Session instantanee refusee par le backend (${response.statusCode}).',
        );
        return false;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final clientSecret = _readClientSecret(payload);
      if (clientSecret == null || clientSecret.isEmpty) {
        _lastLiveError = 'Le backend n a pas renvoye de client_secret.';
        return false;
      }

      final channel = IOWebSocketChannel.connect(
        Uri.parse('wss://api.openai.com/v1/realtime?intent=transcription'),
        headers: {'Authorization': 'Bearer $clientSecret'},
      );
      _liveChannel = channel;
      _liveSub = channel.stream.listen(
        _handleRealtimeEvent,
        onError: (error) {
          _liveFailed = true;
          _lastLiveError = 'Connexion OpenAI Realtime interrompue: $error';
        },
        onDone: () => _liveReady = false,
      );
      _liveReady = true;
      return true;
    } on TimeoutException {
      _lastLiveError = 'Delai depasse en contactant le backend.';
      await stopLiveSession();
      return false;
    } catch (error) {
      _lastLiveError =
          'Impossible de demarrer la transcription instantanee: $error';
      await stopLiveSession();
      return false;
    }
  }

  void appendLiveAudio(Uint8List pcm16Chunk) {
    if (!_liveReady || _liveFailed || pcm16Chunk.isEmpty) return;
    _liveChannel?.sink.add(jsonEncode({
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(pcm16Chunk),
    }));
  }

  Future<void> stopLiveSession() async {
    _liveReady = false;
    await _liveSub?.cancel();
    _liveSub = null;
    await _liveChannel?.sink.close();
    _liveChannel = null;
    _onLiveDelta = null;
    _onLiveCompleted = null;
  }

  Future<String> transcribeLiveSegment(Duration elapsed) async {
    await Future.delayed(const Duration(milliseconds: 220));
    final seconds = elapsed.inSeconds.toString().padLeft(2, '0');
    return '[$seconds s] Transcription instantanée indisponible. '
        'Vérifiez BACKEND_BASE_URL, APP_CLIENT_TOKEN et la connexion backend.';
  }

  Future<String> transcribeAudio(String filePath) async {
    if (ApiConfig.isConfigured) {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.backendBaseUrl}/transcribe'),
      );
      request.headers['x-app-token'] = ApiConfig.appClientToken;
      request.files.add(await http.MultipartFile.fromPath('audio', filePath));

      final streamed =
          await request.send().timeout(const Duration(seconds: 90));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['text'] as String? ?? '';
      }
      throw Exception(_errorFromResponse(
        response.body,
        fallback: 'Transcription impossible (${response.statusCode}).',
      ));
    }

    await Future.delayed(const Duration(seconds: 2));
    final fileName = filePath.split(RegExp(r'[/\\]')).last;
    return '[ Transcription simulée ]\n\n'
        'Ceci représente le contenu transcrit de "$fileName".\n\n'
        'Configurez BACKEND_BASE_URL et APP_CLIENT_TOKEN au build pour utiliser le backend réel.';
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

  String? _readClientSecret(Map<String, dynamic> payload) {
    final direct = payload['client_secret'];
    if (direct is Map<String, dynamic>) {
      final value = direct['value'];
      if (value is String) return value;
    }
    final session = payload['session'];
    if (session is Map<String, dynamic>) {
      final secret = session['client_secret'];
      if (secret is Map<String, dynamic>) {
        final value = secret['value'];
        if (value is String) return value;
      }
    }
    return null;
  }

  void _handleRealtimeEvent(dynamic raw) {
    if (raw is! String) return;
    final event = jsonDecode(raw) as Map<String, dynamic>;
    switch (event['type']) {
      case 'conversation.item.input_audio_transcription.delta':
        final delta = event['delta'];
        if (delta is String && delta.isNotEmpty) _onLiveDelta?.call(delta);
      case 'conversation.item.input_audio_transcription.completed':
        final transcript = event['transcript'];
        if (transcript is String && transcript.isNotEmpty) {
          _onLiveCompleted?.call(transcript);
        }
      case 'error':
        _liveFailed = true;
    }
  }
}
