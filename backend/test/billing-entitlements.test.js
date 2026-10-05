import assert from 'node:assert/strict';
import test from 'node:test';

import {
  decodeDeveloperNotification,
  entitlementPayload,
  inactiveEntitlementUpdate,
  shouldRefreshEntitlement,
  verifiedEntitlementUpdate,
} from '../src/billing-entitlements.js';

const now = new Date('2026-10-05T12:00:00.000Z');

function activeRow(overrides = {}) {
  return {
    tier: 'pro',
    credits_remaining: 217,
    credits_reset_at: '2026-11-05T12:00:00.000Z',
    subscription_expires_at: '2026-11-05T12:00:00.000Z',
    subscription_last_verified_at: '2026-10-05T11:50:00.000Z',
    subscription_product_id: 'ultimate_audio_recorder_pro_monthly',
    purchase_token: 'token',
    ...overrides,
  };
}

test('active subscriptions are revalidated after fifteen minutes', () => {
  assert.equal(shouldRefreshEntitlement(activeRow(), now), false);
  assert.equal(
    shouldRefreshEntitlement(
      activeRow({ subscription_last_verified_at: '2026-10-05T11:44:59.000Z' }),
      now,
    ),
    true,
  );
});

test('expired subscriptions are always revalidated', () => {
  assert.equal(
    shouldRefreshEntitlement(
      activeRow({ subscription_expires_at: '2026-10-05T11:59:59.000Z' }),
      now,
    ),
    true,
  );
});

test('a renewal resets Pro credits but a routine verification does not', () => {
  const routine = verifiedEntitlementUpdate(
    activeRow(),
    '2026-11-05T12:00:00.000Z',
    1000,
    now,
  );
  assert.equal(routine.credits_remaining, 217);

  const renewal = verifiedEntitlementUpdate(
    activeRow(),
    '2026-12-05T12:00:00.000Z',
    1000,
    now,
  );
  assert.equal(renewal.credits_remaining, 1000);
  assert.equal(renewal.credits_reset_at, '2026-12-05T12:00:00.000Z');
});

test('inactive purchases immediately become free', () => {
  const update = inactiveEntitlementUpdate(now);
  assert.equal(update.tier, 'free');
  assert.equal(update.credits_remaining, 0);
  assert.equal(update.purchase_token, null);
  assert.deepEqual(entitlementPayload({ ...activeRow(), ...update }, now), {
    tier: 'free',
    creditsRemaining: 0,
    creditsResetAt: null,
    subscriptionExpiresAt: '2026-11-05T12:00:00.000Z',
  });
});

test('Google Play RTDN payload is decoded from Pub/Sub data', () => {
  const data = Buffer.from(
    JSON.stringify({
      subscriptionNotification: {
        notificationType: 12,
        purchaseToken: 'purchase-token',
        subscriptionId: 'ultimate_audio_recorder_pro_monthly',
      },
    }),
  ).toString('base64');
  assert.deepEqual(decodeDeveloperNotification(data), {
    purchaseToken: 'purchase-token',
    productId: 'ultimate_audio_recorder_pro_monthly',
    notificationType: 12,
  });
});
