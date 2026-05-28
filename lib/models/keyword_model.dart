class KeywordModel {
  final String id;
  final String text;
  final String? audioSamplePath; // chemin vers l'échantillon vocal enregistré

  const KeywordModel({
    required this.id,
    required this.text,
    this.audioSamplePath,
  });

  bool get isRecorded => audioSamplePath != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'audioSamplePath': audioSamplePath,
      };

  factory KeywordModel.fromJson(Map<String, dynamic> json) => KeywordModel(
        id: json['id'] as String,
        text: json['text'] as String,
        audioSamplePath: json['audioSamplePath'] as String?,
      );

  KeywordModel copyWith({
    String? id,
    String? text,
    String? audioSamplePath,
    bool clearSample = false, // met audioSamplePath à null si true
  }) =>
      KeywordModel(
        id: id ?? this.id,
        text: text ?? this.text,
        audioSamplePath:
            clearSample ? null : (audioSamplePath ?? this.audioSamplePath),
      );
}
