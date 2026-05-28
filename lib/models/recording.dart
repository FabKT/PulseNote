class Recording {
  final String id;
  final String filePath;
  final DateTime createdAt;
  final Duration? duration;
  String? transcription;
  String? summary;

  Recording({
    required this.id,
    required this.filePath,
    required this.createdAt,
    this.duration,
    this.transcription,
    this.summary,
  });

  String get fileName => filePath.split('/').last.split('\\').last;

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
        'durationMs': duration?.inMilliseconds,
        'transcription': transcription,
        'summary': summary,
      };

  factory Recording.fromJson(Map<String, dynamic> json) => Recording(
        id: json['id'] as String,
        filePath: json['filePath'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        duration: json['durationMs'] != null
            ? Duration(milliseconds: json['durationMs'] as int)
            : null,
        transcription: json['transcription'] as String?,
        summary: json['summary'] as String?,
      );
}
