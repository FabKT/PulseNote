enum SubscriptionTier { free, plus, pro }

extension SubscriptionTierAccess on SubscriptionTier {
  bool get hasContinuousPlayback => index >= SubscriptionTier.plus.index;
  bool get hasAudioImport => true;
  bool get hasMp4ToMp3 => true;
  bool get hasKeywordSchedules => index >= SubscriptionTier.plus.index;
  bool get hasPlaybackSchedules => index >= SubscriptionTier.plus.index;
  bool get hasTranscription => index >= SubscriptionTier.pro.index;
  bool get hasAiSummary => index >= SubscriptionTier.pro.index;

  String get label => switch (this) {
        SubscriptionTier.free => 'Gratuit',
        SubscriptionTier.plus => 'Plus',
        SubscriptionTier.pro => 'Pro',
      };
}
