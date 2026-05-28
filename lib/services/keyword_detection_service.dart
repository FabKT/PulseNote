import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

import '../models/keyword_model.dart';

class KeywordDetectionService {
  final SpeechToText _speech = SpeechToText();
  bool _active = false;
  bool _initialized = false;
  bool _restartScheduled = false;
  List<KeywordModel> _keywords = [];
  void Function(String keyword)? _onDetected;
  void Function(String text)? _onRecognizedText;
  void Function(String error)? _onError;

  bool get isActive => _active;

  Future<bool> startListening({
    required List<KeywordModel> keywords,
    required void Function(String keyword) onDetected,
    void Function(String text)? onRecognizedText,
    void Function(String error)? onError,
  }) async {
    if (_active) return true;

    _keywords = keywords.where((k) => k.text.trim().isNotEmpty).toList();
    if (_keywords.isEmpty) return false;

    _onDetected = onDetected;
    _onRecognizedText = onRecognizedText;
    _onError = onError;

    if (!_initialized) {
      _initialized = await _speech.initialize(
        onStatus: _onStatus,
        onError: (error) {
          _onError?.call(error.errorMsg);
          if (_active && !error.permanent) _scheduleRestart();
        },
      );
    }

    if (!_initialized) {
      _onError?.call('Reconnaissance vocale indisponible sur cet appareil.');
      _clearSession();
      return false;
    }

    _active = true;
    _startListenCycle();
    return true;
  }

  Future<void> stop() async {
    _active = false;
    _restartScheduled = false;
    _clearSession();
    await _speech.cancel();
  }

  void _startListenCycle() {
    if (!_active || _speech.isListening) return;
    _speech.listen(
      onResult: (result) {
        if (!_active) return;
        _onRecognizedText?.call(result.recognizedWords);
        _checkForKeywords(result.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        cancelOnError: false,
        partialResults: true,
        onDevice: false,
        listenMode: ListenMode.dictation,
        listenFor: const Duration(seconds: 10),
        pauseFor: const Duration(seconds: 3),
        localeId: 'fr_FR',
      ),
    );
  }

  void _onStatus(String status) {
    if (!_active) return;
    if (status == 'done' || status == 'notListening') {
      _scheduleRestart();
    }
  }

  void _checkForKeywords(String recognizedText) {
    final text = _normalize(recognizedText);
    if (text.isEmpty) return;

    for (final kw in _keywords) {
      final target = _normalize(kw.text);
      if (target.isEmpty) continue;
      if (text.contains(target)) {
        _triggerDetection(kw.text);
        return;
      }
    }
  }

  void _triggerDetection(String keyword) {
    final callback = _onDetected;
    stop().then((_) => callback?.call(keyword));
  }

  void _scheduleRestart() {
    if (_restartScheduled) return;
    _restartScheduled = true;
    Future.delayed(const Duration(milliseconds: 450), () {
      _restartScheduled = false;
      _startListenCycle();
    });
  }

  void _clearSession() {
    _onDetected = null;
    _onRecognizedText = null;
    _onError = null;
    _keywords = [];
  }

  String _normalize(String value) {
    var text = value.trim().toLowerCase();
    const replacements = {
      'à': 'a',
      '?': 'a',
      'ä': 'a',
      'ç': 'c',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'î': 'i',
      'ï': 'i',
      'ô': 'o',
      'ö': 'o',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
    };
    replacements.forEach((from, to) => text = text.replaceAll(from, to));
    return text;
  }
}
