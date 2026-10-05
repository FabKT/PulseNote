export const entitlementVerificationMaxAgeMs = 15 * 60 * 1000;

function validDate(value) {
  const date = value ? new Date(value) : null;
  return date && Number.isFinite(date.getTime()) ? date : null;
}

export function isEntitlementActive(row, now = new Date()) {
  const expiry = validDate(row?.subscription_expires_at);
  return !!row && row.tier !== 'free' && !!expiry && expiry > now;
}

export function shouldRefreshEntitlement(
  row,
  now = new Date(),
  maxAgeMs = entitlementVerificationMaxAgeMs,
) {
  if (
    !row ||
    row.tier === 'free' ||
    !row.purchase_token ||
    !row.subscription_product_id
  ) {
    return false;
  }
  if (!isEntitlementActive(row, now)) return true;
  const lastVerified = validDate(row.subscription_last_verified_at);
  return !lastVerified || now.getTime() - lastVerified.getTime() >= maxAgeMs;
}

export function entitlementPayload(row, now = new Date()) {
  const active = isEntitlementActive(row, now);
  return {
    tier: active ? row.tier : 'free',
    creditsRemaining: active ? row.credits_remaining || 0 : 0,
    creditsResetAt: active ? row.credits_reset_at || null : null,
    subscriptionExpiresAt: row?.subscription_expires_at || null,
  };
}

export function verifiedEntitlementUpdate(
  row,
  expiryTime,
  monthlyProCredits,
  now = new Date(),
) {
  const previousExpiry = validDate(row?.subscription_expires_at);
  const nextExpiry = validDate(expiryTime);
  if (!nextExpiry) throw new Error('Invalid Google Play expiry time.');
  const renewed = !previousExpiry || nextExpiry > previousExpiry;
  const isPro = row?.tier === 'pro';
  return {
    subscription_expires_at: nextExpiry.toISOString(),
    subscription_last_verified_at: now.toISOString(),
    credits_remaining:
      isPro && renewed ? monthlyProCredits : row?.credits_remaining || 0,
    credits_reset_at: isPro ? nextExpiry.toISOString() : null,
    updated_at: now.toISOString(),
  };
}

export function inactiveEntitlementUpdate(now = new Date()) {
  return {
    tier: 'free',
    credits_remaining: 0,
    credits_reset_at: null,
    purchase_token: null,
    subscription_last_verified_at: now.toISOString(),
    updated_at: now.toISOString(),
  };
}

export function decodeDeveloperNotification(encodedData) {
  if (typeof encodedData !== 'string' || !encodedData) {
    throw new Error('Missing Pub/Sub message data.');
  }
  const notification = JSON.parse(
    Buffer.from(encodedData, 'base64').toString('utf8'),
  );
  const subscription = notification?.subscriptionNotification;
  if (!subscription?.purchaseToken) return null;
  return {
    purchaseToken: subscription.purchaseToken,
    productId: subscription.subscriptionId || null,
    notificationType: subscription.notificationType || null,
  };
}
