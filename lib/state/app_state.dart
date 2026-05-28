import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/billing_config.dart';
import '../models/audio_playback_schedule_model.dart';
import '../models/keyword_model.dart';
import '../models/recording_model.dart';
import '../models/schedule_model.dart';
import '../models/secure_folder_model.dart';
import '../services/audio_service.dart';
import '../services/foreground_service.dart';
import '../services/keyword_detection_service.dart';
import '../services/media_export_service.dart';
import '../services/purchase_service.dart';
import '../services/schedule_service.dart';
import '../services/transcription_service.dart';
import '../services/summary_service.dart';

// -?š' Machine à états de l'application -?š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š?
enum AppStatus { idle, sessionActive, listening, recording }

class AppState extends ChangeNotifier {
  // -?š' État courant -?š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š'
  AppStatus _status = AppStatus.idle;
  List<KeywordModel> _keywords = [];
  List<ScheduleModel> _schedules = [];
  List<RecordingModel> _recordings = [];
  List<SecureFolderModel> _folders = [];
  List<AudioPlaybackScheduleModel> _audioPlaybackSchedules = [];
  bool _isPremium = false;
  String? _currentRecordingPath;
  String _currentTriggerSource = 'manual';
  DateTime? _recordingStartTime;
  bool _recordingTransitionInProgress = false;
  String? _lastCreatedRecordingId;
  int _createdRecordingSignal = 0;

  // -?š' Services -?š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š'
  final AudioService _audio = AudioService();
  late final KeywordDetectionService _detector;
  final ScheduleService _scheduler = ScheduleService();
  final TranscriptionService _transcription = TranscriptionService();
  final SummaryService _summary = SummaryService();
  final MediaExportService _mediaExport = MediaExportService();
  final PurchaseService _purchase = PurchaseService();
  final AudioPlayer _scheduledAudioPlayer = AudioPlayer();
  Timer? _scheduleTimer;
  Timer? _amplitudeTimer;
  double _currentAudioLevel = 0;
  String _lastKeywordRecognitionText = '';
  String? _lastKeywordDetectionError;
  final List<double> _liveWaveform = [];
  final List<double> _recordingWaveform = [];

  // -?š' Getters publics -?š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š?
  AppStatus get status => _status;
  List<KeywordModel> get keywords => List.unmodifiable(_keywords);
  List<ScheduleModel> get schedules => List.unmodifiable(_schedules);
  List<RecordingModel> get recordings => List.unmodifiable(_recordings);
  List<SecureFolderModel> get folders => List.unmodifiable(_folders);
  List<AudioPlaybackScheduleModel> get audioPlaybackSchedules =>
      List.unmodifiable(_audioPlaybackSchedules);
  bool get isPremium => _isPremium;
  bool get purchaseAvailable => _purchase.available;
  bool get purchaseLoading => _purchase.loading;
  bool get purchasePending => _purchase.purchasePending;
  String? get purchaseError => _purchase.errorMessage;
  String get premiumPrice => _purchase.premiumPrice;
  int get freeRecordingLimit => 5;
  int get remainingFreeRecordings =>
      (_isPremium ? 999 : freeRecordingLimit - _recordings.length)
          .clamp(0, 999);
  bool get canEnableKeywordTrigger => _keywords.isNotEmpty;
  int get keywordCount => _keywords.length;
  double get currentAudioLevel => _currentAudioLevel;
  String get lastKeywordRecognitionText => _lastKeywordRecognitionText;
  String? get lastKeywordDetectionError => _lastKeywordDetectionError;
  List<double> get liveWaveform => List.unmodifiable(_liveWaveform);
  String? get lastCreatedRecordingId => _lastCreatedRecordingId;
  int get createdRecordingSignal => _createdRecordingSignal;
  static const int maxKeywords = 3;
  static const String importedAudioSource = 'imported';
  static const String mp4ToMp3AudioSource = 'mp4_to_mp3';

  Future<void> setPremiumEnabled(bool enabled) async {
    _isPremium = enabled;
    final p = await SharedPreferences.getInstance();
    await p.setBool(BillingConfig.premiumEntitlementKey, enabled);
    notifyListeners();
  }

  Future<void> buyPremium() => _purchase.buyPremium();

  Future<void> restorePremiumPurchase() => _purchase.restorePurchases();

  AppState() {
    _detector = KeywordDetectionService();
    _init();
  }

  Future<void> _init() async {
    await _loadAll();
    await _configureScheduledAudioPlayer();
    await _purchase.init(onPremiumUnlocked: () {
      setPremiumEnabled(true);
    });
    _purchase.addListener(notifyListeners);
    FlutterForegroundTask.addTaskDataCallback(_onForegroundTick);
    _startLocalTimer();
    notifyListeners();
  }

  Future<void> _configureScheduledAudioPlayer() async {
    await _scheduledAudioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
    await _scheduledAudioPlayer.setReleaseMode(ReleaseMode.stop);
    await _scheduledAudioPlayer.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          stayAwake: true,
          contentType: AndroidContentType.speech,
          usageType: AndroidUsageType.media,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
  }

  void _onForegroundTick(dynamic data) {
    if (data is Map && data['event'] == 'tick') _checkSchedules();
  }

  // -?š' Contrôle de session -?š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š?

  Future<void> startSession() async {
    if (_status != AppStatus.idle) return;
    if (!await _audio.requestPermissions()) return;
    await ForegroundService.start();
    _status = AppStatus.sessionActive;
    _startLocalTimer();
    _checkSchedules();
    notifyListeners();
  }

  Future<void> stopSession() async {
    if (_status == AppStatus.idle) return;
    if (_status == AppStatus.recording) {
      await stopRecording();
    }
    if (_status == AppStatus.listening) await _stopListening();
    await ForegroundService.stop();
    _status = AppStatus.idle;
    notifyListeners();
  }

  // -?š' Enregistrement -?š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š'

  Future<void> startRecording({String triggerSource = 'manual'}) async {
    if (_status == AppStatus.recording || _recordingTransitionInProgress) {
      return;
    }
    _recordingTransitionInProgress = true;
    notifyListeners();
    if (!await _audio.requestPermissions()) {
      _recordingTransitionInProgress = false;
      notifyListeners();
      return;
    }
    if (!await ForegroundService.isRunning) {
      await ForegroundService.start();
    }
    _startLocalTimer();

    if (_status == AppStatus.listening) {
      await _detector.stop();
    }

    final path = await _audio.startRecording();
    if (path == null) {
      _recordingTransitionInProgress = false;
      notifyListeners();
      return;
    }
    _currentRecordingPath = path;
    _currentTriggerSource = triggerSource;
    _recordingStartTime = DateTime.now();
    _status = AppStatus.recording;
    _startAmplitudeSampling();
    _recordingTransitionInProgress = false;
    await ForegroundService.updateNotification(
        'Enregistrement en cours', "Micro actif - capture audio...");
    notifyListeners();
  }

  Future<void> stopRecording() async {
    if (_status != AppStatus.recording || _recordingTransitionInProgress) {
      return;
    }
    _recordingTransitionInProgress = true;
    final duration = await _audio.stopRecording();
    if (_currentRecordingPath != null) {
      final triggerSource = _currentTriggerSource;
      final rec = RecordingModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        filePath: _currentRecordingPath!,
        createdAt: _recordingStartTime ?? DateTime.now(),
        duration: duration,
        triggerSource: triggerSource,
        waveform: List<double>.from(_recordingWaveform),
        transcription: null,
        displayName: _recordingNameForTrigger(triggerSource),
      );
      _recordings.insert(0, rec);
      _lastCreatedRecordingId = rec.id;
      _createdRecordingSignal++;
      if (!_isPremium && _recordings.length > freeRecordingLimit) {
        final removed = _recordings.removeLast();
        await _audio.deleteFile(removed.filePath);
      }
      await _saveRecordings();
      await _saveRecordingToGallerySilently(rec);
    }
    _stopAmplitudeSampling(clearLiveWaveform: false);
    _currentRecordingPath = null;
    _currentTriggerSource = 'manual';
    _recordingStartTime = null;
    final activeKeywordSchedule = _activeKeywordSchedule();
    _status = AppStatus.sessionActive;
    _recordingTransitionInProgress = false;

    await ForegroundService.updateNotification(
        'Session active', 'En attente d\'un créneau planifié');
    notifyListeners();

    if (activeKeywordSchedule != null) {
      await _startListening(activeKeywordSchedule);
    }
  }

  // -?š' Planification -?š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š?

  void _startLocalTimer() {
    _scheduleTimer?.cancel();
    _scheduleTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _checkSchedules());
  }

  void _stopLocalTimer() {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
  }

  void _startAmplitudeSampling() {
    _amplitudeTimer?.cancel();
    _currentAudioLevel = 0;
    _liveWaveform.clear();
    _recordingWaveform.clear();
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      _sampleAmplitude();
    });
  }

  Future<void> _sampleAmplitude() async {
    if (_status != AppStatus.recording) return;
    try {
      final db = await _audio.getAmplitude();
      final normalized = ((db + 55) / 55).clamp(0.0, 1.0);
      _currentAudioLevel = normalized;
      _liveWaveform.add(normalized);
      if (_liveWaveform.length > 72) _liveWaveform.removeAt(0);
      _appendRecordingWaveformSample(normalized);
      notifyListeners();
    } catch (_) {
      _currentAudioLevel = 0;
    }
  }

  void _appendRecordingWaveformSample(double sample) {
    _recordingWaveform.add(sample);
    if (_recordingWaveform.length <= 160) return;

    final compressed = <double>[];
    for (var i = 0; i < _recordingWaveform.length; i += 2) {
      final first = _recordingWaveform[i];
      final second =
          i + 1 < _recordingWaveform.length ? _recordingWaveform[i + 1] : first;
      compressed.add((first + second) / 2);
    }
    _recordingWaveform
      ..clear()
      ..addAll(compressed);
  }

  void _stopAmplitudeSampling({bool clearLiveWaveform = true}) {
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
    _currentAudioLevel = 0;
    if (clearLiveWaveform) _liveWaveform.clear();
    _recordingWaveform.clear();
  }

  void _checkSchedules() {
    _checkAudioPlaybackSchedules();
    if (_status == AppStatus.idle || _recordingTransitionInProgress) return;

    final activeAuto = _scheduler.findActiveSchedule(
      _schedules.where((s) => s.mode == ScheduleMode.autoRecord).toList(),
    );

    if (_status == AppStatus.recording) {
      if (_currentTriggerSource.startsWith('schedule:') && activeAuto == null) {
        stopRecording();
      }
      return;
    }

    final activeKeyword = _scheduler.findActiveSchedule(
      _schedules.where((s) => s.mode == ScheduleMode.keywordTrigger).toList(),
    );

    if (activeAuto != null) {
      // MODE A : enregistrement automatique immédiat
      if (_status == AppStatus.listening) {
        _stopListening().then(
          (_) => startRecording(triggerSource: 'schedule:${activeAuto.id}'),
        );
      } else if (_status == AppStatus.sessionActive) {
        startRecording(triggerSource: 'schedule:${activeAuto.id}');
      }
      // MODE B : écoute et détection de mots-clés
      return;
    }

    if (activeKeyword != null && _status == AppStatus.sessionActive) {
      _startListening(activeKeyword);
    } else if (activeKeyword == null && _status == AppStatus.listening) {
      _stopListening();
    }
  }

  Future<void> _checkAudioPlaybackSchedules() async {
    if (_audioPlaybackSchedules.isEmpty || _status == AppStatus.recording) {
      return;
    }
    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    for (var i = 0; i < _audioPlaybackSchedules.length; i++) {
      final schedule = _audioPlaybackSchedules[i];
      if (!schedule.shouldPlayAt(now)) continue;

      final recording = _recordingById(schedule.recordingId);
      if (recording == null || !await File(recording.filePath).exists()) {
        _audioPlaybackSchedules[i] =
            schedule.copyWith(lastPlayedDateKey: todayKey);
        await _saveAudioPlaybackSchedules();
        notifyListeners();
        continue;
      }

      _audioPlaybackSchedules[i] = schedule.copyWith(
        lastPlayedDateKey: todayKey,
        isActive: schedule.recurrence == AudioPlaybackRecurrence.once
            ? false
            : schedule.isActive,
      );
      await _saveAudioPlaybackSchedules();
      notifyListeners();
      await _scheduledAudioPlayer.stop();
      await _scheduledAudioPlayer.play(
        DeviceFileSource(recording.filePath),
        mode: PlayerMode.mediaPlayer,
      );
      break;
    }
  }

  RecordingModel? _recordingById(String id) {
    for (final recording in _recordings) {
      if (recording.id == id) return recording;
    }
    return null;
  }

  RecordingModel? recordingById(String id) => _recordingById(id);

  String? _recordingNameForTrigger(String triggerSource) {
    if (!triggerSource.startsWith('schedule:')) return null;
    final scheduleId = triggerSource.substring('schedule:'.length);
    for (final schedule in _schedules) {
      if (schedule.id != scheduleId) continue;
      final name = schedule.recordingName?.trim() ?? '';
      return name.isEmpty ? null : name;
    }
    return null;
  }

  ScheduleModel? _activeKeywordSchedule() => _scheduler.findActiveSchedule(
        _schedules.where((s) => s.mode == ScheduleMode.keywordTrigger).toList(),
      );

  Future<void> _startListening(ScheduleModel schedule) async {
    final targets =
        _keywords.where((k) => schedule.keywordIds.contains(k.id)).toList();
    if (targets.isEmpty) {
      await ForegroundService.updateNotification(
        'Session active',
        'Aucun mot-clé configuré pour le créneau actif',
      );
      notifyListeners();
      return;
    }

    _status = AppStatus.listening;
    _lastKeywordRecognitionText = '';
    _lastKeywordDetectionError = null;
    await ForegroundService.updateNotification(
        'En écoute...', 'Surveillance des mots-clés active');
    final started = await _detector.startListening(
      keywords: targets,
      onDetected: (kw) => startRecording(triggerSource: 'keyword:$kw'),
      onRecognizedText: (text) {
        _lastKeywordRecognitionText = text;
        notifyListeners();
      },
      onError: (error) {
        _lastKeywordDetectionError = error;
        notifyListeners();
      },
    );
    if (!started) {
      _status = AppStatus.sessionActive;
      await ForegroundService.updateNotification(
        'Session active',
        'Reconnaissance vocale indisponible pour les mots-clés',
      );
    }
    notifyListeners();
  }

  Future<void> _stopListening() async {
    await _detector.stop();
    _status = AppStatus.sessionActive;
    _lastKeywordRecognitionText = '';
    _lastKeywordDetectionError = null;
    await ForegroundService.updateNotification(
        'Session active', 'En attente d\'un créneau planifié');
    notifyListeners();
  }

  // -?š' Gestion des mots-clés -?š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š?

  String? canAddKeyword() {
    if (_keywords.length >= maxKeywords) {
      return 'Maximum $maxKeywords mots-clés atteint. Supprimez-en un pour continuer.';
    }
    return null;
  }

  Future<void> addKeyword(KeywordModel keyword) async {
    if (_keywords.length >= maxKeywords) return;
    _keywords.add(keyword);
    await _saveKeywords();
    notifyListeners();
  }

  Future<void> updateKeyword(KeywordModel keyword) async {
    final i = _keywords.indexWhere((k) => k.id == keyword.id);
    if (i == -1) return;
    _keywords[i] = keyword;
    await _saveKeywords();
    notifyListeners();
  }

  Future<void> removeKeyword(String id) async {
    _keywords.removeWhere((k) => k.id == id);
    // Retirer l'ID des créneaux qui le référençaient
    _schedules = _schedules
        .map((s) => s.copyWith(
            keywordIds: s.keywordIds.where((kid) => kid != id).toList()))
        .toList();
    await _saveKeywords();
    await _saveSchedules();
    notifyListeners();
  }

  // Enregistre un échantillon vocal (3s) pour un mot-clé.
  // Retourne le chemin du fichier ou null en cas d'échec.
  Future<String?> recordKeywordSample() async {
    if (!await _audio.requestPermissions()) return null;
    if (_audio.isMonitoring) await _audio.stopMonitoring();
    final path = await _audio.startRecording();
    if (path == null) return null;
    await Future.delayed(const Duration(seconds: 3));
    await _audio.stopRecording();
    return path;
  }

  // -?š' Gestion des créneaux -?š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š'

  Future<void> addSchedule(ScheduleModel schedule) async {
    _schedules.add(schedule);
    await _saveSchedules();
    notifyListeners();
  }

  Future<void> removeSchedule(String id) async {
    _schedules.removeWhere((s) => s.id == id);
    await _saveSchedules();
    notifyListeners();
  }

  Future<void> updateSchedule(ScheduleModel schedule) async {
    final i = _schedules.indexWhere((s) => s.id == schedule.id);
    if (i == -1) return;
    _schedules[i] = schedule;
    await _saveSchedules();
    notifyListeners();
  }

  Future<void> toggleSchedule(String id) async {
    final i = _schedules.indexWhere((s) => s.id == id);
    if (i == -1) return;
    _schedules[i] = _schedules[i].copyWith(isActive: !_schedules[i].isActive);
    await _saveSchedules();
    notifyListeners();
  }

  // -?š' Gestion des enregistrements -?š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š'

  Future<void> deleteRecording(String id) async {
    final i = _recordings.indexWhere((r) => r.id == id);
    if (i == -1) return;
    await _audio.deleteFile(_recordings[i].filePath);
    _recordings.removeAt(i);
    _audioPlaybackSchedules.removeWhere((s) => s.recordingId == id);
    await _saveRecordings();
    await _saveAudioPlaybackSchedules();
    notifyListeners();
  }

  Future<void> toggleFavorite(String id) async {
    final i = _recordings.indexWhere((r) => r.id == id);
    if (i == -1) return;
    _recordings[i].isFavorite = !_recordings[i].isFavorite;
    await _saveRecordings();
    notifyListeners();
  }

  Future<void> updateRecordingText({
    required String id,
    String? transcription,
    String? summary,
  }) async {
    final i = _recordings.indexWhere((r) => r.id == id);
    if (i == -1) return;
    _recordings[i].transcription = transcription;
    _recordings[i].summary = summary;
    await _saveRecordings();
    notifyListeners();
  }

  Future<void> renameRecording(String id, String? name) async {
    final i = _recordings.indexWhere((r) => r.id == id);
    if (i == -1) return;
    final cleanName = name?.trim() ?? '';
    _recordings[i].displayName = cleanName.isEmpty ? null : cleanName;
    await _saveRecordings();
    notifyListeners();
  }

  Future<RecordingModel?> importAudioFile({
    required String filePath,
    required String displayName,
    String triggerSource = importedAudioSource,
  }) async {
    final source = File(filePath);
    if (!await source.exists()) return null;
    final dir = await getApplicationDocumentsDirectory();
    final importDir = Directory('${dir.path}/imported_audio');
    if (!await importDir.exists()) await importDir.create(recursive: true);
    final extension = source.path.split('.').last.toLowerCase();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final cleanName =
        displayName.trim().isEmpty ? 'Audio importé' : displayName.trim();
    final target = File('${importDir.path}/audio_$id.$extension');
    await source.copy(target.path);
    final recording = RecordingModel(
      id: id,
      filePath: target.path,
      createdAt: DateTime.now(),
      triggerSource: triggerSource,
      displayName: cleanName,
    );
    _recordings.insert(0, recording);
    await _saveRecordings();
    notifyListeners();
    return recording;
  }

  Future<void> createFolder({required String name, String? pin}) async {
    final cleanName = name.trim();
    final cleanPin = pin?.trim() ?? '';
    if (cleanName.isEmpty) return;
    _folders.insert(
      0,
      SecureFolderModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: cleanName,
        pinHash: cleanPin.isEmpty ? null : SecureFolderModel.hashPin(cleanPin),
        createdAt: DateTime.now(),
      ),
    );
    await _saveFolders();
    notifyListeners();
  }

  Future<void> deleteFolder(String id) async {
    _folders.removeWhere((f) => f.id == id);
    for (final recording in _recordings) {
      if (recording.folderId == id) recording.folderId = null;
    }
    await _saveFolders();
    await _saveRecordings();
    notifyListeners();
  }

  bool verifyFolderPin(String folderId, String pin) {
    final matches = _folders.where((f) => f.id == folderId);
    if (matches.isEmpty) return false;
    return matches.first.verifyPin(pin);
  }

  Future<void> assignRecordingToFolder(
    String recordingId,
    String? folderId,
  ) async {
    final i = _recordings.indexWhere((r) => r.id == recordingId);
    if (i == -1) return;
    _recordings[i].folderId = folderId;
    await _saveRecordings();
    notifyListeners();
  }

  List<RecordingModel> recordingsForFolder(String folderId) =>
      _recordings.where((r) => r.folderId == folderId).toList();

  // Lecture audio planifiée

  Future<void> addAudioPlaybackSchedule({
    required String recordingId,
    required TimeOfDay time,
    required AudioPlaybackRecurrence recurrence,
    DateTime? date,
    List<int> weekdays = const [],
  }) async {
    if (_recordingById(recordingId) == null) return;
    _audioPlaybackSchedules.insert(
      0,
      AudioPlaybackScheduleModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        recordingId: recordingId,
        time: time,
        recurrence: recurrence,
        date: date,
        weekdays: weekdays,
      ),
    );
    await _saveAudioPlaybackSchedules();
    notifyListeners();
  }

  Future<void> toggleAudioPlaybackSchedule(String id) async {
    final i = _audioPlaybackSchedules.indexWhere((s) => s.id == id);
    if (i == -1) return;
    final schedule = _audioPlaybackSchedules[i];
    _audioPlaybackSchedules[i] = schedule.copyWith(
      isActive: !schedule.isActive,
    );
    await _saveAudioPlaybackSchedules();
    notifyListeners();
  }

  Future<void> updateAudioPlaybackSchedule(
    AudioPlaybackScheduleModel schedule,
  ) async {
    final i = _audioPlaybackSchedules.indexWhere((s) => s.id == schedule.id);
    if (i == -1) return;
    _audioPlaybackSchedules[i] = schedule;
    await _saveAudioPlaybackSchedules();
    notifyListeners();
  }

  Future<void> deleteAudioPlaybackSchedule(String id) async {
    _audioPlaybackSchedules.removeWhere((s) => s.id == id);
    await _saveAudioPlaybackSchedules();
    notifyListeners();
  }

  RecordingModel? recordingForPlaybackSchedule(
    AudioPlaybackScheduleModel schedule,
  ) =>
      _recordingById(schedule.recordingId);

  Future<void> playRecordingNow(String recordingId) async {
    final recording = _recordingById(recordingId);
    if (recording == null || !await File(recording.filePath).exists()) return;
    await _scheduledAudioPlayer.stop();
    await _scheduledAudioPlayer.play(
      DeviceFileSource(recording.filePath),
      mode: PlayerMode.mediaPlayer,
    );
  }

  // -?š' IA : transcription + résumé -?š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š-š'

  Future<void> transcribeRecording(String id) async {
    final i = _recordings.indexWhere((r) => r.id == id);
    if (i == -1) return;
    _recordings[i].transcription =
        await _transcription.transcribeAudio(_recordings[i].filePath);
    await _saveRecordings();
    notifyListeners();
  }

  Future<void> summarizeRecording(String id) async {
    final i = _recordings.indexWhere((r) => r.id == id);
    if (i == -1 || _recordings[i].transcription == null) return;
    _recordings[i].summary =
        await _summary.summarizeText(_recordings[i].transcription!);
    await _saveRecordings();
    notifyListeners();
  }

  List<RecordingModel> searchRecordings(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return recordings;
    return _recordings.where((r) {
      return r.title.toLowerCase().contains(q) ||
          r.fileName.toLowerCase().contains(q) ||
          r.triggerLabel.toLowerCase().contains(q) ||
          (r.transcription?.toLowerCase().contains(q) ?? false) ||
          (r.summary?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  Future<String?> exportRecordingAsText(String id) async {
    final i = _recordings.indexWhere((r) => r.id == id);
    if (i == -1) return null;
    final r = _recordings[i];
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!await exportDir.exists()) await exportDir.create(recursive: true);
    final stamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(r.createdAt);
    final file = File('${exportDir.path}/ultimate_audio_recorder_$stamp.txt');
    await file.writeAsString('Ultimate Audio Recorder - Export audio\n\n'
        'Date : ${DateFormat('dd/MM/yyyy HH:mm').format(r.createdAt)}\n'
        'Durée : ${r.duration?.inSeconds ?? 0} secondes\n'
        'Source : ${r.triggerLabel}\n'
        'Fichier : ${r.fileName}\n\n'
        'Transcription\n'
        '${r.transcription ?? 'Aucune transcription disponible.'}\n\n'
        'Résumé\n'
        '${r.summary ?? 'Aucun résumé disponible.'}\n');
    return file.path;
  }

  Future<String?> saveRecordingToGallery(String id) async {
    final i = _recordings.indexWhere((r) => r.id == id);
    if (i == -1) return null;
    final r = _recordings[i];
    try {
      return await _mediaExport.saveAudioVideoToGallery(r.filePath, r.title);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveRecordingToGallerySilently(RecordingModel recording) async {
    try {
      await _mediaExport.saveAudioToGallery(
          recording.filePath, recording.title);
    } catch (_) {
      // The in-app copy remains available if MediaStore rejects the export.
    }
  }

  // -?š' Persistance SharedPreferences (clés v2 pour éviter conflits) -?š-š-š-š'

  Future<void> _saveKeywords() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'keywords_v2', jsonEncode(_keywords.map((k) => k.toJson()).toList()));
  }

  Future<void> _saveSchedules() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'schedules_v2', jsonEncode(_schedules.map((s) => s.toJson()).toList()));
  }

  Future<void> _saveRecordings() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('recordings_v2',
        jsonEncode(_recordings.map((r) => r.toJson()).toList()));
  }

  Future<void> _saveFolders() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        'folders_v1', jsonEncode(_folders.map((f) => f.toJson()).toList()));
  }

  Future<void> _saveAudioPlaybackSchedules() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      'audio_playback_schedules_v1',
      jsonEncode(_audioPlaybackSchedules.map((s) => s.toJson()).toList()),
    );
  }

  Future<void> _loadAll() async {
    final p = await SharedPreferences.getInstance();
    _isPremium = p.getBool(BillingConfig.premiumEntitlementKey) ??
        p.getBool(BillingConfig.legacyDevEntitlementKey) ??
        false;

    final kj = p.getString('keywords_v2');
    if (kj != null) {
      _keywords = (jsonDecode(kj) as List)
          .map((j) => KeywordModel.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    final sj = p.getString('schedules_v2');
    if (sj != null) {
      _schedules = (jsonDecode(sj) as List)
          .map((j) => ScheduleModel.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    final rj = p.getString('recordings_v2');
    if (rj != null) {
      _recordings = (jsonDecode(rj) as List)
          .map((j) => RecordingModel.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    final fj = p.getString('folders_v1');
    if (fj != null) {
      _folders = (jsonDecode(fj) as List)
          .map((j) => SecureFolderModel.fromJson(j as Map<String, dynamic>))
          .toList();
    }
    final apj = p.getString('audio_playback_schedules_v1');
    if (apj != null) {
      _audioPlaybackSchedules = (jsonDecode(apj) as List)
          .map((j) => AudioPlaybackScheduleModel.fromJson(
                j as Map<String, dynamic>,
              ))
          .where((s) => _recordingById(s.recordingId) != null)
          .toList();
    }
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onForegroundTick);
    _stopLocalTimer();
    _stopAmplitudeSampling();
    _detector.stop();
    _purchase.removeListener(notifyListeners);
    _purchase.dispose();
    _scheduledAudioPlayer.dispose();
    _audio.dispose();
    super.dispose();
  }
}
