import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/audio_playback_schedule_model.dart';
import '../models/keyword_model.dart';
import '../models/recording_model.dart';
import '../models/schedule_model.dart';
import '../models/secure_folder_model.dart';

// Synchronise les données locales (SharedPreferences + fichiers) vers
// Supabase en arrière-plan. Le stockage local reste la source de vérité
// immédiate (l'app doit fonctionner sans réseau) ; ce service pousse les
// changements dès que possible et les rejoue depuis une file d'attente
// persistée en cas de coupure réseau.
class SyncService {
  SyncService({this.onRecordingUploaded});

  // Appelé après qu'un enregistrement a été confirmé uploadé vers Supabase
  // Storage (pas juste sa ligne de métadonnées) — utilisé par AppState pour
  // marquer `cloudSynced = true` et recalculer le quota du palier Gratuit.
  final void Function(String recordingId)? onRecordingUploaded;

  static const _queueKey = 'sync_queue_v1';

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _retryTimer;
  bool _flushing = false;

  SupabaseClient? get _client =>
      SupabaseConfig.isConfigured ? Supabase.instance.client : null;

  String? get _userId => _client?.auth.currentUser?.id;

  bool get isAvailable => _client != null && _userId != null;

  Future<void> init() async {
    if (_client == null) return;
    _connectivitySub = Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none)) flushQueue();
    });
    _retryTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => flushQueue(),
    );
    unawaited(flushQueue());
  }

  void dispose() {
    _connectivitySub?.cancel();
    _retryTimer?.cancel();
  }

  // ─── API publique appelée depuis AppState ────────────────────────────

  Future<void> upsertRecording(RecordingModel r) async {
    r.storagePath ??= _buildStoragePath(r.id, r.filePath);
    await _enqueue(_SyncJob(
      table: 'recordings',
      recordId: r.id,
      payload: _recordingRow(r),
      localFilePath: r.filePath,
      storageBucket: 'recordings-audio',
      storageObjectPath: r.storagePath,
    ));
  }

  // `{user_id}/{id}.{ext}` : chemin attendu par les policies Storage
  // (`storage.foldername(name)[1] = auth.uid()`), cf. supabase/schema.sql.
  String? _buildStoragePath(String id, String localFilePath) {
    final userId = _userId;
    if (userId == null) return null;
    final ext = localFilePath.contains('.') ? localFilePath.split('.').last : 'm4a';
    return '$userId/$id.$ext';
  }

  Future<void> deleteRecording(String id, {String? storagePath}) =>
      _enqueue(_SyncJob(
        table: 'recordings',
        recordId: id,
        isDelete: true,
        storageBucket: storagePath == null ? null : 'recordings-audio',
        storageObjectPath: storagePath,
      ));

  Future<void> upsertFolder(SecureFolderModel f) => _enqueue(_SyncJob(
        table: 'folders',
        recordId: f.id,
        payload: {
          'id': f.id,
          'name': f.name,
          'pin_hash': f.pinHash,
          'created_at': f.createdAt.toIso8601String(),
          'updated_at': f.updatedAt.toIso8601String(),
        },
      ));

  Future<void> deleteFolder(String id) =>
      _enqueue(_SyncJob(table: 'folders', recordId: id, isDelete: true));

  Future<void> upsertKeyword(KeywordModel k) async {
    var storagePath = k.audioSampleStoragePath;
    final userId = _userId;
    if (storagePath == null && userId != null && k.audioSamplePath != null) {
      final ext = k.audioSamplePath!.contains('.')
          ? k.audioSamplePath!.split('.').last
          : 'm4a';
      storagePath = '$userId/${k.id}.$ext';
    }
    await _enqueue(_SyncJob(
      table: 'keywords',
      recordId: k.id,
      payload: {
        'id': k.id,
        'text': k.text,
        'audio_sample_storage_path': storagePath,
        'updated_at': k.updatedAt.toIso8601String(),
      },
      localFilePath: k.audioSamplePath,
      storageBucket: 'keyword-samples',
      storageObjectPath: storagePath,
    ));
  }

  Future<void> deleteKeyword(String id) =>
      _enqueue(_SyncJob(table: 'keywords', recordId: id, isDelete: true));

  Future<void> upsertSchedule(ScheduleModel s) => _enqueue(_SyncJob(
        table: 'schedules',
        recordId: s.id,
        payload: {
          'id': s.id,
          'start_hour': s.startTime.hour,
          'start_minute': s.startTime.minute,
          'end_hour': s.endTime.hour,
          'end_minute': s.endTime.minute,
          'mode': s.mode.name,
          'keyword_ids': s.keywordIds,
          'days_of_week': s.daysOfWeek,
          'recording_name': s.recordingName,
          'is_active': s.isActive,
          'updated_at': s.updatedAt.toIso8601String(),
        },
      ));

  Future<void> deleteSchedule(String id) =>
      _enqueue(_SyncJob(table: 'schedules', recordId: id, isDelete: true));

  Future<void> upsertAudioPlaybackSchedule(
    AudioPlaybackScheduleModel s,
  ) =>
      _enqueue(_SyncJob(
        table: 'audio_playback_schedules',
        recordId: s.id,
        payload: {
          'id': s.id,
          'recording_id': s.recordingId,
          'hour': s.time.hour,
          'minute': s.time.minute,
          'recurrence': s.recurrence.name,
          'date': s.date == null
              ? null
              : '${s.date!.year.toString().padLeft(4, '0')}-'
                  '${s.date!.month.toString().padLeft(2, '0')}-'
                  '${s.date!.day.toString().padLeft(2, '0')}',
          'weekdays': s.weekdays,
          'is_active': s.isActive,
          'last_played_date_key': s.lastPlayedDateKey,
          'updated_at': s.updatedAt.toIso8601String(),
        },
      ));

  Future<void> deleteAudioPlaybackSchedule(String id) => _enqueue(
        _SyncJob(table: 'audio_playback_schedules', recordId: id, isDelete: true),
      );

  // ─── Récupération distante (nouvel appareil / réinstallation) ────────

  Future<List<RecordingModel>> pullRecordings() async {
    final rows = await _fetchTable('recordings');
    return rows.map(_recordingFromRow).whereType<RecordingModel>().toList();
  }

  Future<List<SecureFolderModel>> pullFolders() async {
    final rows = await _fetchTable('folders');
    return rows
        .map((row) => SecureFolderModel(
              id: row['id'] as String,
              name: row['name'] as String,
              pinHash: row['pin_hash'] as String?,
              createdAt: DateTime.parse(row['created_at'] as String),
              updatedAt: DateTime.parse(row['updated_at'] as String),
            ))
        .toList();
  }

  Future<List<KeywordModel>> pullKeywords() async {
    final rows = await _fetchTable('keywords');
    return rows
        .map((row) => KeywordModel(
              id: row['id'] as String,
              text: row['text'] as String,
              updatedAt: DateTime.parse(row['updated_at'] as String),
              audioSampleStoragePath:
                  row['audio_sample_storage_path'] as String?,
            ))
        .toList();
  }

  Future<List<ScheduleModel>> pullSchedules() async {
    final rows = await _fetchTable('schedules');
    return rows
        .map((row) => ScheduleModel(
              id: row['id'] as String,
              startTime: TimeOfDay(
                hour: row['start_hour'] as int,
                minute: row['start_minute'] as int,
              ),
              endTime: TimeOfDay(
                hour: row['end_hour'] as int,
                minute: row['end_minute'] as int,
              ),
              mode: ScheduleMode.values.firstWhere(
                (m) => m.name == row['mode'],
                orElse: () => ScheduleMode.autoRecord,
              ),
              keywordIds: List<String>.from(row['keyword_ids'] as List? ?? []),
              daysOfWeek: List<int>.from(row['days_of_week'] as List? ?? []),
              recordingName: row['recording_name'] as String?,
              isActive: row['is_active'] as bool? ?? true,
              updatedAt: DateTime.parse(row['updated_at'] as String),
            ))
        .toList();
  }

  Future<List<AudioPlaybackScheduleModel>> pullAudioPlaybackSchedules() async {
    final rows = await _fetchTable('audio_playback_schedules');
    return rows
        .map((row) => AudioPlaybackScheduleModel(
              id: row['id'] as String,
              recordingId: row['recording_id'] as String,
              time: TimeOfDay(
                hour: row['hour'] as int,
                minute: row['minute'] as int,
              ),
              recurrence: AudioPlaybackRecurrence.values.firstWhere(
                (r) => r.name == row['recurrence'],
                orElse: () => AudioPlaybackRecurrence.once,
              ),
              date: row['date'] == null
                  ? null
                  : DateTime.tryParse(row['date'] as String),
              weekdays: List<int>.from(row['weekdays'] as List? ?? []),
              isActive: row['is_active'] as bool? ?? true,
              lastPlayedDateKey: row['last_played_date_key'] as String?,
              updatedAt: DateTime.parse(row['updated_at'] as String),
            ))
        .toList();
  }

  // Télécharge l'audio d'un enregistrement récupéré d'un autre appareil et
  // ne possédant pas encore de copie locale. Retourne le chemin local ou
  // null en cas d'échec (pas de réseau, fichier absent du bucket...).
  Future<String?> downloadRecordingAudio(
    RecordingModel recording,
    String targetPath,
  ) async {
    final client = _client;
    final storagePath = recording.storagePath;
    if (client == null || storagePath == null) return null;
    try {
      final bytes =
          await client.storage.from('recordings-audio').download(storagePath);
      final file = File(targetPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  // ─── Implémentation file d'attente ────────────────────────────────────

  Future<List<Map<String, dynamic>>> _fetchTable(String table) async {
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null) return [];
    try {
      final rows = await client.from(table).select().eq('user_id', userId);
      return List<Map<String, dynamic>>.from(rows as List);
    } catch (_) {
      return [];
    }
  }

  RecordingModel? _recordingFromRow(Map<String, dynamic> row) {
    try {
      return RecordingModel(
        id: row['id'] as String,
        filePath: '',
        createdAt: DateTime.parse(row['created_at'] as String),
        duration: row['duration_ms'] != null
            ? Duration(milliseconds: row['duration_ms'] as int)
            : null,
        triggerSource: row['trigger_source'] as String?,
        waveform: (row['waveform'] as List? ?? [])
            .map((v) => v is num ? v.toDouble() : 0.0)
            .toList(),
        displayName: row['display_name'] as String?,
        isFavorite: row['is_favorite'] as bool? ?? false,
        folderId: row['folder_id'] as String?,
        transcription: row['transcription'] as String?,
        summary: row['summary'] as String?,
        updatedAt: DateTime.parse(row['updated_at'] as String),
        storagePath: row['storage_path'] as String?,
        cloudSynced: row['storage_path'] != null,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _recordingRow(RecordingModel r) => {
        'id': r.id,
        'storage_path': r.storagePath,
        'created_at': r.createdAt.toIso8601String(),
        'duration_ms': r.duration?.inMilliseconds,
        'trigger_source': r.triggerSource,
        'waveform': r.waveform,
        'display_name': r.displayName,
        'is_favorite': r.isFavorite,
        'folder_id': r.folderId,
        'transcription': r.transcription,
        'summary': r.summary,
        'updated_at': r.updatedAt.toIso8601String(),
      };

  Future<void> _enqueue(_SyncJob job) async {
    job.ownerId ??= _userId;
    final jobs = await _loadQueue();
    jobs.removeWhere((j) => j.table == job.table && j.recordId == job.recordId);
    jobs.add(job);
    await _saveQueue(jobs);
    unawaited(flushQueue());
  }

  Future<void> flushQueue() async {
    if (_flushing || _client == null || _userId == null) return;
    _flushing = true;
    try {
      var jobs = await _loadQueue();
      while (jobs.isNotEmpty) {
        final job = jobs.first;
        final ok = await _runJob(job);
        if (!ok) break;
        jobs = jobs.sublist(1);
        await _saveQueue(jobs);
      }
    } finally {
      _flushing = false;
    }
  }

  Future<bool> _runJob(_SyncJob job) async {
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null) return false;
    // Tache creee sous un autre compte (deconnexion puis connexion d'une
    // autre personne) : ne jamais l'envoyer dans le cloud du compte actuel.
    if (job.ownerId != null && job.ownerId != userId) return true;
    try {
      if (job.isDelete) {
        if (job.storageBucket != null && job.storageObjectPath != null) {
          await client.storage
              .from(job.storageBucket!)
              .remove([job.storageObjectPath!]);
        }
        await client.from(job.table).delete().eq('id', job.recordId);
        return true;
      }

      var uploaded = false;
      if (job.localFilePath != null &&
          job.storageBucket != null &&
          job.storageObjectPath != null) {
        final file = File(job.localFilePath!);
        if (await file.exists()) {
          await client.storage.from(job.storageBucket!).upload(
                job.storageObjectPath!,
                file,
                fileOptions: const FileOptions(upsert: true),
              );
          uploaded = true;
        }
      }

      final payload = <String, dynamic>{
        ...?job.payload,
        'user_id': userId,
      };
      await client.from(job.table).upsert(payload);
      if (uploaded && job.table == 'recordings') {
        onRecordingUploaded?.call(job.recordId);
      }
      return true;
    } on SocketException {
      return false;
    } catch (_) {
      // Erreur non réseau (payload invalide, ligne supprimée entre temps...) :
      // on abandonne ce job pour ne pas bloquer la file indéfiniment.
      return true;
    }
  }

  Future<List<_SyncJob>> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((j) => _SyncJob.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveQueue(List<_SyncJob> jobs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _queueKey,
      jsonEncode(jobs.map((j) => j.toJson()).toList()),
    );
  }
}

class _SyncJob {
  final String table;
  final String recordId;
  final bool isDelete;
  final Map<String, dynamic>? payload;
  final String? localFilePath;
  final String? storageBucket;
  final String? storageObjectPath;
  // Compte connecte au moment ou la tache a ete creee.
  String? ownerId;

  _SyncJob({
    required this.table,
    required this.recordId,
    this.isDelete = false,
    this.payload,
    this.localFilePath,
    this.storageBucket,
    this.storageObjectPath,
    this.ownerId,
  });

  Map<String, dynamic> toJson() => {
        'table': table,
        'recordId': recordId,
        'isDelete': isDelete,
        'payload': payload,
        'localFilePath': localFilePath,
        'storageBucket': storageBucket,
        'storageObjectPath': storageObjectPath,
        'ownerId': ownerId,
      };

  factory _SyncJob.fromJson(Map<String, dynamic> json) => _SyncJob(
        table: json['table'] as String,
        recordId: json['recordId'] as String,
        isDelete: json['isDelete'] as bool? ?? false,
        payload: (json['payload'] as Map?)?.cast<String, dynamic>(),
        localFilePath: json['localFilePath'] as String?,
        storageBucket: json['storageBucket'] as String?,
        storageObjectPath: json['storageObjectPath'] as String?,
        ownerId: json['ownerId'] as String?,
      );
}
