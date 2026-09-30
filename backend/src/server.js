import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import crypto from 'node:crypto';
import { execFile } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { promisify } from 'node:util';
import multer from 'multer';
import OpenAI from 'openai';
import { createClient } from '@supabase/supabase-js';
import admin from 'firebase-admin';

const app = express();
const port = Number(process.env.PORT || 8787);
const execFileAsync = promisify(execFile);

const openaiApiKey = process.env.OPENAI_API_KEY;
const appClientToken = process.env.APP_CLIENT_TOKEN;
const transcriptionModel =
  process.env.TRANSCRIPTION_MODEL || 'gpt-4o-transcribe';
const requestedRealtimeTranscriptionModel =
  process.env.REALTIME_TRANSCRIPTION_MODEL || 'gpt-realtime-whisper';
const defaultRealtimeTranscriptionModel = 'gpt-realtime-whisper';
const realtimeTranscriptionModel = [
  'whisper-1',
  'gpt-realtime-whisper',
  'gpt-4o-transcribe',
  'gpt-4o-mini-transcribe',
  'gpt-4o-mini-transcribe-2025-03-20',
  'gpt-4o-mini-transcribe-2025-12-15',
].includes(requestedRealtimeTranscriptionModel)
  ? requestedRealtimeTranscriptionModel
  : defaultRealtimeTranscriptionModel;
const summaryModel = process.env.SUMMARY_MODEL || 'gpt-4.1-mini';
const defaultLanguage = process.env.DEFAULT_LANGUAGE || 'fr';
const supabaseUrl = process.env.SUPABASE_URL;
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;
const supabaseServiceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const firebaseProjectId = process.env.FIREBASE_PROJECT_ID || 'pulsenote-d2d85';
const packageName = 'com.fabkt.ultimateaudiorecorder';
const plusProductId = 'ultimate_audio_recorder_plus_monthly';
const proProductId = 'ultimate_audio_recorder_pro_monthly';
const monthlyProCredits = 1000;
const directTranscriptionMaxBytes = 24 * 1024 * 1024;
const uploadMaxBytes = Number(process.env.MAX_AUDIO_UPLOAD_MB || 500) * 1024 * 1024;
const chunkSeconds = Number(process.env.TRANSCRIPTION_CHUNK_SECONDS || 600);

if (!openaiApiKey) {
  throw new Error('OPENAI_API_KEY is required.');
}

if (!appClientToken || appClientToken.length < 24) {
  throw new Error('APP_CLIENT_TOKEN must be a long random secret.');
}

if (!supabaseUrl || !supabaseAnonKey) {
  console.warn(
    'SUPABASE_URL/SUPABASE_ANON_KEY not set: Supabase-authenticated clients will be rejected (Firebase and x-app-token still work).',
  );
}

const openai = new OpenAI({ apiKey: openaiApiKey });
const supabase =
  supabaseUrl && supabaseAnonKey ? createClient(supabaseUrl, supabaseAnonKey) : null;
const supabaseAdmin =
  supabaseUrl && supabaseServiceRoleKey
    ? createClient(supabaseUrl, supabaseServiceRoleKey, {
        auth: { autoRefreshToken: false, persistSession: false },
      })
    : null;
admin.initializeApp({ projectId: firebaseProjectId });

function loadGooglePlayServiceAccount() {
  const raw = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON;
  if (raw) return JSON.parse(raw);
  const configuredPath = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_PATH;
  if (configuredPath && fs.existsSync(configuredPath)) {
    return JSON.parse(fs.readFileSync(configuredPath, 'utf8'));
  }
  return null;
}

function base64Url(value) {
  return Buffer.from(value)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

async function googlePlayAccessToken() {
  const account = loadGooglePlayServiceAccount();
  if (!account?.client_email || !account?.private_key) {
    throw new Error('Google Play service account is not configured.');
  }
  const now = Math.floor(Date.now() / 1000);
  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claims = base64Url(
    JSON.stringify({
      iss: account.client_email,
      scope: 'https://www.googleapis.com/auth/androidpublisher',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsigned = `${header}.${claims}`;
  const signature = crypto
    .createSign('RSA-SHA256')
    .update(unsigned)
    .sign(account.private_key);
  const assertion = `${unsigned}.${base64Url(signature)}`;
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  const payload = await response.json();
  if (!response.ok || !payload.access_token) {
    throw new Error(payload.error_description || 'Google OAuth failed.');
  }
  return payload.access_token;
}

async function verifyGoogleSubscription(productId, purchaseToken) {
  if (![plusProductId, proProductId].includes(productId)) {
    throw new Error('Unknown subscription product.');
  }
  const accessToken = await googlePlayAccessToken();
  const url =
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
    `${packageName}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;
  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  const purchase = await response.json();
  if (!response.ok) {
    throw new Error(purchase?.error?.message || 'Google Play verification failed.');
  }

  const lineItem = purchase.lineItems?.find((item) => item.productId === productId);
  const expiryTime = lineItem?.expiryTime;
  const allowedStates = new Set([
    'SUBSCRIPTION_STATE_ACTIVE',
    'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
    'SUBSCRIPTION_STATE_CANCELED',
  ]);
  if (
    !lineItem ||
    !expiryTime ||
    new Date(expiryTime) <= new Date() ||
    !allowedStates.has(purchase.subscriptionState)
  ) {
    throw new Error('Subscription is not active.');
  }

  if (purchase.acknowledgementState === 'ACKNOWLEDGEMENT_STATE_PENDING') {
    const acknowledgeUrl =
      `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
      `${packageName}/purchases/subscriptions/${productId}/tokens/` +
      `${encodeURIComponent(purchaseToken)}:acknowledge`;
    const acknowledgeResponse = await fetch(acknowledgeUrl, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: '{}',
    });
    if (!acknowledgeResponse.ok) {
      throw new Error('Google Play acknowledgement failed.');
    }
  }
  return { expiryTime };
}

function entitlementPayload(row) {
  return {
    tier: row?.tier || 'free',
    creditsRemaining: row?.credits_remaining || 0,
    creditsResetAt: row?.credits_reset_at || null,
    subscriptionExpiresAt: row?.subscription_expires_at || null,
  };
}

async function userEntitlement(userId) {
  if (!supabaseAdmin) throw new Error('Supabase admin is not configured.');
  const { data, error } = await supabaseAdmin
    .from('user_entitlements')
    .select('*')
    .eq('user_id', userId)
    .maybeSingle();
  if (error) throw error;
  return data;
}

async function requireProEntitlement(userId) {
  const entitlement = await userEntitlement(userId);
  const expiresAt = entitlement?.subscription_expires_at;
  if (
    entitlement?.tier !== 'pro' ||
    !expiresAt ||
    new Date(expiresAt) <= new Date()
  ) {
    const error = new Error('Un abonnement Pro actif est requis.');
    error.status = 403;
    throw error;
  }
  return entitlement;
}

async function audioCreditCost(filePath) {
  const { stdout } = await execFileAsync(
    'ffprobe',
    [
      '-v',
      'error',
      '-show_entries',
      'format=duration',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      filePath,
    ],
    { timeout: 30_000 },
  );
  const seconds = Number.parseFloat(stdout.trim());
  if (!Number.isFinite(seconds) || seconds <= 0) return 1;
  return Math.max(1, Math.ceil(seconds / 60));
}

async function consumeCredits(userId, amount) {
  await requireProEntitlement(userId);
  const { data, error } = await supabaseAdmin.rpc('consume_ai_credits', {
    p_user_id: userId,
    p_amount: amount,
  });
  if (error) {
    const insufficient = error.message?.includes('insufficient_ai_credits');
    const failure = new Error(
      insufficient ? 'Crédits IA insuffisants.' : 'Débit des crédits impossible.',
    );
    failure.status = insufficient ? 402 : 500;
    throw failure;
  }
  return data;
}

async function refundCredits(userId, amount) {
  if (!supabaseAdmin || amount <= 0) return;
  await supabaseAdmin.rpc('refund_ai_credits', {
    p_user_id: userId,
    p_amount: amount,
  });
}

const uploadDir = path.join(os.tmpdir(), 'ultimate-audio-recorder-uploads');
const upload = multer({
  storage: multer.diskStorage({
    destination: uploadDir,
    filename: (_, file, cb) => {
      const extension = audioExtension(file.originalname, file.mimetype);
      cb(null, `${crypto.randomUUID()}${extension}`);
    },
  }),
  limits: {
    fileSize: uploadMaxBytes,
    files: 1,
  },
});

app.disable('x-powered-by');
app.use(cors({ origin: true }));
app.use(express.json({ limit: '1mb' }));

async function requireAuth(req, res, next) {
  const authorization = req.header('authorization') || '';
  const [, bearerToken] = authorization.match(/^Bearer\s+(.+)$/i) || [];
  if (bearerToken) {
    // Deux populations de clients partagent ce backend : l'app historique
    // (Firebase Auth) et Ultimate Audio Recorder (Supabase Auth). On tente
    // les deux verifications avant de retomber sur le token applicatif.
    try {
      req.user = await admin.auth().verifyIdToken(bearerToken);
      req.authProvider = 'firebase';
      return next();
    } catch (firebaseError) {
      if (supabase) {
        try {
          const { data, error } = await supabase.auth.getUser(bearerToken);
          if (error || !data?.user) {
            throw error || new Error('No user for token.');
          }
          req.user = data.user;
          req.authProvider = 'supabase';
          return next();
        } catch (supabaseError) {
          console.warn('Firebase token rejected:', firebaseError?.message || firebaseError);
          console.warn('Supabase token rejected:', supabaseError?.message || supabaseError);
        }
      } else {
        console.warn('Firebase token rejected:', firebaseError?.message || firebaseError);
      }
    }
  }

  const token = req.header('x-app-token');
  if (token !== appClientToken) {
    return res.status(401).json({ error: 'Unauthorized' });
  }
  next();
}

function safeOpenAiError(error) {
  return {
    message: error?.message || 'Unknown OpenAI error.',
    status: error?.status || error?.response?.status || null,
    type: error?.type || error?.error?.type || null,
    code: error?.code || error?.error?.code || null,
  };
}

function audioExtension(originalName = '', mimeType = '') {
  const fromName = path.extname(originalName).toLowerCase();
  if (
    ['.flac', '.m4a', '.mp3', '.mp4', '.mpeg', '.mpga', '.oga', '.ogg', '.wav', '.webm'].includes(
      fromName,
    )
  ) {
    return fromName;
  }

  const cleanMime = mimeType.toLowerCase().split(';')[0].trim();
  switch (cleanMime) {
    case 'audio/wav':
    case 'audio/x-wav':
      return '.wav';
    case 'audio/mpeg':
    case 'audio/mp3':
      return '.mp3';
    case 'audio/mp4':
    case 'audio/m4a':
    case 'audio/x-m4a':
      return '.m4a';
    case 'audio/aac':
      return '.aac';
    case 'audio/ogg':
      return '.ogg';
    case 'audio/webm':
      return '.webm';
    case 'audio/flac':
      return '.flac';
    default:
      return '.m4a';
  }
}

async function createTranscription(filePath) {
  return openai.audio.transcriptions.create({
    file: fs.createReadStream(filePath),
    model: transcriptionModel,
    language: defaultLanguage,
    response_format: 'json',
  });
}

async function transcribeAudioFile(filePath) {
  const stat = await fs.promises.stat(filePath);
  if (stat.size <= directTranscriptionMaxBytes) {
    const transcription = await createTranscription(filePath);
    return {
      text: transcription.text || '',
      chunks: 1,
    };
  }

  return transcribeLargeAudioFile(filePath);
}

async function transcribeLargeAudioFile(filePath) {
  const chunkDir = await fs.promises.mkdtemp(
    path.join(os.tmpdir(), 'ultimate-audio-recorder-chunks-'),
  );
  try {
    const outputPattern = path.join(chunkDir, 'chunk_%03d.mp3');
    await execFileAsync(
      'ffmpeg',
      [
        '-hide_banner',
        '-loglevel',
        'error',
        '-y',
        '-i',
        filePath,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-b:a',
        '48k',
        '-f',
        'segment',
        '-segment_time',
        String(chunkSeconds),
        '-reset_timestamps',
        '1',
        outputPattern,
      ],
      { timeout: 30 * 60 * 1000 },
    );

    const chunkFiles = (await fs.promises.readdir(chunkDir))
      .filter((name) => name.endsWith('.mp3'))
      .sort()
      .map((name) => path.join(chunkDir, name));
    if (chunkFiles.length === 0) {
      throw new Error('No audio chunks were created.');
    }

    const parts = [];
    for (const chunkPath of chunkFiles) {
      const stat = await fs.promises.stat(chunkPath);
      if (stat.size > directTranscriptionMaxBytes) {
        throw new Error('A generated audio chunk is still too large.');
      }
      const transcription = await createTranscription(chunkPath);
      const text = transcription.text?.trim();
      if (text) parts.push(text);
    }

    return {
      text: parts.join('\n\n'),
      chunks: chunkFiles.length,
    };
  } finally {
    await fs.promises.rm(chunkDir, { recursive: true, force: true });
  }
}

app.get('/health', (_, res) => {
  res.json({ ok: true, service: 'ultimate-audio-recorder-backend' });
});

app.get('/me/entitlements', requireAuth, async (req, res) => {
  if (req.authProvider !== 'supabase' || !req.user?.id) {
    return res.status(401).json({ error: 'Authentification utilisateur requise.' });
  }
  try {
    const entitlement = await userEntitlement(req.user.id);
    res.json(entitlementPayload(entitlement));
  } catch (error) {
    console.error('Entitlement lookup failed:', error);
    res.status(500).json({ error: 'Droits utilisateur indisponibles.' });
  }
});

app.post('/billing/verify', requireAuth, async (req, res) => {
  if (req.authProvider !== 'supabase' || !req.user?.id) {
    return res.status(401).json({ error: 'Authentification utilisateur requise.' });
  }
  if (!supabaseAdmin) {
    return res.status(503).json({ error: 'Facturation serveur non configurée.' });
  }

  const productId = typeof req.body?.productId === 'string' ? req.body.productId : '';
  const purchaseToken =
    typeof req.body?.purchaseToken === 'string' ? req.body.purchaseToken : '';
  if (!productId || !purchaseToken) {
    return res.status(400).json({ error: 'Données d’achat manquantes.' });
  }

  try {
    const verified = await verifyGoogleSubscription(productId, purchaseToken);
    const existing = await userEntitlement(req.user.id);
    const tier = productId === proProductId ? 'pro' : 'plus';
    const isNewProPeriod =
      tier === 'pro' &&
      existing?.subscription_expires_at !== verified.expiryTime;
    const payload = {
      user_id: req.user.id,
      tier,
      subscription_product_id: productId,
      purchase_token_hash: crypto.createHash('sha256').update(purchaseToken).digest('hex'),
      subscription_expires_at: verified.expiryTime,
      credits_remaining:
        tier === 'pro'
          ? isNewProPeriod
            ? monthlyProCredits
            : existing?.credits_remaining || monthlyProCredits
          : 0,
      credits_reset_at: tier === 'pro' ? verified.expiryTime : null,
      updated_at: new Date().toISOString(),
    };
    const { data, error } = await supabaseAdmin
      .from('user_entitlements')
      .upsert(payload)
      .select('*')
      .single();
    if (error) throw error;
    res.json(entitlementPayload(data));
  } catch (error) {
    console.error('Purchase verification failed:', error);
    res.status(400).json({ error: 'Achat Google Play non valide.' });
  }
});

async function removeUserStorage(bucket, userId) {
  const { data, error } = await supabaseAdmin.storage
    .from(bucket)
    .list(userId, { limit: 1000 });
  if (error) throw error;
  const paths = (data || [])
    .filter((entry) => entry.name && entry.id)
    .map((entry) => `${userId}/${entry.name}`);
  if (paths.length === 0) return;
  const { error: removeError } = await supabaseAdmin.storage
    .from(bucket)
    .remove(paths);
  if (removeError) throw removeError;
}

app.delete('/account', requireAuth, async (req, res) => {
  if (req.authProvider !== 'supabase' || !req.user?.id) {
    return res.status(400).json({
      error: 'La suppression automatique exige un compte Supabase connecté.',
    });
  }
  if (!supabaseAdmin) {
    return res.status(503).json({
      error: 'Le service de suppression de compte n’est pas encore configuré.',
    });
  }

  try {
    const userId = req.user.id;
    await Promise.all([
      removeUserStorage('recordings-audio', userId),
      removeUserStorage('keyword-samples', userId),
    ]);
    const { error } = await supabaseAdmin.auth.admin.deleteUser(userId);
    if (error) throw error;
    res.json({ ok: true });
  } catch (error) {
    console.error('Account deletion failed:', error);
    res.status(500).json({ error: 'La suppression du compte a échoué.' });
  }
});

app.get('/diagnostics/openai', requireAuth, async (_, res) => {
  try {
    const [fileModel, realtimeModel] = await Promise.all([
      openai.models.retrieve(transcriptionModel),
      openai.models.retrieve(realtimeTranscriptionModel),
    ]);
    res.json({
      ok: true,
      transcriptionModel,
      realtimeTranscriptionModel,
      summaryModel,
      defaultLanguage,
      fileModel: fileModel.id,
      realtimeModel: realtimeModel.id,
    });
  } catch (error) {
    console.error('OpenAI diagnostics failed:', error);
    res.status(500).json({
      error: 'OpenAI diagnostics failed.',
      details: safeOpenAiError(error),
    });
  }
});

app.post('/transcribe', requireAuth, upload.single('audio'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'Missing audio file.' });
  }

  let chargedCredits = 0;
  try {
    if (!req.user?.id) {
      return res.status(401).json({ error: 'Authentification utilisateur requise.' });
    }
    const creditCost = await audioCreditCost(req.file.path);
    const creditsRemaining = await consumeCredits(req.user.id, creditCost);
    chargedCredits = creditCost;
    const transcription = await transcribeAudioFile(req.file.path);

    res.json({
      text: transcription.text || '',
      model: transcriptionModel,
      chunks: transcription.chunks,
      creditsUsed: chargedCredits,
      creditsRemaining,
    });
  } catch (error) {
    console.error('Transcription failed:', error);
    if (chargedCredits > 0 && req.user?.id) {
      await refundCredits(req.user.id, chargedCredits);
    }
    res.status(error?.status || 500).json({
      error: 'Transcription failed.',
      details: safeOpenAiError(error),
    });
  } finally {
    fs.promises.unlink(req.file.path).catch(() => {});
  }
});

app.post('/summarize', requireAuth, async (req, res) => {
  const text = typeof req.body?.text === 'string' ? req.body.text.trim() : '';
  if (!text) {
    return res.status(400).json({ error: 'Missing text.' });
  }

  try {
    if (!req.user?.id) {
      return res.status(401).json({ error: 'Authentification utilisateur requise.' });
    }
    await requireProEntitlement(req.user.id);
    const response = await openai.responses.create({
      model: summaryModel,
      input: [
        {
          role: 'system',
          content:
            'Tu es un assistant de prise de notes. Résume en français de façon claire, structurée et utile. Extrais aussi les décisions, tâches, dates et points importants quand ils existent.',
        },
        {
          role: 'user',
          content: text,
        },
      ],
    });

    res.json({
      summary: response.output_text || '',
      model: summaryModel,
    });
  } catch (error) {
    console.error('Summary failed:', error);
    res.status(error?.status || 500).json({
      error: 'Summary failed.',
      details: safeOpenAiError(error),
    });
  }
});

app.post('/realtime/transcription-session', requireAuth, async (_, res) => {
  try {
    const response = await fetch(
      'https://api.openai.com/v1/realtime/client_secrets',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${openaiApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          expires_after: {
            anchor: 'created_at',
            seconds: 600,
          },
          session: {
            type: 'transcription',
            audio: {
              input: {
                format: {
                  type: 'audio/pcm',
                  rate: 24000,
                },
                transcription: {
                  model: realtimeTranscriptionModel,
                  language: defaultLanguage,
                },
                noise_reduction: {
                  type: 'near_field',
                },
                turn_detection: null,
              },
            },
          },
        }),
        signal: AbortSignal.timeout(15000),
      },
    );

    const payload = await response.json();
    if (!response.ok) {
      console.error('Realtime session failed:', payload);
      return res.status(500).json({
        error: 'Realtime session failed.',
        details: {
          message:
            payload?.error?.message ||
            payload?.message ||
            'Realtime session was rejected by OpenAI.',
          status: response.status,
          type: payload?.error?.type || null,
          code: payload?.error?.code || null,
        },
      });
    }

    res.json(payload);
  } catch (error) {
    console.error('Realtime session failed:', error);
    res.status(500).json({
      error: 'Realtime session failed.',
      details: safeOpenAiError(error),
    });
  }
});

app.use((error, _, res, __) => {
  if (error?.code === 'LIMIT_FILE_SIZE') {
    return res.status(413).json({ error: 'Audio file is too large.' });
  }
  console.error('Unhandled error:', error);
  res.status(500).json({ error: 'Internal server error.' });
});

app.listen(port, () => {
  console.log(`Ultimate Audio Recorder backend listening on port ${port}`);
});
