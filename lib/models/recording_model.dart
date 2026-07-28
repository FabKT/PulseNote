class RecordingModel {
  final String id;
  final String filePath;
  final DateTime createdAt;
  final Duration? duration;
  final String? triggerSource; // 'manual' | 'schedule:id' | 'keyword:text'
  final List<double> waveform;
  String? displayName;
  bool isFavorite;
  String? folderId;
  String? transcription;
  String? summary;
  DateTime updatedAt;
  // Chemin de l'objet dans le bucket Supabase Storage une fois synchronisé.
  String? storagePath;
  // Taille du fichier local en octets, utilisée pour le quota de stockage
  // cloud du palier Gratuit.
  int? sizeBytes;
  // Vrai seulement une fois l'upload Storage confirmé (voir SyncService).
  bool cloudSynced;
  // Non nul = l'enregistrement dépasse le quota Gratuit, reste local
  // uniquement, et sera supprimé automatiquement à cette date s'il n'est
  // pas exporté ou si l'utilisateur ne passe pas à un palier payant.
  DateTime? overQuotaDeadline;

  RecordingModel({
    required this.id,
    required this.filePath,
    required this.createdAt,
    this.duration,
    this.triggerSource,
    this.waveform = const [],
    this.displayName,
    this.isFavorite = false,
    this.folderId,
    this.transcription,
    this.summary,
    DateTime? updatedAt,
    this.storagePath,
    this.sizeBytes,
    this.cloudSynced = false,
    this.overQuotaDeadline,
  }) : updatedAt = updatedAt ?? createdAt;

  String get fileName => filePath.split(RegExp(r'[/\\]')).last;
  String get title =>
      displayName?.trim().isNotEmpty == true ? displayName!.trim() : fileName;

  String get triggerLabel {
    if (triggerSource == null || triggerSource == 'manual') return 'Manuel';
    if (triggerSource == 'imported') return 'Importé';
    if (triggerSource == 'mp4_to_mp3') return 'MP4 vers MP3';
    if (triggerSource!.startsWith('keyword:')) {
      return 'Mot-clé : "${triggerSource!.substring(8)}"';
    }
    return 'Planifié';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
        'durationMs': duration?.inMilliseconds,
        'triggerSource': triggerSource,
        'waveform': waveform,
        'displayName': displayName,
        'isFavorite': isFavorite,
        'folderId': folderId,
        'transcription': transcription,
        'summary': summary,
        'updatedAt': updatedAt.toIso8601String(),
        'storagePath': storagePath,
        'sizeBytes': sizeBytes,
        'cloudSynced': cloudSynced,
        'overQuotaDeadline': overQuotaDeadline?.toIso8601String(),
      };

  factory RecordingModel.fromJson(Map<String, dynamic> json) {
    final rawWaveform = json['waveform'];
    return RecordingModel(
      id: json['id'] as String,
      filePath: json['filePath'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      duration: json['durationMs'] != null
          ? Duration(milliseconds: json['durationMs'] as int)
          : null,
      triggerSource: json['triggerSource'] as String?,
      waveform: rawWaveform is List
          ? rawWaveform
              .map((v) => v is num ? v.toDouble().clamp(0.0, 1.0) : 0.0)
              .toList()
          : const [],
      displayName: json['displayName'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      folderId: json['folderId'] as String?,
      transcription: json['transcription'] as String?,
      summary: json['summary'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      storagePath: json['storagePath'] as String?,
      sizeBytes: json['sizeBytes'] as int?,
      cloudSynced: json['cloudSynced'] as bool? ?? false,
      overQuotaDeadline: json['overQuotaDeadline'] != null
          ? DateTime.tryParse(json['overQuotaDeadline'] as String)
          : null,
    );
  }
}
