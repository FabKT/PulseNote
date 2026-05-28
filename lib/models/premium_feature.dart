enum PremiumFeature {
  recordingTranscription,
  aiSummary,
  keywordTrigger,
  advancedSearch,
  advancedExports,
  unlimitedHistory,
}

extension PremiumFeatureLabels on PremiumFeature {
  String get title => switch (this) {
        PremiumFeature.recordingTranscription => 'Transcription audio',
        PremiumFeature.aiSummary => 'Résumé IA',
        PremiumFeature.keywordTrigger => 'Déclenchement par mots-clés',
        PremiumFeature.advancedSearch => 'Recherche intelligente',
        PremiumFeature.advancedExports => 'Exports avancés',
        PremiumFeature.unlimitedHistory => 'Historique illimité',
      };

  String get description => switch (this) {
        PremiumFeature.recordingTranscription =>
          'Transformez vos fichiers audio existants en texte.',
        PremiumFeature.aiSummary =>
          'Générez automatiquement un résumé exploitable.',
        PremiumFeature.keywordTrigger =>
          'Lancez un enregistrement quand un mot-clé est détecté.',
        PremiumFeature.advancedSearch =>
          'Retrouvez un passage précis dans vos transcriptions.',
        PremiumFeature.advancedExports =>
          'Exportez vos notes vocales en formats texte, PDF ou document.',
        PremiumFeature.unlimitedHistory =>
          "Conservez plus d'enregistrements et des sessions plus longues.",
      };
}
