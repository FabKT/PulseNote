class KeywordModel {
  final String id;
  final String text;
  final String? audioSamplePath; // chemin vers l'échantillon vocal enregistré
  final DateTime updatedAt;
  // Chemin de l'objet dans le bucket Supabase Storage une fois synchronisé.
  final String? audioSampleStoragePath;

  KeywordModel({
    required this.id,
    required this.text,
    this.audioSamplePath,
    DateTime? updatedAt,
    this.audioSampleStoragePath,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get isRecorded => audioSamplePath != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'audioSamplePath': audioSamplePath,
        'updatedAt': updatedAt.toIso8601String(),
        'audioSampleStoragePath': audioSampleStoragePath,
      };

  factory KeywordModel.fromJson(Map<String, dynamic> json) => KeywordModel(
        id: json['id'] as String,
        text: json['text'] as String,
        audioSamplePath: json['audioSamplePath'] as String?,
        updatedAt: json['updatedAt'] != null
            ? DateTime.parse(json['updatedAt'] as String)
            : null,
        audioSampleStoragePath: json['audioSampleStoragePath'] as String?,
      );

  KeywordModel copyWith({
    String? id,
    String? text,
    String? audioSamplePath,
    bool clearSample = false, // met audioSamplePath à null si true
    String? audioSampleStoragePath,
  }) =>
      KeywordModel(
        id: id ?? this.id,
        text: text ?? this.text,
        audioSamplePath:
            clearSample ? null : (audioSamplePath ?? this.audioSamplePath),
        updatedAt: DateTime.now(),
        audioSampleStoragePath:
            audioSampleStoragePath ?? this.audioSampleStoragePath,
      );
}
