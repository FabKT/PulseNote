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
  });

  String get fileName => filePath.split(RegExp(r'[/\\]')).last;
  String get title =>
      displayName?.trim().isNotEmpty == true ? displayName!.trim() : fileName;

  String get triggerLabel {
    if (triggerSource == null || triggerSource == 'manual') return 'Manuel';
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
    );
  }
}
