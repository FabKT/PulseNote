// Cree/actualise les abonnements Google Play Billing (Plus / Pro) via l'API
// Google Play Developer, a partir d'un compte de service.
//
// Prerequis cote Play Console (a faire manuellement, une seule fois) :
//   1. La fiche app com.fabkt.ultimateaudiorecorder doit deja exister.
//   2. Users and permissions > API access > creer/lier un compte de service
//      avec le droit "Gerer les commandes et abonnements".
//   3. Telecharger la cle JSON du compte de service et la placer a
//      backend/google-play-service-account.json (jamais commite, voir
//      .gitignore) — ou pointer GOOGLE_PLAY_SERVICE_ACCOUNT_PATH ailleurs.
//
// Usage : node scripts/create-play-subscriptions.js

import 'dotenv/config';
import { readFileSync } from 'node:fs';
import { createSign } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const PACKAGE_NAME = 'com.fabkt.ultimateaudiorecorder';
const SERVICE_ACCOUNT_PATH = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_PATH
  ? path.resolve(process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_PATH)
  : fileURLToPath(new URL('../google-play-service-account.json', import.meta.url));

// Doit rester identique a lib/config/billing_config.dart cote Flutter.
const SUBSCRIPTIONS = [
  {
    productId: 'ultimate_audio_recorder_plus_monthly',
    basePlanId: 'plus-monthly',
    name: 'Plus',
    priceEur: 2.99,
  },
  {
    productId: 'ultimate_audio_recorder_pro_monthly',
    basePlanId: 'pro-monthly',
    name: 'Pro',
    priceEur: 9.99,
  },
];

// Marches ou le prix est fixe explicitement en euros ; ailleurs, Play
// convertit automatiquement depuis otherRegionsConfig.
// CH (Suisse) exclu : facture en CHF, pas en EUR — a ajouter separement si besoin.
const EUR_REGIONS = ['FR', 'BE', 'LU', 'DE', 'ES', 'IT', 'PT', 'IE', 'NL'];

function base64url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function money(amountEur, currencyCode = 'EUR') {
  const units = Math.trunc(amountEur);
  const nanos = Math.round((amountEur - units) * 1e9);
  return { currencyCode, units: String(units), nanos };
}

async function getAccessToken(serviceAccount) {
  const header = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const now = Math.floor(Date.now() / 1000);
  const claims = base64url(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/androidpublisher',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = `${header}.${claims}`;
  const signature = createSign('RSA-SHA256').update(unsigned).sign(serviceAccount.private_key);
  const jwt = `${unsigned}.${base64url(signature)}`;

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(`Echec obtention token OAuth: ${JSON.stringify(payload)}`);
  }
  return payload.access_token;
}

async function callPlayApi(accessToken, method, path, body) {
  const response = await fetch(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PACKAGE_NAME}${path}`,
    {
      method,
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: body ? JSON.stringify(body) : undefined,
    },
  );
  const payload = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, payload };
}

function subscriptionBody(sub) {
  return {
    productId: sub.productId,
    basePlans: [
      {
        basePlanId: sub.basePlanId,
        state: 'DRAFT',
        autoRenewingBasePlanType: {
          billingPeriodDuration: 'P1M',
          gracePeriodDuration: 'P3D',
        },
        regionalConfigs: EUR_REGIONS.map((regionCode) => ({
          regionCode,
          newSubscriberAvailability: true,
          price: money(sub.priceEur),
        })),
      },
    ],
    listings: [
      {
        languageCode: 'en-US',
        title: `Ultimate Audio Recorder ${sub.name}`,
        description: `${sub.name} subscription - Ultimate Audio Recorder`,
      },
      {
        languageCode: 'fr-FR',
        title: `Ultimate Audio Recorder ${sub.name}`,
        description: `Abonnement ${sub.name} - Ultimate Audio Recorder`,
      },
    ],
  };
}

async function ensureSubscription(accessToken, sub) {
  const body = subscriptionBody(sub);
  console.log(`\n-> ${sub.productId}`);

  const regionsVersionParam = `regionsVersion.version=${encodeURIComponent('2022/02')}`;

  let result = await callPlayApi(
    accessToken,
    'POST',
    `/subscriptions?productId=${sub.productId}&${regionsVersionParam}`,
    body,
  );

  if (!result.ok && result.status === 409) {
    console.log('   Deja existant, mise a jour...');
    result = await callPlayApi(
      accessToken,
      'PATCH',
      `/subscriptions/${sub.productId}?updateMask=basePlans,listings&${regionsVersionParam}`,
      body,
    );
  }

  if (!result.ok) {
    console.error(`   Echec creation/maj: ${JSON.stringify(result.payload)}`);
    return;
  }
  console.log('   Cree/mis a jour.');

  console.log(`   Activation du base plan ${sub.basePlanId}...`);
  const activation = await callPlayApi(
    accessToken,
    'POST',
    `/subscriptions/${sub.productId}/basePlans/${sub.basePlanId}:activate`,
    {},
  );
  console.log(
    activation.ok
      ? '   Base plan actif.'
      : `   Echec activation: ${JSON.stringify(activation.payload)}`,
  );
}

async function main() {
  const serviceAccount = JSON.parse(readFileSync(SERVICE_ACCOUNT_PATH, 'utf8'));
  const accessToken = await getAccessToken(serviceAccount);
  for (const sub of SUBSCRIPTIONS) {
    await ensureSubscription(accessToken, sub);
  }
  console.log('\nTermine. Verifie le resultat dans Play Console > Monetisation > Produits.');
}

main().catch((error) => {
  console.error('Erreur:', error);
  process.exitCode = 1;
});
