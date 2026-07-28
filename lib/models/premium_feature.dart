import 'subscription_tier.dart';

enum PremiumFeature {
  continuousPlayback,
  audioImport,
  mp4ToMp3,
  keywordTrigger,
  playbackSchedule,
  recordingTranscription,
  aiSummary,
}

extension PremiumFeatureLabels on PremiumFeature {
  SubscriptionTier get requiredTier => switch (this) {
        PremiumFeature.continuousPlayback => SubscriptionTier.plus,
        PremiumFeature.audioImport => SubscriptionTier.plus,
        PremiumFeature.mp4ToMp3 => SubscriptionTier.plus,
        PremiumFeature.keywordTrigger => SubscriptionTier.plus,
        PremiumFeature.playbackSchedule => SubscriptionTier.plus,
        PremiumFeature.recordingTranscription => SubscriptionTier.pro,
        PremiumFeature.aiSummary => SubscriptionTier.pro,
      };

  String get title => switch (this) {
        PremiumFeature.continuousPlayback => 'Lecture continue',
        PremiumFeature.audioImport => 'Import audio',
        PremiumFeature.mp4ToMp3 => 'MP4 vers MP3',
        PremiumFeature.keywordTrigger => 'Déclenchement par mots-clés',
        PremiumFeature.playbackSchedule => 'Lecture planifiée',
        PremiumFeature.recordingTranscription => 'Transcription audio',
        PremiumFeature.aiSummary => 'Résumé IA',
      };

  String get description => switch (this) {
        PremiumFeature.continuousPlayback =>
          'Enchaînez la lecture de vos enregistrements sans interruption.',
        PremiumFeature.audioImport =>
          'Importez des fichiers audio existants dans l\'app.',
        PremiumFeature.mp4ToMp3 =>
          'Convertissez vos vidéos MP4 en fichiers audio MP3.',
        PremiumFeature.keywordTrigger =>
          'Lancez un enregistrement quand un mot-clé est détecté.',
        PremiumFeature.playbackSchedule =>
          'Programmez la lecture automatique d\'un enregistrement.',
        PremiumFeature.recordingTranscription =>
          'Transformez vos enregistrements en texte.',
        PremiumFeature.aiSummary =>
          'Générez automatiquement un résumé exploitable.',
      };
}
