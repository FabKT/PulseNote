class BillingConfig {
  static const plusSubscriptionId = 'ultimate_audio_recorder_plus_monthly';
  static const proSubscriptionId = 'ultimate_audio_recorder_pro_monthly';
  static const subscriptionTierKey = 'subscription_tier_v1';
  static const legacyDevEntitlementKey = 'is_premium_dev';

  // Quota de stockage cloud (Supabase Storage) du palier Gratuit.
  static const int freeStorageQuotaBytes = 500 * 1024 * 1024;
  static const Duration overQuotaGracePeriod = Duration(days: 3);
}
