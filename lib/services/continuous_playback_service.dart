import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../models/recording_model.dart';
import 'foreground_service.dart';

class ContinuousPlaybackService extends ChangeNotifier {
  ContinuousPlaybackService._();

  static final ContinuousPlaybackService instance =
      ContinuousPlaybackService._();

  final AudioPlayer _player = AudioPlayer();
  bool _configured = false;
  bool _locked = false;
  bool _foregroundStartedHere = false;
  bool _isPlaying = false;
  bool _loading = false;
  String? _recordingId;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  bool get locked => _locked;
  bool get isPlaying => _isPlaying;
  bool get loading => _loading;
  String? get recordingId => _recordingId;
  Duration get position => _position;
  Duration get duration => _duration;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    _configured = true;
    await _player.setPlayerMode(PlayerMode.mediaPlayer);
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          stayAwake: true,
          contentType: AndroidContentType.music,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
    });
    _player.onPositionChanged.listen((position) {
      _position = position;
      notifyListeners();
    });
    _player.onDurationChanged.listen((duration) {
      _duration = duration;
      notifyListeners();
    });
  }

  Future<void> setLocked(bool value) async {
    await _ensureConfigured();
    if (_locked == value) return;
    _locked = value;
    if (_locked) {
      if (!await ForegroundService.isRunning) {
        await ForegroundService.start();
        _foregroundStartedHere = true;
      }
      await ForegroundService.updateNotification(
        'Lecture continue active',
        'Un audio tourne en boucle en arriere-plan',
      );
    } else {
      if (_foregroundStartedHere && !_isPlaying) {
        await ForegroundService.stop();
        _foregroundStartedHere = false;
      }
    }
    notifyListeners();
  }

  Future<void> select(RecordingModel recording, {bool restart = false}) async {
    await _ensureConfigured();
    final changed = _recordingId != recording.id;
    _recordingId = recording.id;
    _duration = recording.duration ?? Duration.zero;
    if (changed || restart) {
      await _player.stop();
      _position = Duration.zero;
    }
    notifyListeners();
  }

  Future<void> toggle(RecordingModel recording) async {
    await _ensureConfigured();
    if (_isPlaying && _recordingId == recording.id) {
      await pause();
      return;
    }
    await play(recording);
  }

  Future<void> play(RecordingModel recording) async {
    await _ensureConfigured();
    final file = File(recording.filePath);
    if (!await file.exists()) {
      throw Exception('Fichier audio introuvable.');
    }

    _loading = true;
    notifyListeners();
    try {
      if (_recordingId != recording.id) {
        await select(recording, restart: true);
      }
      await _player.setReleaseMode(ReleaseMode.loop);
      if (_position > Duration.zero &&
          (_duration == Duration.zero || _position < _duration)) {
        await _player.resume();
      } else {
        _position = Duration.zero;
        await _player.play(
          DeviceFileSource(recording.filePath),
          mode: PlayerMode.mediaPlayer,
        );
      }
      if (_locked) {
        await ForegroundService.updateNotification(
          'Lecture continue active',
          recording.title,
        );
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> pause() => _player.pause();

  Future<void> seekByFraction(double fraction) async {
    await _ensureConfigured();
    if (_duration.inMilliseconds <= 0) return;
    await _player.seek(
      Duration(milliseconds: (_duration.inMilliseconds * fraction).round()),
    );
  }

  Future<void> stopIfUnlocked() async {
    await _ensureConfigured();
    if (_locked) return;
    await stop();
  }

  Future<void> stop() async {
    await _ensureConfigured();
    await _player.stop();
    _position = Duration.zero;
    if (_foregroundStartedHere) {
      await ForegroundService.stop();
      _foregroundStartedHere = false;
    }
    notifyListeners();
  }
}
