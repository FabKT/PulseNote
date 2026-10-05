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
import { OAuth2Client } from 'google-auth-library';
import {
  removeStoragePaths,
  removeStoragePrefix,
} from './account-cleanup.js';
import {
  decodeDeveloperNotification,
  entitlementPayload,
  inactiveEntitlementUpdate,
  isEntitlementActive,
  shouldRefreshEntitlement,
  verifiedEntitlementUpdate,
} from './billing-entitlements.js';

const app = express();
const port = Number(process.env.PORT || 8787);
const execFileAsync = promisify(execFile);

const openaiApiKey = process.env.OPENAI_API_KEY;
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
const googlePubSubPushAudience = process.env.GOOGLE_PUBSUB_PUSH_AUDIENCE;
const googlePubSubPushServiceAccountEmail =
  process.env.GOOGLE_PUBSUB_PUSH_SERVICE_ACCOUNT_EMAIL;
const packageName = 'com.fabkt.ultimateaudiorecorder';
const plusProductId = 'ultimate_audio_recorder_plus_monthly';
const proProductId = 'ultimate_audio_recorder_pro_monthly';
const monthlyProCredits = 1000;
const directTranscriptionMaxBytes = 24 * 1024 * 1024;
const uploadMaxBytes = Number(process.env.MAX_AUDIO_UPLOAD_MB || 200) * 1024 * 1024;
// Une session temps reel OpenAI dure au plus 10 minutes : on debite d'avance
// un credit par minute de session, rembourse si la creation echoue.
const realtimeSessionSeconds = 600;
const realtimeSessionCredits = Math.ceil(realtimeSessionSeconds / 60);
const chunkSeconds = Number(process.env.TRANSCRIPTION_CHUNK_SECONDS || 600);

if (!openaiApiKey) {
  throw new Error('OPENAI_API_KEY is required.');
}

if (!supabaseUrl || !supabaseAnonKey) {
  console.warn(
    'SUPABASE_URL/SUPABASE_ANON_KEY not set: Supabase-authenticated clients will be rejected.',
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
const googleOidcClient = new OAuth2Client();

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
    const failure = new Error(
      purchase?.error?.message || 'Google Play verification failed.',
    );
    // 410 : jeton expire depuis longtemps, l'abonnement n'existe plus.
    if (response.status === 410) failure.inactive = true;
    throw failure;
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
    const failure = new Error('Subscription is not active.');
    failure.inactive = true;
    throw failure;
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

async function persistVerifiedEntitlement(row, verified) {
  const update = verifiedEntitlementUpdate(
    row,
    verified.expiryTime,
    monthlyProCredits,
  );
  const { data, error } = await supabaseAdmin
    .from('user_entitlements')
    .update(update)
    .eq('user_id', row.user_id)
    .select('*')
    .single();
  if (error) throw error;
  return data;
}

async function persistInactiveEntitlement(row) {
  const { data, error } = await supabaseAdmin
    .from('user_entitlements')
    .update(inactiveEntitlementUpdate())
    .eq('user_id', row.user_id)
    .select('*')
    .single();
  if (error) throw error;
  return data;
}

// Revalidation reguliere, y compris pendant la periode payee. Elle ramene un
// remboursement/retrait au palier Gratuit sous 15 minutes quand l'app appelle
// /me/entitlements. RTDN appelle la meme fonction immediatement.
async function refreshEntitlement(
  row,
  { force = false, throwOnTransient = false } = {},
) {
  if (!force && !shouldRefreshEntitlement(row)) return row;
  if (
    !row ||
    row.tier === 'free' ||
    !row.purchase_token ||
    !row.subscription_product_id
  ) return row;
  try {
    const verified = await verifyGoogleSubscription(
      row.subscription_product_id,
      row.purchase_token,
    );
    return persistVerifiedEntitlement(row, verified);
  } catch (error) {
    if (!error?.inactive) {
      console.error('Subscription refresh failed:', error);
      if (throwOnTransient) throw error;
      return row;
    }
    return persistInactiveEntitlement(row);
  }
}

async function userEntitlement(userId) {
  if (!supabaseAdmin) throw new Error('Supabase admin is not configured.');
  const { data, error } = await supabaseAdmin
    .from('user_entitlements')
    .select('*')
    .eq('user_id', userId)
    .maybeSingle();
  if (error) throw error;
  return refreshEntitlement(data);
}

async function requireProEntitlement(userId) {
  const entitlement = await userEntitlement(userId);
  if (entitlement?.tier !== 'pro' || !isEntitlementActive(entitlement)) {
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

// Limiteur en memoire par cle (IP ou utilisateur). Suffisant pour une seule
// instance ; au-dela, utiliser un stockage partage (Redis...).
function rateLimit({ windowMs, max, key }) {
  const hits = new Map();
  setInterval(() => {
    const now = Date.now();
    for (const [k, entry] of hits) {
      if (entry.resetAt <= now) hits.delete(k);
    }
  }, windowMs).unref();
  return (req, res, next) => {
    const now = Date.now();
    const k = key(req);
    let entry = hits.get(k);
    if (!entry || entry.resetAt <= now) {
      entry = { count: 0, resetAt: now + windowMs };
      hits.set(k, entry);
    }
    entry.count += 1;
    if (entry.count > max) {
      res.setHeader('Retry-After', Math.ceil((entry.resetAt - now) / 1000));
      return res.status(429).json({ error: 'Trop de requêtes, réessayez plus tard.' });
    }
    next();
  };
}

// Render / Cloud Run placent un proxy devant l'app : req.ip doit venir de
// X-Forwarded-For pour que la limite par IP soit pertinente.
app.set('trust proxy', 1);
app.use(
  rateLimit({ windowMs: 60_000, max: 120, key: (req) => `ip:${req.ip}` }),
);
const aiRateLimit = rateLimit({
  windowMs: 60 * 60_000,
  max: 60,
  key: (req) => `user:${req.user?.id || req.ip}`,
});

async function requireAuth(req, res, next) {
  const authorization = req.header('authorization') || '';
  const [, bearerToken] = authorization.match(/^Bearer\s+(.+)$/i) || [];
  // Seule l'authentification Supabase est acceptee : plus de jeton applicatif
  // partage (extractible de l'APK) ni de comptes Firebase de l'ancienne app.
  if (bearerToken && supabase) {
    try {
      const { data, error } = await supabase.auth.getUser(bearerToken);
      if (error || !data?.user) {
        throw error || new Error('No user for token.');
      }
      req.user = data.user;
      req.authProvider = 'supabase';
      return next();
    } catch (supabaseError) {
      console.warn('Supabase token rejected:', supabaseError?.message || supabaseError);
    }
  }
  return res.status(401).json({ error: 'Unauthorized' });
}

// Les routes IA payantes exigent un compte Supabase avec un abonnement Pro
// actif. Place avant multer pour ne pas recevoir un gros fichier pour rien.
async function requirePro(req, res, next) {
  if (req.authProvider !== 'supabase' || !req.user?.id) {
    return res.status(401).json({ error: 'Authentification utilisateur requise.' });
  }
  try {
    await requireProEntitlement(req.user.id);
    next();
  } catch (error) {
    if (!error?.status) console.error('Entitlement check failed:', error);
    res
      .status(error?.status || 500)
      .json({ error: error?.status ? error.message : 'Droits utilisateur indisponibles.' });
  }
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
  res.json({
    ok: true,
    service: 'ultimate-audio-recorder-backend',
    version: '2026-10-05-renewals',
  });
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

async function authenticateGooglePubSub(req) {
  if (!googlePubSubPushAudience || !googlePubSubPushServiceAccountEmail) {
    const error = new Error('Google Pub/Sub push authentication is not configured.');
    error.status = 503;
    throw error;
  }
  const authorization = req.header('authorization') || '';
  const [, idToken] = authorization.match(/^Bearer\s+(.+)$/i) || [];
  if (!idToken) {
    const error = new Error('Missing Google Pub/Sub identity token.');
    error.status = 401;
    throw error;
  }
  const ticket = await googleOidcClient.verifyIdToken({
    idToken,
    audience: googlePubSubPushAudience,
  });
  const payload = ticket.getPayload();
  if (
    payload?.email !== googlePubSubPushServiceAccountEmail ||
    payload?.email_verified !== true
  ) {
    const error = new Error('Unexpected Google Pub/Sub service account.');
    error.status = 401;
    throw error;
  }
}

// Endpoint Push Pub/Sub pour les Real-time developer notifications Google
// Play. Le jeton OIDC signe par Google empeche un tiers de modifier les droits.
app.post('/billing/google-play/rtdn', async (req, res) => {
  try {
    await authenticateGooglePubSub(req);
    if (!supabaseAdmin) {
      return res.status(503).json({ error: 'Facturation serveur non configuree.' });
    }
    const notification = decodeDeveloperNotification(req.body?.message?.data);
    if (!notification) return res.status(204).end();

    const tokenHash = crypto
      .createHash('sha256')
      .update(notification.purchaseToken)
      .digest('hex');
    const { data: entitlement, error } = await supabaseAdmin
      .from('user_entitlements')
      .select('*')
      .eq('purchase_token_hash', tokenHash)
      .maybeSingle();
    if (error) throw error;
    if (!entitlement) return res.status(204).end();

    await refreshEntitlement(entitlement, {
      force: true,
      throwOnTransient: true,
    });
    return res.status(204).end();
  } catch (error) {
    const status = Number(error?.status) || 500;
    console.error('Google Play RTDN processing failed:', error);
    return res.status(status).json({ error: 'Notification Google Play refusee.' });
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
      purchase_token: purchaseToken,
      subscription_expires_at: verified.expiryTime,
      subscription_last_verified_at: new Date().toISOString(),
      credits_remaining:
        tier === 'pro'
          ? isNewProPeriod
            ? monthlyProCredits
            : existing?.credits_remaining ?? monthlyProCredits
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

async function allFriendMessageAudioPaths(userId) {
  const paths = [];
  const pageSize = 1000;
  let from = 0;
  while (true) {
    const { data, error } = await supabaseAdmin
      .from('friend_messages')
      .select('audio_path')
      .or(`sender_id.eq.${userId},receiver_id.eq.${userId}`)
      .not('audio_path', 'is', null)
      .order('id', { ascending: true })
      .range(from, from + pageSize - 1);
    if (error) throw error;
    const rows = data || [];
    paths.push(...rows.map((row) => row.audio_path).filter(Boolean));
    if (rows.length < pageSize) break;
    from += rows.length;
  }
  return paths;
}

async function allOwnedFolderShares(userId) {
  const shares = [];
  const pageSize = 1000;
  let from = 0;
  while (true) {
    const { data, error } = await supabaseAdmin
      .from('folder_shares')
      .select('*')
      .eq('owner_id', userId)
      .order('id', { ascending: true })
      .range(from, from + pageSize - 1);
    if (error) throw error;
    const rows = data || [];
    shares.push(...rows);
    if (rows.length < pageSize) break;
    from += rows.length;
  }
  return shares;
}

async function preserveFriendsOwnContributions(userId) {
  const ownedShares = await allOwnedFolderShares(userId);

  for (const share of ownedShares) {
    if (share.mode === 'live') {
      const { data: contributions, error: contributionsError } =
        await supabaseAdmin
          .from('recordings')
          .select('id')
          .eq('folder_id', share.folder_id)
          .eq('user_id', share.recipient_id)
          .limit(1);
      if (contributionsError) throw contributionsError;

      if ((contributions || []).length > 0) {
        const folderId = crypto.randomUUID();
        const now = new Date().toISOString();
        const { error: folderError } = await supabaseAdmin
          .from('folders')
          .insert({
            id: folderId,
            user_id: share.recipient_id,
            name: share.folder_name,
            created_at: now,
            updated_at: now,
          });
        if (folderError) throw folderError;

        const { error: moveError } = await supabaseAdmin
          .from('recordings')
          .update({ folder_id: folderId, updated_at: now })
          .eq('folder_id', share.folder_id)
          .eq('user_id', share.recipient_id);
        if (moveError) throw moveError;
      }
    }

    const { error: deleteError } = await supabaseAdmin
      .from('folder_shares')
      .delete()
      .eq('id', share.id);
    if (deleteError) throw deleteError;
  }

  const { error: receivedDeleteError } = await supabaseAdmin
    .from('folder_shares')
    .delete()
    .eq('recipient_id', userId);
  if (receivedDeleteError) throw receivedDeleteError;
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
    await preserveFriendsOwnContributions(userId);
    const messageAudioPaths = await allFriendMessageAudioPaths(userId);
    await removeStoragePaths(
      supabaseAdmin.storage,
      'friend-audio',
      messageAudioPaths,
    );
    await Promise.all([
      removeStoragePrefix(supabaseAdmin.storage, 'recordings-audio', userId),
      removeStoragePrefix(supabaseAdmin.storage, 'keyword-samples', userId),
      removeStoragePrefix(supabaseAdmin.storage, 'friend-audio', userId),
    ]);
    const { error } = await supabaseAdmin.auth.admin.deleteUser(userId);
    if (error) throw error;
    res.json({ ok: true });
  } catch (error) {
    console.error('Account deletion failed:', error);
    res.status(500).json({ error: 'La suppression du compte a échoué.' });
  }
});

// ---------------------------------------------------------------------------
// Quitter un dossier partage
// ---------------------------------------------------------------------------
// Un dossier partage ne se supprime pas : on le quitte. La personne qui reste
// recoit une copie independante (fichiers dupliques, lignes a son nom) de ce
// qu'elle voyait, pour ne rien perdre si celui qui part supprime ses audios.

const recordingsBucket = 'recordings-audio';

// N'accepte que les fichiers ranges sous le prefixe de leur proprietaire :
// le service_role peut tout copier, une ligne forgee ne doit pas permettre de
// dupliquer le fichier d'un tiers.
function ownedStoragePath(recording) {
  const storagePath = recording?.storage_path;
  if (!storagePath || !storagePath.startsWith(`${recording.user_id}/`)) {
    return null;
  }
  return storagePath;
}

async function copyRecordingsTo(userId, folderId, sources) {
  const rows = [];
  const copiedPaths = [];
  try {
    for (const source of sources) {
      const sourcePath = ownedStoragePath(source);
      if (!sourcePath) continue;
      const id = crypto.randomUUID();
      const targetPath = `${userId}/${id}${path.extname(sourcePath) || '.m4a'}`;
      const { error } = await supabaseAdmin.storage
        .from(recordingsBucket)
        .copy(sourcePath, targetPath);
      if (error) throw error;
      copiedPaths.push(targetPath);
      rows.push({
        id,
        user_id: userId,
        storage_path: targetPath,
        created_at: source.created_at,
        duration_ms: source.duration_ms ?? null,
        trigger_source: source.trigger_source ?? null,
        waveform: source.waveform ?? [],
        display_name: source.display_name ?? null,
        is_favorite: false,
        folder_id: folderId,
        transcription: source.transcription ?? null,
        summary: source.summary ?? null,
        updated_at: new Date().toISOString(),
      });
    }
    if (rows.length > 0) {
      const { error } = await supabaseAdmin.from('recordings').insert(rows);
      if (error) throw error;
    }
  } catch (error) {
    if (copiedPaths.length > 0) {
      await supabaseAdmin.storage.from(recordingsBucket).remove(copiedPaths);
    }
    throw error;
  }
  return rows.length;
}

async function recordingsInFolder(folderId) {
  const { data, error } = await supabaseAdmin
    .from('recordings')
    .select('*')
    .eq('folder_id', folderId);
  if (error) throw error;
  return data || [];
}

async function snapshotSources(shareId) {
  const { data: items, error } = await supabaseAdmin
    .from('folder_share_items')
    .select('source_recording_id')
    .eq('share_id', shareId);
  if (error) throw error;
  const ids = (items || []).map((item) => item.source_recording_id);
  if (ids.length === 0) return [];
  const { data, error: recordingsError } = await supabaseAdmin
    .from('recordings')
    .select('*')
    .in('id', ids);
  if (recordingsError) throw recordingsError;
  return data || [];
}

async function deleteShare(shareId) {
  const { error } = await supabaseAdmin
    .from('folder_shares')
    .delete()
    .eq('id', shareId);
  if (error) throw error;
}

// Le destinataire part : le proprietaire garde une copie de ce que le
// destinataire avait ajoute ; les originaux redeviennent "sans dossier" chez
// le destinataire.
async function recipientLeavesShare(share) {
  if (share.mode === 'live') {
    const contributed = (await recordingsInFolder(share.folder_id)).filter(
      (recording) => recording.user_id === share.recipient_id,
    );
    await copyRecordingsTo(share.owner_id, share.folder_id, contributed);
    const { error } = await supabaseAdmin
      .from('recordings')
      .update({ folder_id: null, updated_at: new Date().toISOString() })
      .eq('folder_id', share.folder_id)
      .eq('user_id', share.recipient_id);
    if (error) throw error;
  }
  await deleteShare(share.id);
}

// Le proprietaire part : chaque destinataire recoit son propre dossier avec
// une copie de ce qu'il voyait, puis le dossier d'origine disparait et les
// audios du proprietaire redeviennent "sans dossier". Chaque partage est
// supprime des qu'il est traite : une nouvelle tentative apres une erreur ne
// duplique pas les copies deja faites.
async function ownerLeavesFolder(folderId) {
  const { data: shares, error } = await supabaseAdmin
    .from('folder_shares')
    .select('*')
    .eq('folder_id', folderId);
  if (error) throw error;
  // Releve unique : les ajouts d'un destinataire sont deplaces dans son
  // nouveau dossier au fil de la boucle, mais les autres doivent en recevoir
  // une copie (leurs fichiers ne bougent pas).
  const liveRecordings = await recordingsInFolder(folderId);

  for (const share of shares || []) {
    const recipientId = share.recipient_id;
    const newFolderId = crypto.randomUUID();
    const now = new Date().toISOString();
    const { error: folderError } = await supabaseAdmin.from('folders').insert({
      id: newFolderId,
      user_id: recipientId,
      name: share.folder_name,
      created_at: now,
      updated_at: now,
    });
    if (folderError) throw folderError;

    const visible =
      share.mode === 'live' ? liveRecordings : await snapshotSources(share.id);
    await copyRecordingsTo(
      recipientId,
      newFolderId,
      visible.filter((recording) => recording.user_id !== recipientId),
    );
    if (share.mode === 'live') {
      const { error: moveError } = await supabaseAdmin
        .from('recordings')
        .update({ folder_id: newFolderId, updated_at: now })
        .eq('folder_id', folderId)
        .eq('user_id', recipientId);
      if (moveError) throw moveError;
    }
    await deleteShare(share.id);
  }

  const { error: unfileError } = await supabaseAdmin
    .from('recordings')
    .update({ folder_id: null, updated_at: new Date().toISOString() })
    .eq('folder_id', folderId);
  if (unfileError) throw unfileError;
  const { error: deleteError } = await supabaseAdmin
    .from('folders')
    .delete()
    .eq('id', folderId);
  if (deleteError) throw deleteError;
}

app.post('/shares/:id/leave', requireAuth, async (req, res) => {
  if (req.authProvider !== 'supabase' || !req.user?.id) {
    return res.status(401).json({ error: 'Authentification utilisateur requise.' });
  }
  if (!supabaseAdmin) {
    return res.status(503).json({ error: 'Service de partage non configuré.' });
  }

  try {
    const userId = req.user.id;
    const { data: share, error } = await supabaseAdmin
      .from('folder_shares')
      .select('*')
      .eq('id', req.params.id)
      .maybeSingle();
    if (error) throw error;
    if (!share || ![share.owner_id, share.recipient_id].includes(userId)) {
      return res.status(404).json({ error: 'Dossier partagé introuvable.' });
    }

    if (share.owner_id === userId) {
      await ownerLeavesFolder(share.folder_id);
    } else {
      await recipientLeavesShare(share);
    }
    res.json({ ok: true, folderId: share.folder_id });
  } catch (error) {
    console.error('Leaving shared folder failed:', error);
    res.status(500).json({ error: 'Impossible de quitter ce dossier.' });
  }
});

app.post('/transcribe', requireAuth, requirePro, aiRateLimit, upload.single('audio'), async (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: 'Missing audio file.' });
  }

  let chargedCredits = 0;
  try {
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

app.post('/summarize', requireAuth, requirePro, aiRateLimit, async (req, res) => {
  const text = typeof req.body?.text === 'string' ? req.body.text.trim() : '';
  if (!text) {
    return res.status(400).json({ error: 'Missing text.' });
  }

  try {
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

app.post('/realtime/transcription-session', requireAuth, requirePro, aiRateLimit, async (req, res) => {
  let chargedCredits = 0;
  try {
    await consumeCredits(req.user.id, realtimeSessionCredits);
    chargedCredits = realtimeSessionCredits;
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
            seconds: realtimeSessionSeconds,
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
      await refundCredits(req.user.id, chargedCredits);
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

    res.json({ ...payload, creditsUsed: chargedCredits });
  } catch (error) {
    console.error('Realtime session failed:', error);
    if (chargedCredits > 0) {
      await refundCredits(req.user.id, chargedCredits);
    }
    res.status(error?.status || 500).json({
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
