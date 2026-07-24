import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import multer from 'multer';
import OpenAI from 'openai';
import admin from 'firebase-admin';

const app = express();
const port = Number(process.env.PORT || 8787);

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
const imageModel = process.env.IMAGE_MODEL || 'gpt-image-2';
const imageAnalysisModel = process.env.IMAGE_ANALYSIS_MODEL || 'gpt-4.1-mini';
const supportedMangaImageSizes = new Set(['1024x1536', '1536x1024']);
function normalizeMangaImageSize(value, fallback = '1024x1536') {
  const candidate = typeof value === 'string' ? value.trim() : '';
  return supportedMangaImageSizes.has(candidate) ? candidate : fallback;
}
function mangaImageSizeFromAspectRatio(value) {
  if (value === '3:2' || value === '4:3') return '1536x1024';
  if (value === '2:3') return '1024x1536';
  return '';
}
function normalizeMangaAspectRatio(value, requestedImageSize = imageSize) {
  if (value === '3:2' || value === '4:3') return '3:2';
  if (value === '2:3') return '2:3';
  return requestedImageSize === '1536x1024' ? '3:2' : '2:3';
}
const imageSize = normalizeMangaImageSize(process.env.IMAGE_SIZE);
const imageQuality = process.env.IMAGE_QUALITY || 'high';
const imageFormat = process.env.IMAGE_FORMAT || 'png';
const imageGenerationTimeoutMs = Number(process.env.IMAGE_GENERATION_TIMEOUT_MS || 300000);
const imageEditTimeoutMs = Number(process.env.IMAGE_EDIT_TIMEOUT_MS || 330000);
const imageAnalysisEnabled = process.env.IMAGE_ANALYSIS_ENABLED !== 'false';
const imageAnalysisTimeoutMs = Number(process.env.IMAGE_ANALYSIS_TIMEOUT_MS || 90000);
const referenceAnalysisCacheLimit = Number(process.env.REFERENCE_ANALYSIS_CACHE_LIMIT || 160);
const openAIImagePromptMaxLength = 32000;
const imageRequestMaxAttempts = Math.max(
  1,
  Math.min(4, Number(process.env.IMAGE_REQUEST_MAX_ATTEMPTS || 1)),
);
const mangaPageCreditCost = Number(process.env.CREDIT_COST_MANGA_PAGE || 10);
const characterCardCreditCost = Number(
  process.env.CREDIT_COST_CHARACTER_CARD || mangaPageCreditCost,
);
const sketchFinalCreditCost = Number(
  process.env.CREDIT_COST_SKETCH_FINAL || mangaPageCreditCost,
);
const mangaForgeEnabled = process.env.MANGA_FORGE_ENABLED !== 'false';
// Plafond dur d'OpenAI /images/edits (nombre d'images de référence en entrée).
const maxMangaReferenceImages = 16;
const defaultLanguage = process.env.DEFAULT_LANGUAGE || 'fr';
const firebaseProjectId = process.env.FIREBASE_PROJECT_ID || 'pulsenote-d2d85';

if (!openaiApiKey) {
  throw new Error('OPENAI_API_KEY is required.');
}

if (!appClientToken || appClientToken.length < 24) {
  throw new Error('APP_CLIENT_TOKEN must be a long random secret.');
}

const openai = new OpenAI({ apiKey: openaiApiKey });
admin.initializeApp({ projectId: firebaseProjectId });
const referenceAnalysisCache = new Map();

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
    fileSize: 25 * 1024 * 1024,
    files: 1,
  },
});

app.disable('x-powered-by');
app.use(cors({ origin: true }));
app.use(express.json({ limit: '60mb' }));

async function requireAuth(req, res, next) {
  const authorization = req.header('authorization') || '';
  const [, bearerToken] = authorization.match(/^Bearer\s+(.+)$/i) || [];
  if (bearerToken) {
    try {
      req.user = await admin.auth().verifyIdToken(bearerToken);
      return next();
    } catch (error) {
      console.warn('Firebase token rejected:', error?.message || error);
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
  const supportedExtensions = [
    '.flac',
    '.m4a',
    '.mp3',
    '.mp4',
    '.mpeg',
    '.mpga',
    '.oga',
    '.ogg',
    '.wav',
    '.webm',
  ];
  if (supportedExtensions.includes(fromName)) return fromName;

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

const mangaAssetRoles = new Set([
  'Character',
  'Background',
  'Object',
  'Storyboard',
  'Pose',
  'Style',
  'Inspiration',
  'Target',
  'Generated Page',
]);

const imageRoleCopy = {
  Character:
    'defines character identity only: face, hair, outfit, morphology, silhouette, expression baseline, aura, and distinctive traits; it does not define final pose, final expression, or panel position unless explicitly assigned',
  Background: 'defines decor, location, atmosphere, and allowed background complexity',
  Object: 'defines prop identity, shape, scale, and narrative ownership',
  Storyboard:
    'defines panel structure, framing, reading order, camera angles, panel functions, character placement, action order, and spatial relationships; it does not define final identity or style',
  Pose: 'defines body angle, gesture, limb placement, movement mechanics, and orientation only',
  Style:
    'defines rendering style, inking, screentone, hatching, contrast, color policy, and finish level only; it does not define identity, pose, composition, or narrative role',
  Inspiration:
    'influences only mood, energy, impact, motion feeling, or visual intensity; it must not override identity or structure',
  Target:
    'defines the existing image or page to preserve and modify directly: composition, panel geometry, existing style, correct elements, and targeted defects',
  'Generated Page':
    'defines the current generated page structure, panel geometry, style, and successful elements to preserve',
};

function cleanText(value, fallback = '') {
  return typeof value === 'string' ? value.trim() : fallback;
}

function clampPanelCount(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 6;
  return Math.min(12, Math.max(1, Math.round(parsed)));
}

function normalizeMangaRole(role) {
  const cleanRole = cleanText(role, 'Inspiration');
  return mangaAssetRoles.has(cleanRole) ? cleanRole : 'Inspiration';
}

function cleanImageDataUrl(value) {
  if (typeof value !== 'string') return '';
  const trimmed = value.trim();
  if (!/^data:image\/(png|jpe?g|webp);base64,/i.test(trimmed)) return '';
  return trimmed;
}

function normalizeMangaAssets(selectedAssets) {
  if (!Array.isArray(selectedAssets)) return [];
  return selectedAssets
    .map((asset) => ({
      id: cleanText(asset?.id),
      name: cleanText(asset?.name),
      role: normalizeMangaRole(asset?.role),
      imageDataUrl: cleanImageDataUrl(asset?.imageDataUrl),
      mimeType: cleanText(asset?.mimeType),
      imageWidth: Number.isFinite(Number(asset?.imageWidth)) ? Number(asset.imageWidth) : undefined,
      imageHeight: Number.isFinite(Number(asset?.imageHeight))
        ? Number(asset.imageHeight)
        : undefined,
      omitFromImageGeneration: Boolean(asset?.omitFromImageGeneration),
      characterId: cleanText(asset?.characterId),
      characterName: cleanText(asset?.characterName),
      characterProfile: cleanText(asset?.characterProfile),
      description: cleanText(asset?.description),
    }))
    .filter((asset) => asset.id && asset.name);
}

function normalizeMangaCharacters(characters) {
  if (!Array.isArray(characters)) return [];
  return characters
    .map((character) => ({
      id: cleanText(character?.id),
      name: cleanText(character?.name),
      storyRole: cleanText(character?.storyRole),
      identityLock: cleanText(character?.identityLock),
      defaultExpression: cleanText(character?.defaultExpression),
    }))
    .filter((character) => character.id && character.name);
}

function classifyMangaTask(input) {
  const text = `${input.prompt} ${input.editPrompt || ''}`.toLowerCase();

  if (input.operation === 'edit') {
    if (/\b(replace|swap|remplace|remplacer|changer le personnage)\b/.test(text)) {
      return 'strict_character_replacement';
    }
    if (/\b(correct|corrige|fix|repair|cibl|panel|case|bras|jambe|expression|pose)\b/.test(text)) {
      return 'targeted_correction';
    }
    return 'existing_image_modification';
  }

  if (/\b(storyboard|planche|panel|case|cases|page|layout|composition)\b/.test(text)) {
    return 'storyboard_page_creation';
  }

  return 'free_creation_with_references';
}

function inventoryMangaAssets(input) {
  const inventory = {
    identityRefs: [],
    structureRefs: [],
    inspirationRefs: [],
    postureRefs: [],
    styleRefs: [],
    targetRefs: [],
    backgrounds: [],
    objects: [],
  };

  for (const asset of input.selectedAssets) {
    if (asset.role === 'Character') {
      inventory.identityRefs.push(asset);
      continue;
    }
    if (asset.role === 'Background') {
      inventory.backgrounds.push(asset);
      continue;
    }
    if (asset.role === 'Object') {
      inventory.objects.push(asset);
      continue;
    }
    if (asset.role === 'Storyboard' || asset.role === 'Generated Page') {
      inventory.structureRefs.push(asset);
      continue;
    }
    if (asset.role === 'Pose') {
      inventory.postureRefs.push(asset);
      continue;
    }
    if (asset.role === 'Style') {
      inventory.styleRefs.push(asset);
      continue;
    }
    if (asset.role === 'Target') {
      inventory.targetRefs.push(asset);
      continue;
    }
    inventory.inspirationRefs.push(asset);
  }

  return inventory;
}

function assetLabel(asset) {
  const parts = [
    asset.imageLabel ? `${asset.imageLabel}: ${asset.name}` : asset.name,
    asset.characterName ? `character=${asset.characterName}` : '',
    asset.characterProfile ? `profile=${asset.characterProfile}` : '',
    asset.description ? `details=${asset.description}` : '',
  ].filter(Boolean);
  return parts.join(' | ');
}

function formatPromptList(items, fallback) {
  if (!items.length) return fallback;
  return items.map((item) => `- ${assetLabel(item)}`).join('\n');
}

function formatCharacterList(characters, fallback) {
  if (!characters.length) return fallback;
  return characters
    .map((character) =>
      [
        `- ${character.name}`,
        character.storyRole ? `  Role: ${character.storyRole}` : '',
        character.identityLock ? `  Identity: ${character.identityLock}` : '',
        character.defaultExpression ? `  Default expression: ${character.defaultExpression}` : '',
      ]
        .filter(Boolean)
        .join('\n'),
    )
    .join('\n');
}

function assignImageLabels(input, isModification) {
  let index = isModification && input.existingImageDataUrl ? 2 : 1;
  const labelledAssets = input.selectedAssets.map((asset) => {
    if (!asset.imageDataUrl) return asset;
    const imageLabel = `Input image ${index}`;
    index += 1;
    return { ...asset, imageLabel };
  });
  return {
    ...input,
    selectedAssets: labelledAssets,
    targetImageLabel: isModification && input.existingImageDataUrl ? 'Input image 1' : '',
  };
}

const STRUCTURE_ROLES = new Set(['Storyboard', 'Generated Page', 'Target']);

function mangaCharacterGroupKey(asset) {
  return asset.characterId || asset.characterName || asset.name || asset.id;
}

/**
 * Sélection équitable et plafonnée des images de référence.
 *
 * Contraintes (cf. plan produit) :
 *  - 16 images maximum (plafond dur d'OpenAI /images/edits) ;
 *  - une seule image de structure (storyboard / page générée / cible) ;
 *  - round-robin entre les personnages puis les références, afin qu'AUCUN
 *    personnage ne soit affamé si le budget est dépassé. Sous le budget, tout
 *    passe ; au-dessus, chaque personnage est représenté avant les extras.
 */
function selectMangaVisualAssets(input, limit = maxMangaReferenceImages) {
  if (limit <= 0) return [];

  const withImages = input.selectedAssets.filter((asset) => asset.imageDataUrl);
  const selected = [];
  const seen = new Set();
  const take = (asset) => {
    if (!asset || selected.length >= limit) return false;
    const key = asset.id || `${asset.role}:${asset.name}`;
    if (seen.has(key)) return false;
    seen.add(key);
    selected.push(asset);
    return true;
  };

  // 1) une seule image de structure
  const structure = withImages.find((asset) => STRUCTURE_ROLES.has(asset.role));
  if (structure) take(structure);

  // 2) groupes round-robin : un par personnage, puis un seau "références"
  const characterGroups = new Map();
  const referenceQueue = [];
  for (const asset of withImages) {
    if (asset === structure || STRUCTURE_ROLES.has(asset.role)) continue;
    if (asset.role === 'Character') {
      const key = mangaCharacterGroupKey(asset);
      if (!characterGroups.has(key)) characterGroups.set(key, []);
      characterGroups.get(key).push(asset);
    } else {
      referenceQueue.push(asset);
    }
  }

  const queues = [...characterGroups.values(), referenceQueue].filter((queue) => queue.length);
  let progressed = true;
  while (selected.length < limit && progressed) {
    progressed = false;
    for (const queue of queues) {
      if (!queue.length) continue;
      if (take(queue.shift())) progressed = true;
      if (selected.length >= limit) break;
    }
  }

  return selected;
}

// Compat : renvoie la sélection plafonnée (utilisé par l'analyse et le comptage).
function getMangaVisualAssets(input, limit = maxMangaReferenceImages) {
  return selectMangaVisualAssets(input, limit);
}

function extractResponseOutputText(payload) {
  if (typeof payload?.output_text === 'string') return payload.output_text.trim();

  const chunks = [];
  for (const output of payload?.output || []) {
    for (const content of output?.content || []) {
      if (typeof content?.text === 'string') chunks.push(content.text);
      if (typeof content?.value === 'string') chunks.push(content.value);
    }
  }

  return chunks.join('\n').trim();
}

function responseApiErrorMessage(status, payload) {
  const error = payload?.error;
  if (!error) return `OpenAI reference image analysis failed with status ${status}.`;
  return error.code
    ? `${error.message || 'OpenAI reference image analysis failed.'} (${error.code})`
    : error.message || 'OpenAI reference image analysis failed.';
}

async function requestOpenAIResponsePayload(body, timeoutMs, label) {
  let lastError;

  for (let attempt = 1; attempt <= imageRequestMaxAttempts; attempt += 1) {
    try {
      const response = await fetch('https://api.openai.com/v1/responses', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${openaiApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(timeoutMs),
      });
      const payload = await parseOpenAIImageResponse(response);

      if (response.ok) return payload;

      const message = responseApiErrorMessage(response.status, payload);
      if (
        attempt < imageRequestMaxAttempts &&
        retryableOpenAIImageStatuses.has(response.status)
      ) {
        console.warn(`${label} failed on attempt ${attempt}; retrying: ${message}`);
        await wait(retryDelayMs(attempt));
        continue;
      }

      throw new Error(message);
    } catch (error) {
      lastError = error;
      if (attempt < imageRequestMaxAttempts && isRetryableOpenAIImageError(error)) {
        console.warn(
          `${label} network error on attempt ${attempt}; retrying: ${errorText(error)}`,
        );
        await wait(retryDelayMs(attempt));
        continue;
      }

      throw error;
    }
  }

  throw lastError || new Error(`${label} failed.`);
}

function referenceAnalysisCacheKey(labelledInput, taskType) {
  const hash = crypto.createHash('sha256');
  hash.update(imageAnalysisModel);
  hash.update(taskType);
  hash.update(labelledInput.prompt || '');
  hash.update(labelledInput.editPrompt || '');
  hash.update(labelledInput.panelInstructions.join('|'));
  hash.update(labelledInput.targetImageLabel || '');
  hash.update(labelledInput.existingImageDataUrl || '');

  for (const asset of labelledInput.selectedAssets) {
    if (!asset.imageDataUrl) continue;
    hash.update(asset.imageLabel || '');
    hash.update(asset.name || '');
    hash.update(asset.role || '');
    hash.update(asset.omitFromImageGeneration ? 'analysis-only' : 'generation-input');
    hash.update(asset.characterName || '');
    hash.update(asset.characterProfile || '');
    hash.update(asset.description || '');
    hash.update(asset.imageDataUrl);
  }

  return hash.digest('hex');
}

function rememberReferenceAnalysis(key, value) {
  referenceAnalysisCache.set(key, value);
  if (referenceAnalysisCache.size <= referenceAnalysisCacheLimit) return;
  const oldestKey = referenceAnalysisCache.keys().next().value;
  if (oldestKey) referenceAnalysisCache.delete(oldestKey);
}

function buildReferenceAnalysisContent(labelledInput, taskType) {
  const content = [
    {
      type: 'input_text',
      text: [
        'Analyze the attached manga reference images for an image-generation prompt.',
        'Your job is not to describe everything. Identify only the visual facts that should influence the final manga page.',
        'The analysis must be self-contained: the final image prompt should remain useful even if the generator could not inspect the reference images.',
        'Some images may be analysis-only if their canvas ratio conflicts with the requested final output. In those cases, extract useful visual facts without preserving their outer page shape or ratio.',
        'References are allowed to strongly guide composition, poses, panel rhythm, expressions, and visual relationships according to their declared role.',
        'Before analyzing the images, classify each one by role and keep that role boundary strict.',
        'Apply this hierarchy when references conflict: explicit user instruction, target/current image for edits, user-assigned roles and identities, storyboard or structure, character identity, pose, inspiration, general style, then free interpretation.',
        'Never let an inspiration image override a character identity image, a storyboard image, panel geometry, role assignment, or dialogue.',
        'The final rendering style is controlled by the user style mode and STYLE LOCK, even when a reference is more detailed, shaded, or textured.',
        '',
        'Return compact markdown only. For each input image, use this exact structure:',
        '### Input image N - role / name',
        '- Essential visual facts:',
        '- Role-specific utility:',
        '- Foreground / midground / background cues:',
        '- Character posture, gaze, expression, and orientation cues:',
        '- Style, linework, color, lighting, and composition cues:',
        '- Prompt emphasis:',
        '- Boundaries / do not infer:',
        '- Self-contained prompt sentence:',
        '',
        'Respect the declared role of each image:',
        '- Character: extract identity, face, hair, outfit, silhouette, distinctive marks, expression baseline, posture, gaze, and traits to preserve.',
        '- Pose: extract body mechanics, limb placement, weight, gesture, orientation, camera angle, and motion, not identity.',
        '- Storyboard or Generated Page: extract panel layout, reading order, framing, gutters, foreground/background placement, action sequence, and relative composition.',
        '- Style: extract medium, linework, color policy, flatness, shading level, contrast, rendering finish, texture density, and whether the look is simple or detailed.',
        '- Background: extract location, decor, atmosphere, depth, perspective, foreground/background layers, and environmental constraints.',
        '- Object: extract prop shape, scale, material, position, ownership, and narrative function.',
        '- Target: extract what must be preserved and what can be changed.',
        '- Inspiration: extract mood, impact, energy, rhythm, and visual intensity only; do not copy identity or layout.',
        '',
        'For every image, identify only the points that the final prompt should insist on: posture, gaze, foreground, background, panel role, silhouette, expression, orientation, and relevant style cues.',
        'Make the written analysis strong enough that the final prompt can still work without relying on the image being re-read.',
        '',
        `Task type: ${mangaTaskLabel(taskType)}.`,
        `User prompt: ${cleanText(labelledInput.prompt) || '(empty)'}`,
        labelledInput.editPrompt
          ? `Edit prompt: ${cleanText(labelledInput.editPrompt)}`
          : '',
        labelledInput.panelInstructions.length
          ? `Panel notes: ${labelledInput.panelInstructions.map((line) => cleanText(line)).filter(Boolean).join(' | ')}`
          : '',
      ]
        .filter(Boolean)
        .join('\n'),
    },
  ];

  if (labelledInput.targetImageLabel && labelledInput.existingImageDataUrl) {
    content.push({
      type: 'input_text',
      text: `${labelledInput.targetImageLabel} metadata: role=Target / current generated page to modify. It defines the existing layout, successful elements, character placement, style, and what should be preserved unless the edit prompt says otherwise.`,
    });
    content.push({
      type: 'input_image',
      image_url: labelledInput.existingImageDataUrl,
      detail: 'high',
    });
  }

  const targetImageCount =
    labelledInput.targetImageLabel && labelledInput.existingImageDataUrl ? 1 : 0;
  const visualAssets = selectMangaVisualAssets(
    labelledInput,
    maxMangaReferenceImages - targetImageCount,
  );
  for (const asset of visualAssets) {
    if (!asset.imageDataUrl) continue;
    content.push({
      type: 'input_text',
      text: [
        `${asset.imageLabel} metadata:`,
        `name=${asset.name || 'untitled'}`,
        `role=${asset.role}`,
        `declared utility=${imageRoleCopy[asset.role]}`,
        asset.characterName ? `assigned character=${asset.characterName}` : '',
        asset.characterProfile ? `character profile=${asset.characterProfile}` : '',
        asset.description ? `user notes=${asset.description}` : '',
      ]
        .filter(Boolean)
        .join(' | '),
    });
    content.push({
      type: 'input_image',
      image_url: asset.imageDataUrl,
      detail: 'high',
    });
  }

  return content;
}

function countReferenceImages(labelledInput) {
  const count = labelledInput.targetImageLabel && labelledInput.existingImageDataUrl ? 1 : 0;
  return count + selectMangaVisualAssets(labelledInput, maxMangaReferenceImages - count).length;
}

async function analyzeMangaReferenceImages(input, taskType) {
  const isModification = [
    'existing_image_modification',
    'strict_character_replacement',
    'targeted_correction',
  ].includes(taskType);
  const labelledInput = assignImageLabels(input, isModification);

  if (!imageAnalysisEnabled || countReferenceImages(labelledInput) === 0) {
    return labelledInput;
  }

  const cacheKey = referenceAnalysisCacheKey(labelledInput, taskType);
  const cachedAnalysis = referenceAnalysisCache.get(cacheKey);
  if (cachedAnalysis) {
    return {
      ...labelledInput,
      referenceAnalysisText: cachedAnalysis,
    };
  }

  try {
    const payload = await requestOpenAIResponsePayload(
      {
        model: imageAnalysisModel,
        input: [
          {
            role: 'user',
            content: buildReferenceAnalysisContent(labelledInput, taskType),
          },
        ],
        max_output_tokens: 1800,
      },
      imageAnalysisTimeoutMs,
      'OpenAI manga reference image analysis',
    );
    const analysis = extractResponseOutputText(payload);
    if (!analysis) throw new Error('OpenAI returned no reference image analysis.');
    const cleanAnalysis = cleanText(analysis);
    rememberReferenceAnalysis(cacheKey, cleanAnalysis);
    return {
      ...labelledInput,
      referenceAnalysisText: cleanAnalysis,
    };
  } catch (error) {
    console.warn('Reference image analysis failed; continuing with attached images:', error);
    return {
      ...labelledInput,
      referenceAnalysisText:
        'Automatic visual analysis failed for this request. The attached reference images are still provided to the image model; use their declared roles, user notes, and character profiles as the fallback reference interpretation.',
    };
  }
}

function mangaTaskLabel(taskType) {
  const labels = {
    free_creation_with_references: 'creation / free composition with references',
    storyboard_page_creation: 'creation / manga page from storyboard-like instructions',
    existing_image_modification:
      'modification / preserve existing result and alter requested parts',
    strict_character_replacement: 'strict character replacement',
    targeted_correction: 'targeted correction',
  };
  return labels[taskType] || labels.free_creation_with_references;
}

function joinPromptLines(lines) {
  return lines.filter((line) => line !== '').join('\n');
}

function compactMiddleText(value, maxLength) {
  const text = cleanText(value);
  if (!maxLength || maxLength <= 0 || text.length <= maxLength) return text;
  if (maxLength < 200) return text.slice(0, maxLength).trim();
  const marker = '\n[Text condensed only to stay under the OpenAI image prompt size limit. Preserve all explicit requirements, roles, locks, identities, and surrounding context.]\n';
  const available = Math.max(0, maxLength - marker.length);
  const headLength = Math.ceil(available * 0.68);
  const tailLength = Math.max(0, available - headLength);
  const tail = tailLength > 0 ? text.slice(-tailLength).trim() : '';
  return `${text.slice(0, headLength).trim()}${marker}${tail}`;
}

function compactPromptList(items, fallback, maxLength) {
  return compactMiddleText(formatPromptList(items, fallback), maxLength);
}

function buildCompactMangaImagePrompt(context, maxLength = openAIImagePromptMaxLength) {
  const {
    taskType,
    isModification,
    labelledInput,
    inventory,
    characterNames,
    userRequest,
    canvasFormatLine,
    objectiveLine,
    panelGeometryLine,
    panelLines,
    imageRoleLines,
  } = context;

  const build = (budgets) =>
    joinPromptLines([
      'COMPACT BACKEND PLAN MODE:',
      'The complete manga generation plan exceeded the OpenAI image prompt size limit. This compact version preserves the same hierarchy, locks, and quality requirements with less repetition.',
      '',
      'OBJECTIVE:',
      objectiveLine,
      '',
      'CANVAS FORMAT LOCK:',
      canvasFormatLine,
      '',
      'USER REQUEST - HIGHEST PRIORITY:',
      compactMiddleText(userRequest, budgets.userRequest),
      '',
      'CHARACTER PROFILES:',
      compactMiddleText(
        formatCharacterList(labelledInput.characters, '- no explicit character profile provided'),
        budgets.characters,
      ),
      '',
      'PROVIDED IMAGE ROLES:',
      labelledInput.targetImageLabel
        ? `- ${labelledInput.targetImageLabel}: current generated page / target image to modify. Preserve composition, panel structure, successful elements, style, and unchanged details.`
        : '- no target image provided',
      compactMiddleText(
        imageRoleLines.length ? imageRoleLines.join('\n') : '- no imported image references selected',
        budgets.imageRoles,
      ),
      '',
      'REFERENCE IMAGE ANALYSIS - SELF-CONTAINED FACTS:',
      compactMiddleText(
        labelledInput.referenceAnalysisText ||
          '- no automatic visual reference analysis was produced for this request',
        budgets.referenceAnalysis,
      ),
      '',
      'REFERENCE HIERARCHY AND ROLE LOCK:',
      'Resolve conflicts in this order: explicit user instruction > target/current image for edits > user-assigned roles and identities > storyboard/structure > character identity > pose > inspiration > general style > free interpretation.',
      'Each image influences only its assigned role: character=identity; storyboard/layout=panel geometry/framing/action order; pose=body mechanics/orientation; style=rendering only; inspiration=mood/impact only; target=preserve/edit current image.',
      'Never let style or inspiration override identity, panel structure, role assignment, dialogue, pose locks, or the user request.',
      '',
      'IMAGE ROLE INVENTORY:',
      `Characters:\n${compactPromptList(inventory.identityRefs, '- none selected', budgets.inventory)}`,
      `Structure:\n${compactPromptList(
        inventory.structureRefs,
        '- inferred from prompt/workspace',
        budgets.inventory,
      )}`,
      `Pose:\n${compactPromptList(inventory.postureRefs, '- none selected', budgets.inventory)}`,
      `Style:\n${compactPromptList(inventory.styleRefs, '- default manga rendering', budgets.inventory)}`,
      `Inspiration:\n${compactPromptList(inventory.inspirationRefs, '- none selected', budgets.inventory)}`,
      `Background/Object:\n${compactMiddleText(
        [
          formatPromptList(inventory.backgrounds, '- no background reference'),
          formatPromptList(inventory.objects, '- no object reference'),
        ].join('\n'),
        budgets.inventory,
      )}`,
      '',
      'TASK TYPE LOCK:',
      mangaTaskLabel(taskType),
      '',
      'NON-NEGOTIABLE LOCKS:',
      characterNames.length > 1
        ? `${characterNames.join(' and ')} must never be swapped, fused, or mixed.`
        : 'Preserve selected character identity exactly; never replace with a generic manga character.',
      'Narrative roles are fixed: do not swap actor/observer/reactor/attacker/defender/object-holder.',
      'Panel functions, panel count, relative panel sizes, gutters, reading order, dominant panel, and panel geometry must remain readable.',
      panelGeometryLine,
      compactMiddleText(panelLines.join('\n'), budgets.panelLines),
      'Pose/action is mandatory: preserve gesture, body orientation, limb placement, hand placement, contact points, action direction, perspective, foreshortening, scale, and viewpoint.',
      'Back/profile/front/three-quarter views must stay as requested. Do not rotate the character for convenience.',
      'Keep both arms, both legs, hands, feet, shoulders, action-carrying limbs, silhouette, hair shape, clothing outline, build, and important props readable unless intentionally cropped.',
      'Expressions may change only where the prompt says so; identity remains locked.',
      'Dialogue must be exact text, correct language, correct speaker, correct bubble/panel placement; do not invent text.',
      '',
      'STYLE AND BACKGROUND LOCK:',
      labelledInput.styleMode === 'black-white'
        ? 'Finished black-and-white manga only: crisp ink, clean black fills, purposeful screentones/hatching, flat values, strong silhouettes, print-ready readability.'
        : labelledInput.styleMode === 'color'
          ? 'Finished original manga in color: crisp ink, disciplined cel-shaded color, readable silhouettes and values.'
          : 'Finished original manga. If black-and-white is requested or implied, do not use color; use crisp ink, clean fills, flat values, screentones/hatching only when useful.',
      'Avoid photorealism, glossy/painterly rendering, muddy greys, random noise, AI-smudge linework, and over-rendered grain unless explicitly requested.',
      labelledInput.backgroundLevel === 'empty'
        ? 'Background: empty or nearly empty unless explicitly required.'
        : labelledInput.backgroundLevel === 'minimal'
          ? 'Background: minimal decor only; no unwanted complex scenery.'
          : labelledInput.backgroundLevel === 'detailed'
            ? 'Background: detailed only where it supports readability and never overpowers characters/panel function.'
            : 'Background: obey requested level; avoid unwanted complex scenery.',
      '',
      isModification ? 'EDIT PRESERVATION LOCK:' : '',
      isModification
        ? 'The target image is the existing result to edit, not inspiration. Preserve layout, panel geometry, successful drawings, correct identities, correct expressions/action, speech bubbles, effects, background, and style unless explicitly changed.'
        : '',
      taskType === 'targeted_correction'
        ? 'TARGETED CORRECTION: apply only the named defect/area; keep unrelated panels, characters, pose, expression, background, dialogue, and style stable.'
        : '',
      taskType === 'strict_character_replacement'
        ? 'STRICT CHARACTER REPLACEMENT: replace only requested identity; preserve pose, perspective, orientation, limb placement, silhouette position, panel geometry, background, dialogue, effects, and target style.'
        : '',
      '',
      isModification ? 'PRESERVE:' : 'TARGETED PAGE INSTRUCTIONS:',
      isModification
        ? 'Preserve all correct/unchanged elements.'
        : compactMiddleText(labelledInput.prompt, budgets.targetedInstructions),
      '',
      isModification ? 'CHANGE:' : 'TARGETED PANEL INSTRUCTIONS:',
      isModification
        ? compactMiddleText(labelledInput.editPrompt || 'Apply only explicitly requested changes.', budgets.targetedInstructions)
        : compactMiddleText(panelLines.join('\n'), budgets.panelLines),
      '',
      'GOLDEN RULES:',
      'Do not genericize. Do not create a beautiful but different image. No identity swap/fusion. No missing limbs. No unrequested characters/props/background/text/color. The result must answer who, what action, where in panel/page, composition, style, and what remains unchanged.',
      '',
      'FINAL MANDATORY INSTRUCTION:',
      isModification
        ? `${canvasFormatLine} Modify only requested parts while preserving structure, successful elements, identity, exact pose/orientation, panel geometry, dialogue, background constraints, and original style unless explicitly changed.`
        : `${canvasFormatLine} Generate final manga artwork obeying identities, roles, panel functions, geometry, pose, orientation, perspective, silhouette, expression, dialogue, style, background, and all locks above.`,
    ]);

  const budgetSteps = [
    {
      userRequest: Infinity,
      characters: Infinity,
      imageRoles: Infinity,
      referenceAnalysis: Infinity,
      inventory: Infinity,
      panelLines: Infinity,
      targetedInstructions: Infinity,
    },
    {
      userRequest: Infinity,
      characters: 4500,
      imageRoles: 4500,
      referenceAnalysis: 9000,
      inventory: 3500,
      panelLines: 3500,
      targetedInstructions: 6000,
    },
    {
      userRequest: Infinity,
      characters: 2800,
      imageRoles: 2600,
      referenceAnalysis: 5500,
      inventory: 2200,
      panelLines: 2200,
      targetedInstructions: 3600,
    },
    {
      userRequest: Math.max(8000, Math.floor(maxLength * 0.46)),
      characters: 1800,
      imageRoles: 1600,
      referenceAnalysis: 3200,
      inventory: 1400,
      panelLines: 1400,
      targetedInstructions: 2200,
    },
  ];

  for (const budgets of budgetSteps) {
    const prompt = build(budgets);
    if (prompt.length <= maxLength) return prompt;
  }

  const reserve = 6500;
  const lastPrompt = build({
    userRequest: Math.max(3000, maxLength - reserve),
    characters: 900,
    imageRoles: 900,
    referenceAnalysis: 1400,
    inventory: 700,
    panelLines: 800,
    targetedInstructions: 1200,
  });

  return compactMiddleText(lastPrompt, maxLength);
}

function buildMangaImagePrompt(input) {
  const taskType = classifyMangaTask(input);
  const isModification = [
    'existing_image_modification',
    'strict_character_replacement',
    'targeted_correction',
  ].includes(taskType);
  const labelledInput = assignImageLabels(input, isModification);
  const inventory = inventoryMangaAssets(labelledInput);
  const characterNames = Array.from(
    new Set(
      [
        ...labelledInput.characters.map((character) => character.name),
        ...inventory.identityRefs.map((asset) => asset.characterName || asset.name),
      ].filter(Boolean),
    ),
  );
  const userRequest =
    labelledInput.operation === 'edit' && labelledInput.editPrompt
      ? labelledInput.editPrompt
      : labelledInput.prompt;
  const isLandscape = labelledInput.aspectRatio === '3:2';
  const canvasFormatLine = isLandscape
    ? 'Final image canvas must be landscape 3:2. Use the entire wide canvas as the manga spread itself. Do not draw a vertical page inside a horizontal white support. No blank side margins, no white padding, no poster frame, no centered portrait sheet.'
    : 'Final image canvas must be portrait 2:3. Use the entire vertical canvas as the manga page itself. Do not add an outer support, poster frame, or extra blank margins.';
  const objectiveLine = isModification
    ? "Modify the existing manga image according to the user's requested correction. Preserve all successful parts while matching the requested final canvas format."
    : isLandscape
      ? "Generate a finished horizontal 3:2 manga spread according to the user's request and selected references."
      : "Generate a finished vertical 2:3 manga page according to the user's request and selected references.";
  const panelGeometryLine = isLandscape
    ? `Create one horizontal manga spread in 3:2 with approximately ${labelledInput.panelCount} readable panels arranged across the full wide canvas. Reading direction: ${labelledInput.readingDirection}. The main action panel should be visually dominant unless the user explicitly says otherwise. Preserve clean gutters and reading order.`
    : `Create one vertical manga page in 2:3 with approximately ${labelledInput.panelCount} readable panels. Reading direction: ${labelledInput.readingDirection}. The main action panel should be visually dominant unless the user explicitly says otherwise. Preserve clean gutters and reading order.`;
  const panelLines = Array.from({ length: labelledInput.panelCount }, (_, index) => {
    const panel = index + 1;
    const userPanel = cleanText(labelledInput.panelInstructions?.[index]);
    if (userPanel) return `Panel ${panel}: ${userPanel}`;
    if (panel === 1) return 'Panel 1: establish the scene and character emotion.';
    if (panel === 2) return 'Panel 2: develop the main spatial relationship.';
    if (panel === 3) return 'Panel 3: show the decisive action beat.';
    if (panel === labelledInput.panelCount) {
      return `Panel ${panel}: deliver the final reaction or impact beat.`;
    }
    return `Panel ${panel}: continue the action while preserving readable character identities.`;
  });
  const imageRoleLines = labelledInput.selectedAssets
    .filter((asset) => asset.imageDataUrl)
    .map(
      (asset) =>
        `- ${asset.imageLabel}: ${asset.name} / role=${asset.role}. This image ${imageRoleCopy[asset.role]}. ${
          asset.characterName ? `Assigned character profile: ${asset.characterName}.` : ''
        } ${asset.description ? `User notes: ${asset.description}.` : ''}`.trim(),
    );

  const fullPrompt = joinPromptLines([
      'OBJECTIVE:',
      objectiveLine,
      '',
      'CANVAS FORMAT LOCK:',
      canvasFormatLine,
      isLandscape
        ? 'The generated artwork itself must be 3:2 landscape. Characters, panels, speech bubbles, gutters, backgrounds, motion lines, and composition must occupy the 3:2 canvas naturally.'
        : 'The generated artwork itself must be 2:3 portrait. Characters, panels, speech bubbles, gutters, backgrounds, motion lines, and composition must occupy the 2:3 canvas naturally.',
      '',
      'USER REQUEST:',
      userRequest,
      '',
      'CHARACTER PROFILES:',
      formatCharacterList(labelledInput.characters, '- no explicit character profile provided'),
      '',
      'DESCRIPTION OF PROVIDED IMAGES:',
      labelledInput.targetImageLabel
        ? `- ${labelledInput.targetImageLabel}: current generated page / target image to modify. It defines composition, panel structure, successful elements, style, and elements to preserve.`
        : '- no target image provided',
      imageRoleLines.length ? imageRoleLines.join('\n') : '- no imported image references selected',
      '',
      'REFERENCE IMAGE ANALYSIS - SELF-CONTAINED VISUAL FACTS:',
      labelledInput.referenceAnalysisText ||
        '- no automatic visual reference analysis was produced for this request',
      '',
      'REFERENCE ANALYSIS PRIORITY:',
      'Use the self-contained visual facts above as the written interpretation of the attached images. They identify what matters in each reference: identity, posture, gaze, foreground, background, style, composition, and role boundaries.',
      'Attached images remain authoritative visual references only when they are provided to the final image request. For analysis-only images, rely on the written analysis and never preserve their canvas shape.',
      'Do not invent details that contradict the analysis, user prompt, character profiles, or declared image roles.',
      '',
      'REFERENCE HIERARCHY LOCK:',
      'When references conflict, obey this strict order: explicit user instructions, target/current image for edits, user-assigned roles and identities, storyboard or structure references, character identity references, pose references, inspiration references, general style, then free interpretation.',
      'Each image may influence only the element assigned by its declared role. A character image defines identity, not final pose. A pose image defines body mechanics, not identity. A style image defines rendering, not composition. An inspiration image defines mood or impact only.',
      'Never let an inspiration or style reference replace identity, panel structure, role assignment, dialogue, pose locks, or the user request.',
      '',
      'IMAGE ROLE INVENTORY:',
      `Character identity references:\n${formatPromptList(
        inventory.identityRefs,
        '- none selected',
      )}`,
      `Storyboard / structure references:\n${formatPromptList(
        inventory.structureRefs,
        '- inferred from prompt and page workspace',
      )}`,
      `Posture references:\n${formatPromptList(inventory.postureRefs, '- none selected')}`,
      `Inspiration references:\n${formatPromptList(
        inventory.inspirationRefs,
        '- none selected',
      )}`,
      `Style references:\n${formatPromptList(
        inventory.styleRefs,
        '- default manga rendering',
      )}`,
      `Target / modification references:\n${formatPromptList(
        inventory.targetRefs,
        labelledInput.targetImageLabel
          ? `- ${labelledInput.targetImageLabel}: current generated page`
          : '- none selected',
      )}`,
      `Background references:\n${formatPromptList(
        inventory.backgrounds,
        '- use only prompt-requested decor',
      )}`,
      `Object references:\n${formatPromptList(inventory.objects, '- none selected')}`,
      '',
      'UTILITY OF EACH IMAGE ROLE:',
      'Target or existing-image references define what must be edited directly: preserved composition, panel geometry, successful elements, defects to correct, and existing style unless the user requests a style change.',
      'Character references define WHO the characters are: face, hair, outfit, morphology, silhouette, aura, expression baseline, and distinctive traits. They do not define final pose or final panel placement unless explicitly assigned.',
      'Storyboard or generated page references define HOW the page is organized: panel count, panel sizes, reading order, framing, camera angle, action order, character placement, and spatial relationships.',
      'Posture references define body angle, gesture, action mechanics, limb placement, perspective, and orientation only.',
      'Inspiration references influence only energy, mood, motion, or visual impact. They must not override identity, structure, roles, or dialogue.',
      'Style references define rendering direction, but the final amount of detail, 2D flatness, color policy, and shading level are controlled by STYLE LOCK.',
      'Background and object references define decor and props only.',
      'Text instructions override ambiguous image interpretation. Never let inspiration override identity, panel function, role assignment, or dialogue.',
      '',
      'TASK TYPE LOCK:',
      mangaTaskLabel(taskType),
      '',
      'BACKEND PLAN CHECKLIST:',
      'Before generating, resolve these points from the user prompt, image roles, and reference analysis: task type, involved characters, reference image assigned to each character, character role in the scene, panel structure, panel function, character position per panel, expression per panel, pose/action mechanics, camera angle, dialogue text, style mode, background level, and what must remain faithful versus what may change.',
      'If a detail is not specified, infer only what is necessary for a coherent manga page and do not override any explicit reference role or lock.',
      '',
      'IDENTITY LOCK:',
      characterNames.length > 1
        ? `${characterNames.join(
            ' and ',
          )} must never be swapped, fused, or visually mixed. Each character keeps only their own identity traits.`
        : 'Preserve the selected character identity traits exactly. Do not replace the selected character with a generic manga character.',
      'The reference image defines who the character is. The prompt and panel plan define what the character does.',
      '',
      'ROLE LOCK:',
      'The narrative roles are fixed by the prompt. Do not swap who acts, who observes, who reacts, who attacks, who defends, or who carries the important object.',
      '',
      'PANEL FUNCTION LOCK:',
      'Each panel has a fixed narrative function. Do not merge panel functions. Do not replace a specific panel function with a generic beautiful composition.',
      'Always define the function of each panel before deciding how characters are drawn inside that panel.',
      panelLines.join('\n'),
      '',
      'PANEL GEOMETRY LOCK:',
      panelGeometryLine,
      'Panel count, relative panel sizes, gutters, reading order, and the intended dominant panel must remain readable. Do not collapse the page into a single illustration unless the user explicitly asks.',
      inventory.structureRefs.length
        ? 'Use storyboard or structure references for panel geometry, framing, camera angle, action order, and spatial relationships. Do not copy rough anatomy from a storyboard if it conflicts with clean final anatomy.'
        : '',
      '',
      'POSE / ACTION LOCK:',
      'The requested pose, action mechanics, body angle, and gesture are not optional. Do not replace them with a generic pose.',
      inventory.postureRefs.length
        ? 'Pose references define action mechanics only. They do not define identity unless explicitly assigned as character references.'
        : '',
      '',
      'EXACT POSE LOCK:',
      'If a posture reference, storyboard, or prompt specifies a pose, keep the same core gesture, body orientation, limb placement, hand placement, contact points, and action direction. Clean the anatomy without changing the gesture.',
      '',
      'PERSPECTIVE LOCK:',
      'Preserve camera angle, foreshortening, scale, spatial direction, depth relationship, and viewpoint. Do not flatten a dramatic angle into a neutral view.',
      '',
      'BACK-VIEW / PROFILE / FRONT-VIEW LOCK:',
      'Back view stays back view, profile stays profile, front view stays front view, and three-quarter view stays three-quarter view. Do not rotate the character to make the drawing easier.',
      '',
      'LIMB PLACEMENT / ANATOMY LOCK:',
      'Do not omit important limbs. Both arms, both legs, hands, feet, shoulders, and action-carrying body parts must remain readable unless intentionally cropped by the panel. Do not lose the arm or leg that carries the action.',
      'Correct rough anatomy only where necessary for a polished manga result. Do not use anatomy cleanup as an excuse to change pose, gesture, camera angle, or role.',
      '',
      'SILHOUETTE LOCK:',
      'Preserve the recognizable silhouette of each character, including hair shape, clothing outline, body build, and important props. Silhouette must stay consistent across panels unless the action logically changes it.',
      '',
      'EXPRESSION LOCK:',
      'If the prompt gives a specific expression, it overrides a default expression from a character reference for that panel only. Identity remains unchanged.',
      '',
      'DIALOGUE LOCK:',
      'If dialogue is requested, reproduce the exact text, keep the requested language, assign each line to the correct speaker, and place each bubble in the correct panel. Do not invent dialogue.',
      '',
      'STYLE LOCK:',
      labelledInput.styleMode === 'black-white'
        ? 'Use finished professional black-and-white manga artwork. Do not use color. Use crisp ink, clean black fills, controlled hatching, purposeful screentones, clear line weight hierarchy, flat values, strong silhouettes, and print-ready page readability.'
        : labelledInput.styleMode === 'color'
          ? 'Use finished original manga artwork in color while preserving crisp ink, readable silhouettes, clear values, and disciplined cel-shaded color.'
          : 'Use finished original manga artwork. If black and white manga is requested or implied, do not use color. Use crisp ink, clean black fills, flat values, purposeful screentones, controlled hatching, clear line weight hierarchy, and readable silhouettes.',
      'Do not use photorealism, glossy rendering, painterly shading, muddy greys, random noisy texture, AI-smudge linework, or over-rendered grain unless explicitly requested.',
      '',
      'BACKGROUND LOCK:',
      labelledInput.backgroundLevel === 'empty'
        ? 'Keep backgrounds empty or nearly empty unless the prompt explicitly requires decor.'
        : labelledInput.backgroundLevel === 'minimal'
          ? 'Use minimal decor only. Do not add unwanted complex scenery.'
          : labelledInput.backgroundLevel === 'detailed'
            ? 'Use detailed decor only where it supports readability and does not overpower characters or panel function.'
            : 'Use only the requested level of decor. Do not add unwanted complex scenery. If the prompt asks for minimal or empty backgrounds, keep them minimal or empty.',
      '',
      'INSPIRATION IMAGE LOCK:',
      inventory.inspirationRefs.length
        ? 'Inspiration images may influence only mood, intensity, movement energy, or visual impact. Do not copy them literally and do not let them override character identity, page structure, role assignment, dialogue, or core composition.'
        : 'No inspiration image has priority over the user prompt or the character/structure locks.',
      '',
      isModification ? 'EXISTING IMAGE PRESERVATION LOCK:' : '',
      isModification
        ? 'The target/current image is not a loose inspiration. It is the existing result to edit. Preserve layout, panel geometry, successful drawings, correct character identities, correct expressions, correct action, speech bubble placement, effects, background, and style unless the user explicitly asks to change them.'
        : '',
      taskType === 'targeted_correction' ? 'TARGETED CORRECTION LOCK:' : '',
      taskType === 'targeted_correction'
        ? 'Apply only the named correction area or defect. Keep every unrelated panel, character, pose, expression, background, dialogue, and stylistic choice stable.'
        : '',
      taskType === 'strict_character_replacement' ? 'STRICT CHARACTER REPLACEMENT LOCK:' : '',
      taskType === 'strict_character_replacement'
        ? 'Replace only the requested character identity with the provided character reference. Preserve the original pose, perspective, orientation, limb placement, silhouette position, panel geometry, background, dialogue, effects, and style of the target image. Remove the old character identity completely without redesigning the scene.'
        : '',
      '',
      isModification ? 'PRESERVE:' : 'TARGETED PAGE INSTRUCTIONS:',
      isModification
        ? 'Preserve the existing layout, style, correct panels, correct character identities, successful composition, and any elements not named in the correction request.'
        : labelledInput.prompt,
      '',
      isModification ? 'CHANGE:' : 'TARGETED PANEL INSTRUCTIONS:',
      isModification
        ? labelledInput.editPrompt || 'Apply only the explicitly requested changes.'
        : panelLines.join('\n'),
      '',
      'GOLDEN RULES:',
      'Do not genericize the request. Do not make a beautiful but different image. Do not swap characters. Do not let a style or inspiration reference replace identity. Do not let identity references replace the requested pose or panel placement. Do not change dialogue. Do not omit important limbs. Do not add unnecessary backgrounds, props, characters, or text.',
      'The final image must answer who is shown, what action they perform, where they are in the panel/page, how the panel is composed, what style is used, and what must remain unchanged.',
      '',
      'RESTRICTIONS:',
      isModification
        ? 'Do not alter what is already correct. Do not regenerate the page from scratch unless the user explicitly asks.'
        : 'No identity swapping. No character fusion. No unwanted color if black-and-white manga is implied. No missing limbs. No random extra characters. No text changes unless dialogue is explicitly requested.',
      '',
      'FINAL MANDATORY INSTRUCTION:',
      isModification
        ? `${canvasFormatLine} Modify only the requested parts while preserving the current manga page structure, successful elements, identity fidelity, exact pose/orientation, panel geometry, dialogue, background constraints, and original style unless a style change was explicitly requested.`
        : `${canvasFormatLine} Generate the final manga artwork so the selected character identities, narrative roles, panel functions, panel geometry, pose mechanics, orientation, perspective, silhouette, expression, dialogue, style, and background level all follow the prompt and locks above.`,
    ]);

  if (fullPrompt.length <= openAIImagePromptMaxLength) {
    return {
      taskType,
      prompt: fullPrompt,
    };
  }

  return {
    taskType,
    prompt: buildCompactMangaImagePrompt(
      {
        taskType,
        isModification,
        labelledInput,
        inventory,
        characterNames,
        userRequest,
        canvasFormatLine,
        objectiveLine,
        panelGeometryLine,
        panelLines,
        imageRoleLines,
      },
      openAIImagePromptMaxLength,
    ),
  };
}

function extractImageDataUrl(responseJson) {
  const first = responseJson?.data?.[0];
  if (first?.b64_json) {
    return `data:image/${imageFormat};base64,${first.b64_json}`;
  }
  if (first?.url) return first.url;
  throw new Error('OpenAI returned no image data.');
}

function openAIImageErrorMessage(status, responseJson) {
  const error = responseJson?.error;
  if (!error) return `OpenAI image request failed with status ${status}.`;
  return error.code
    ? `${error.message || 'OpenAI image request failed.'} (${error.code})`
    : error.message || 'OpenAI image request failed.';
}

const retryableOpenAIImageStatuses = new Set([
  408,
  409,
  425,
  429,
  500,
  502,
  503,
  504,
  520,
  522,
  524,
]);

function wait(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function retryDelayMs(attempt) {
  return Math.min(1000 * 2 ** (attempt - 1), 8000);
}

function errorText(error) {
  return error?.message || String(error);
}

function isRetryableOpenAIImageError(error) {
  const name = (error?.name || '').toLowerCase();
  const message = errorText(error).toLowerCase();

  return (
    name.includes('abort') ||
    name.includes('timeout') ||
    message.includes('fetch failed') ||
    message.includes('terminated') ||
    message.includes('socket') ||
    message.includes('econnreset') ||
    message.includes('etimedout') ||
    message.includes('und_err')
  );
}

async function parseOpenAIImageResponse(response) {
  const contentType = response.headers.get('content-type') || '';
  if (contentType.includes('application/json')) {
    return response.json();
  }

  const text = await response.text();
  return {
    error: {
      message: text || 'OpenAI returned a non-JSON image response.',
    },
  };
}

async function requestOpenAIImagePayload(buildRequest, timeoutMs, label) {
  let lastError;

  for (let attempt = 1; attempt <= imageRequestMaxAttempts; attempt += 1) {
    try {
      const request = buildRequest();
      const response = await fetch(request.url, {
        ...request.init,
        signal: AbortSignal.timeout(timeoutMs),
      });
      const payload = await parseOpenAIImageResponse(response);

      if (response.ok) return payload;

      const message = openAIImageErrorMessage(response.status, payload);
      if (
        attempt < imageRequestMaxAttempts &&
        retryableOpenAIImageStatuses.has(response.status)
      ) {
        console.warn(`${label} failed on attempt ${attempt}; retrying: ${message}`);
        await wait(retryDelayMs(attempt));
        continue;
      }

      throw new Error(message);
    } catch (error) {
      lastError = error;
      if (attempt < imageRequestMaxAttempts && isRetryableOpenAIImageError(error)) {
        console.warn(
          `${label} network error on attempt ${attempt}; retrying: ${errorText(error)}`,
        );
        await wait(retryDelayMs(attempt));
        continue;
      }

      throw error;
    }
  }

  throw lastError || new Error(`${label} failed.`);
}

function dataUrlToImageBlob(dataUrl, fallbackName) {
  const match = /^data:(image\/(?:png|jpe?g|webp));base64,(.+)$/i.exec(dataUrl || '');
  if (!match) return null;
  const mimeType = match[1].toLowerCase().replace('image/jpg', 'image/jpeg');
  const extension = mimeType.includes('png') ? 'png' : mimeType.includes('webp') ? 'webp' : 'jpg';
  const bytes = Buffer.from(match[2], 'base64');
  const blob = new Blob([bytes], { type: mimeType });
  return {
    blob,
    filename: `${fallbackName || crypto.randomUUID()}.${extension}`,
  };
}

function buildMangaImageInputs(input, taskType) {
  const isModification = [
    'existing_image_modification',
    'strict_character_replacement',
    'targeted_correction',
  ].includes(taskType);
  const images = [];

  if (isModification && input.existingImageDataUrl) {
    const target = dataUrlToImageBlob(input.existingImageDataUrl, 'current-generated-page');
    if (target) images.push(target);
  }

  const remaining = Math.max(0, maxMangaReferenceImages - images.length);
  for (const asset of selectMangaVisualAssets(input, remaining)) {
    if (!asset.imageDataUrl) continue;
    const image = dataUrlToImageBlob(asset.imageDataUrl, asset.id || asset.name);
    if (image) images.push(image);
  }

  return images;
}

/**
 * Diagnostic retourné au client pour rendre chaque génération traçable :
 * longueur du prompt, compaction déclenchée, images réellement envoyées à
 * OpenAI, décompte par personnage, et personnages sous-représentés.
 */
function buildMangaDiagnostics(input, taskType, finalPrompt) {
  const isModification = [
    'existing_image_modification',
    'strict_character_replacement',
    'targeted_correction',
  ].includes(taskType);
  const targetImageCount = isModification && input.existingImageDataUrl ? 1 : 0;
  const selected = selectMangaVisualAssets(input, maxMangaReferenceImages - targetImageCount);

  const perCharacterImageCount = {};
  let structureImages = 0;
  let referenceImages = 0;
  for (const asset of selected) {
    if (asset.role === 'Character') {
      const key = asset.characterName || asset.name || asset.characterId || 'unknown';
      perCharacterImageCount[key] = (perCharacterImageCount[key] || 0) + 1;
    } else if (STRUCTURE_ROLES.has(asset.role)) {
      structureImages += 1;
    } else {
      referenceImages += 1;
    }
  }

  const providedCharacters = Array.isArray(input.characters)
    ? input.characters.map((character) => character.name).filter(Boolean)
    : [];
  const charactersWithoutImage = providedCharacters.filter(
    (name) => !perCharacterImageCount[name],
  );

  const providedImageCount = input.selectedAssets.filter((asset) => asset.imageDataUrl).length;
  const imagesSentToOpenAI = selected.length + targetImageCount;

  return {
    taskType,
    promptLength: finalPrompt.length,
    promptLimit: openAIImagePromptMaxLength,
    promptCompacted: finalPrompt.includes('COMPACT BACKEND PLAN MODE'),
    maxImages: maxMangaReferenceImages,
    providedImageCount,
    imagesSentToOpenAI,
    droppedImageCount: Math.max(0, providedImageCount + targetImageCount - imagesSentToOpenAI),
    structureImages,
    referenceImages,
    charactersUsed: Object.keys(perCharacterImageCount).length,
    perCharacterImageCount,
    charactersWithoutImage,
  };
}

async function requestMangaImageGeneration(finalPrompt, requestedImageSize = imageSize) {
  const size = normalizeMangaImageSize(requestedImageSize, imageSize);
  const payload = await requestOpenAIImagePayload(
    () => ({
      url: 'https://api.openai.com/v1/images/generations',
      init: {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${openaiApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: imageModel,
          prompt: finalPrompt,
          size,
          quality: imageQuality,
          output_format: imageFormat,
        }),
      },
    }),
    imageGenerationTimeoutMs,
    'OpenAI manga image generation',
  );

  return extractImageDataUrl(payload);
}

async function requestMangaImageEdit(finalPrompt, imageInputs, requestedImageSize = imageSize) {
  const size = normalizeMangaImageSize(requestedImageSize, imageSize);
  const payload = await requestOpenAIImagePayload(
    () => {
      const form = new FormData();
      form.append('model', imageModel);
      form.append('prompt', finalPrompt);
      form.append('size', size);
      form.append('quality', imageQuality);
      form.append('output_format', imageFormat);

      for (const image of imageInputs) {
        form.append('image[]', image.blob, image.filename);
      }

      return {
        url: 'https://api.openai.com/v1/images/edits',
        init: {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${openaiApiKey}`,
          },
          body: form,
        },
      };
    },
    imageEditTimeoutMs,
    'OpenAI manga image edit',
  );

  return extractImageDataUrl(payload);
}

async function requestMangaImage(finalPrompt, input, taskType) {
  const requestedImageSize = normalizeMangaImageSize(input.size, imageSize);
  const imageInputs = buildMangaImageInputs(input, taskType);
  if (imageInputs.length > 0) {
    return requestMangaImageEdit(finalPrompt, imageInputs, requestedImageSize);
  }
  return requestMangaImageGeneration(finalPrompt, requestedImageSize);
}

function normalizeCharacterCardReferences(references) {
  if (!Array.isArray(references)) return [];
  return references
    .map((reference) => ({
      id: cleanText(reference?.id),
      name: cleanText(reference?.name, 'Reference'),
      imageDataUrl: cleanImageDataUrl(reference?.imageDataUrl),
      mimeType: cleanText(reference?.mimeType),
      description: cleanText(reference?.description),
    }))
    .filter((reference) => reference.imageDataUrl);
}

function normalizeCharacterCardInput(body) {
  const requestedImageSize = normalizeMangaImageSize(
    body?.size || mangaImageSizeFromAspectRatio(body?.aspectRatio),
    '1536x1024',
  );

  return {
    prompt: cleanText(body?.prompt),
    identityImageDataUrl: cleanImageDataUrl(
      body?.identityImageDataUrl || body?.characterImageDataUrl || body?.baseImageDataUrl,
    ),
    identityReferenceName: cleanText(body?.identityReferenceName, 'Image A'),
    styleId: cleanText(body?.styleId, 'realistic'),
    styleName: cleanText(body?.styleName, 'Selected style'),
    styleDescription: cleanText(body?.styleDescription),
    styleImageDataUrl: cleanImageDataUrl(body?.styleImageDataUrl),
    structureImageDataUrl: cleanImageDataUrl(
      body?.structureImageDataUrl || body?.cardStructureImageDataUrl,
    ),
    references: normalizeCharacterCardReferences(body?.references),
    aspectRatio: normalizeMangaAspectRatio(body?.aspectRatio, requestedImageSize),
    size: requestedImageSize,
  };
}

function formatCharacterCardReferences(references) {
  if (!references.length) return '- none provided';
  return references
    .map((reference, index) =>
      [
        `- Extra reference ${index + 1}: ${reference.name}`,
        reference.description ? `  User role: ${reference.description}` : '',
        '  Use only the declared utility; do not replace Image A identity.',
      ]
        .filter(Boolean)
        .join('\n'),
    )
    .join('\n');
}

function is1990sCharacterStyle(input) {
  const styleId = cleanText(input?.styleId).toLowerCase();
  const styleName = cleanText(input?.styleName).toLowerCase();
  return (
    styleId === 'retro90' ||
    styleId === '1990s' ||
    styleId.includes('90') ||
    styleName.includes('90')
  );
}

function isClassicCharacterStyle(input) {
  const styleId = cleanText(input?.styleId).toLowerCase();
  const styleName = cleanText(input?.styleName).toLowerCase();
  return styleId === 'classic' || styleName.includes('classic') || styleName.includes('classique');
}

function isCurrentCharacterStyle(input) {
  const styleId = cleanText(input?.styleId).toLowerCase();
  const styleName = cleanText(input?.styleName).toLowerCase();
  return styleId === 'current' || styleName.includes('current') || styleName.includes('actuel');
}

function buildRealisticCharacterCardPrompt(input) {
  const userNotes = input.prompt || 'No extra user notes. Use Image A as the authoritative identity.';

  return [
    'You are generating a CHARACTER CARD / CHARACTER SHEET of a provided character.',
    '',
    'The final result must be a full STYLE CONVERSION and CHARACTER SHEET generation.',
    '',
    '--------------------------------------------------',
    '1. IMAGE ROLES',
    '--------------------------------------------------',
    '',
    'Image A is the mandatory CHARACTER IDENTITY REFERENCE.',
    '',
    'It defines:',
    '- who the character is;',
    '- the face identity;',
    '- the hairstyle identity;',
    '- the eye shape identity;',
    '- the hair color logic if visible;',
    '- the outfit identity if relevant;',
    '- the silhouette and overall character presence;',
    '- the apparent age unless the user explicitly requests otherwise.',
    '',
    'Image B, if provided, is the CHARACTER CARD STRUCTURE REFERENCE.',
    '',
    'It defines:',
    '- how the character sheet must be organized;',
    '- the layout logic;',
    '- the arrangement of full-body views;',
    '- the arrangement of expression portraits;',
    '- the spacing and overall presentation logic.',
    '',
    'Image C, if provided, is the TARGET STYLE REFERENCE.',
    '',
    'It defines:',
    '- linework finish;',
    '- realistic manga eye rendering;',
    '- hair rendering density;',
    '- monochrome value treatment;',
    '- facial construction and polish level.',
    '',
    'Important:',
    'Image A defines WHO the character is.',
    'Image B defines HOW the card must be organized.',
    'Image C defines HOW the selected style should feel.',
    'Do not copy the character from Image B or Image C.',
    '',
    '--------------------------------------------------',
    '2. CORE OBJECTIVE',
    '--------------------------------------------------',
    '',
    'Create a realistic black-and-white character card of the character shown in Image A.',
    '',
    'The final result must:',
    '- preserve the identity of Image A;',
    '- replace the original source style with a realistic target style;',
    '- present the character in a clean character card / character sheet format;',
    '- show the same character under multiple angles;',
    '- show the same character with multiple expressions;',
    '- maintain strict consistency across all views.',
    '',
    'This is NOT a request to preserve the original art style.',
    'This is a request to preserve the character identity and convert the rendering style.',
    '',
    '--------------------------------------------------',
    '3. IDENTITY / STYLE SEPARATION RULE',
    '--------------------------------------------------',
    '',
    'When Image A is provided, separate IDENTITY from STYLE.',
    '',
    'Preserve from Image A:',
    '- face identity;',
    '- hairstyle identity;',
    '- eye shape identity;',
    '- hair color logic if relevant;',
    '- outfit identity if relevant;',
    '- silhouette;',
    '- age impression;',
    '- overall recognizable character presence.',
    '',
    'Do NOT preserve from Image A:',
    '- the original rendering style;',
    '- the original line style;',
    '- the original shading style;',
    '- the original stylization level;',
    '- the original source-style proportions if they are style-dependent.',
    '',
    'Instead:',
    'fully redraw the same character in the target REALISTIC STYLE defined below.',
    '',
    'Important:',
    'The reference image defines WHO the character is.',
    'It does NOT define the final rendering style.',
    '',
    'The final result must clearly read as:',
    'the same character, but fully redrawn in a realistic style.',
    '',
    '--------------------------------------------------',
    '4. TARGET STYLE: REALISTIC',
    '--------------------------------------------------',
    '',
    'The target style is a refined semi-realistic black-and-white manga / manhwa style.',
    '',
    'It must NOT be photorealistic.',
    'It must remain clearly illustrated and manga-based.',
    '',
    'The style must be:',
    '- more realistic than standard anime;',
    '- more anatomically grounded than simplified manga;',
    '- more mature and refined than a flat modern manga style;',
    '- highly polished;',
    '- clean and elegant.',
    '',
    'The final rendering must include:',
    '',
    'FACE:',
    '- semi-realistic facial construction;',
    '- believable facial planes;',
    '- subtle cheek, jaw, chin, and nose bridge structure;',
    '- refined but not exaggerated realism;',
    '- mature and visually credible proportions.',
    '',
    'EYES:',
    '- detailed manga eyes;',
    '- expressive and elegant;',
    '- clearly illustrated, not photographic;',
    '- defined upper eyelids;',
    '- readable iris and pupil structure;',
    '- subtle internal eye detail;',
    '- delicate lower eyelid treatment;',
    '- rich but controlled eye rendering.',
    '',
    'Important eye rules:',
    '- the eyes must remain manga-based;',
    '- they must not become oversized old-school anime eyes;',
    '- they must not become flat simplified manga eyes;',
    '- they must not become realistic photographic human eyes.',
    '',
    'NOSE:',
    '- more realistic than simplified anime;',
    '- delicate and properly integrated into the face;',
    '- subtle bridge and nostril information;',
    '- refined shading;',
    '- elegant and understated.',
    '',
    'MOUTH:',
    '- natural and controlled;',
    '- thin to medium line treatment;',
    '- understated and believable;',
    '- emotionally precise.',
    '',
    'HAIR:',
    '- preserve hairstyle identity;',
    '- preserve black hair if the character has black hair;',
    '- use grouped strands and layered locks;',
    '- rich but controlled detail;',
    '- dimensional and elegant hair rendering;',
    '- not flat anime blocks;',
    '- not photographic individual-hair realism.',
    '',
    'ANATOMY:',
    '- slender, believable, elegant anatomy;',
    '- coherent shoulders, neck, torso, and limbs;',
    '- stable body proportions across all angles;',
    '- readable hands;',
    '- mature and well-constructed body logic.',
    '',
    'CLOTHING:',
    '- preserve outfit identity if relevant;',
    '- clothing must be consistent across all views;',
    '- clothing must be structurally believable;',
    '- folds must be controlled and elegant;',
    '- values must be clean and readable.',
    '',
    'If the desired outfit look is clean:',
    '- use plain, unified value masses;',
    '- minimize grain;',
    '- avoid dirty texture noise on the clothes;',
    '- avoid unnecessary visual clutter.',
    '',
    'LINEART:',
    '- clean;',
    '- elegant;',
    '- polished;',
    '- readable;',
    '- controlled line weight variation.',
    '',
    'SHADING:',
    '- black-and-white only unless otherwise requested;',
    '- refined grayscale or screentone-like rendering;',
    '- controlled shadows;',
    '- subtle volume modeling;',
    '- clear value hierarchy;',
    '- polished monochrome finish.',
    '',
    'BACKGROUND:',
    '- plain, minimal, or very clean;',
    '- never distracting;',
    '- appropriate for a character reference sheet.',
    '',
    '--------------------------------------------------',
    '5. CHARACTER CARD FORMAT',
    '--------------------------------------------------',
    '',
    'The final output must be a CHARACTER CARD / CHARACTER SHEET.',
    '',
    'If Image B is provided, follow its structure strictly.',
    '',
    'If no structure reference is provided, use the following default structure:',
    '',
    '- 3:2 format.',
    '- Clean white or very light neutral background.',
    '- Top row: three full-body views of the same character:',
    '  1. front view',
    '  2. back view',
    '  3. side/profile view',
    '- Bottom row: five bust or head-and-shoulders portraits of the same character with different expressions:',
    '  1. content / lightly pleased',
    '  2. very happy',
    '  3. neutral',
    '  4. angry',
    '  5. sad',
    '',
    'The card must be:',
    '- clean;',
    '- balanced;',
    '- organized;',
    '- easy to read;',
    '- visually coherent.',
    '',
    '--------------------------------------------------',
    '6. CONSISTENCY RULES',
    '--------------------------------------------------',
    '',
    'All views and portraits must clearly depict the SAME character.',
    '',
    'This consistency is mandatory across:',
    '- face identity;',
    '- hairstyle;',
    '- age impression;',
    '- body build;',
    '- outfit;',
    '- proportions;',
    '- style rendering.',
    '',
    'Front view:',
    '- must clearly show the full outfit from the front;',
    '- must preserve identity and silhouette.',
    '',
    'Back view:',
    '- must clearly show the hairstyle from the back;',
    '- must clearly show the outfit from the back;',
    '- must maintain exact same body proportions.',
    '',
    'Side/profile view:',
    '- must clearly show the facial profile;',
    '- must preserve hairstyle silhouette;',
    '- must preserve outfit profile construction.',
    '',
    'Expression portraits:',
    '- must remain fully recognizable as the same character;',
    '- only the expression should change;',
    '- identity must remain locked.',
    '',
    'Expression logic:',
    '- content / lightly pleased = restrained soft smile;',
    '- very happy = open cheerful smile;',
    '- neutral = calm, composed, serious;',
    '- angry = tenser brows, sharper gaze, firmer mouth;',
    '- sad = softer eyes, subdued mouth, slight emotional heaviness.',
    '',
    'Do not let the expressions distort the identity.',
    '',
    '--------------------------------------------------',
    '7. STRUCTURE LOCK',
    '--------------------------------------------------',
    '',
    'If Image B is provided:',
    '- preserve its organizational logic;',
    '- preserve its top/bottom arrangement;',
    '- preserve its general composition system;',
    '- preserve its readability and card-like presentation.',
    '',
    'Do NOT copy the character shown in Image B.',
    'Only use Image B for structure and layout.',
    '',
    'If Image B is not provided:',
    '- use the default structure described above.',
    '',
    '--------------------------------------------------',
    '8. STYLE CONVERSION LOCK',
    '--------------------------------------------------',
    '',
    'This request requires STYLE CONVERSION.',
    '',
    'The final image must NOT look like:',
    '- the original source style placed onto a sheet;',
    '- the original art style with minor modifications;',
    '- the source drawing simply copied.',
    '',
    'Instead, the final image must look like:',
    '- the same character identity,',
    '- fully redesigned and redrawn,',
    '- in the target realistic black-and-white manga / manhwa character-card style.',
    '',
    'Mandatory rule:',
    'Preserve the identity.',
    'Replace the style.',
    '',
    'The original source style must disappear.',
    'The realistic target style must dominate the entire final sheet.',
    '',
    '--------------------------------------------------',
    '9. RESTRICTIONS',
    '--------------------------------------------------',
    '',
    'Do not:',
    '- preserve the original source style;',
    '- make the result photorealistic;',
    '- make the face too flat or too anime-simplified;',
    '- make the eyes too large in a 90s anime way;',
    '- make the nose tiny and symbolic;',
    '- generate different-looking versions of the character across the sheet;',
    '- change the outfit design between views;',
    '- add noisy texture or grain on clothes if a clean result is expected;',
    '- add decorative background elements;',
    '- add extra props unless requested;',
    '- add extra character views unless requested.',
    '',
    'Very important:',
    'Do not add text unless explicitly requested.',
    'By default:',
    '- no title;',
    '- no labels;',
    '- no captions;',
    '- no measurements;',
    '- no annotations;',
    '- no notes;',
    '- no decorative typography.',
    '',
    '--------------------------------------------------',
    '10. USER NOTES AND EXTRA REFERENCES',
    '--------------------------------------------------',
    '',
    'User notes:',
    userNotes,
    '',
    'Extra references:',
    formatCharacterCardReferences(input.references),
    '',
    'Extra references may define outfit details, accessories, or visual notes only when their description says so.',
    'They must never override Image A identity, Image B structure, or the selected realistic style.',
    '',
    '--------------------------------------------------',
    '11. FINAL MANDATORY INSTRUCTION',
    '--------------------------------------------------',
    '',
    'Generate a complete 3:2 realistic black-and-white character card of the same character shown in Image A.',
    '',
    'Preserve from Image A:',
    '- the identity;',
    '- the face;',
    '- the hairstyle;',
    '- the eye shape;',
    '- the character presence;',
    '- the outfit identity if relevant.',
    '',
    'Do NOT preserve the original rendering style of Image A.',
    '',
    'Fully convert the character into a refined semi-realistic manga / manhwa style, with:',
    '- realistic facial construction;',
    '- detailed manga eyes;',
    '- elegant anatomy;',
    '- refined lineart;',
    '- clean monochrome shading;',
    '- mature and polished presentation.',
    '',
    'The final character card must show:',
    '- full-body front view;',
    '- full-body back view;',
    '- full-body side/profile view;',
    '- and five expression portraits:',
    '  content / lightly pleased,',
    '  very happy,',
    '  neutral,',
    '  angry,',
    '  sad.',
    '',
    'If Image B is provided, organize the card according to Image B.',
    'If Image B is not provided, use the default clean character-sheet structure.',
    '',
    'The final result must clearly read as:',
    'the same input character, fully redrawn in a realistic style, and presented as a clean professional character card.',
  ].join('\n');
}

function build1990sCharacterCardPrompt(input) {
  const userNotes =
    input.prompt || 'No extra user instructions. Use Image A as the authoritative identity.';

  return [
    '1990s CHARACTER CARD BACKEND PROMPT',
    'WITH MANDATORY STYLE IMAGE REFERENCE',
    '',
    'You are generating a CHARACTER CARD / CHARACTER SHEET of a provided character.',
    '',
    'The final result must be a full STYLE CONVERSION and CHARACTER SHEET generation.',
    '',
    'The backend receives:',
    '- Image A: a character identity reference image;',
    '- Image B: a mandatory 1990s manga / anime style reference image;',
    '- Image C, if provided: a character-card structure reference image;',
    '- extra user instructions, if provided.',
    '',
    'The final output must convert the provided character into the 1990s manga / anime style shown in Image B and described in this backend prompt.',
    '',
    '--------------------------------------------------',
    '1. IMAGE ROLES',
    '--------------------------------------------------',
    '',
    'Image A is the mandatory CHARACTER IDENTITY REFERENCE.',
    '',
    'It defines:',
    '- who the character is;',
    '- the face identity;',
    '- the hairstyle identity;',
    '- the original eye shape identity before style conversion;',
    '- the hair color logic if visible or specified;',
    '- the outfit identity if relevant;',
    '- the silhouette and overall character presence;',
    '- the apparent age unless the user explicitly requests otherwise.',
    '',
    'Image B is the mandatory 1990s STYLE REFERENCE.',
    '',
    'It defines the target visual style that the final character card must follow.',
    '',
    'Image B controls:',
    '- the 1990s manga / anime face stylization;',
    '- the larger eye size;',
    '- the classic old-school manga eye structure;',
    '- the large iris / pupil logic;',
    '- the visible bright highlight inside the pupils / irises;',
    '- the simplified small nose;',
    '- the small simple mouth;',
    '- the flatter and simpler face construction;',
    '- the old-school manga / anime rendering logic;',
    '- the black-and-white lineart and value treatment;',
    '- the simplified hair treatment;',
    '- the overall 1990s character-design feeling.',
    '',
    'Image C, if provided, is the CHARACTER CARD STRUCTURE REFERENCE.',
    '',
    'It defines:',
    '- how the character sheet must be organized;',
    '- the layout logic;',
    '- the arrangement of full-body views;',
    '- the arrangement of expression portraits;',
    '- the spacing and overall presentation logic.',
    '',
    'Important:',
    'Image A defines WHO the character is.',
    'Image B defines the TARGET 1990s STYLE.',
    'Image C defines HOW the card is organized.',
    'Do not confuse these roles.',
    '',
    '--------------------------------------------------',
    '2. CORE OBJECTIVE',
    '--------------------------------------------------',
    '',
    'Create a 1990s black-and-white manga / anime character card of the character shown in Image A.',
    '',
    'The final result must:',
    '- preserve the identity of Image A;',
    '- remove the original source style of Image A;',
    '- fully convert the character into the 1990s manga / anime target style shown in Image B;',
    '- follow the 1990s backend style rules described below;',
    '- present the character in a clean character card / character sheet format;',
    '- show the same character under multiple angles;',
    '- show the same character with multiple expressions;',
    '- maintain strict consistency across all views.',
    '',
    'This is NOT a request to preserve the original art style of Image A.',
    'This is a request to preserve the character identity from Image A and convert the rendering style into the 1990s manga / anime style of Image B.',
    '',
    '--------------------------------------------------',
    '3. IDENTITY / STYLE SEPARATION RULE',
    '--------------------------------------------------',
    '',
    'When Image A is provided, separate IDENTITY from STYLE.',
    '',
    'Preserve from Image A:',
    '- face identity;',
    '- hairstyle identity;',
    '- hair color logic if relevant;',
    '- outfit identity if relevant;',
    '- silhouette;',
    '- age impression;',
    '- overall recognizable character presence.',
    '',
    'Do NOT preserve from Image A:',
    '- the original rendering style;',
    '- the original realism level;',
    '- the original eye rendering if it conflicts with the 1990s style;',
    '- the original nose rendering if it conflicts with the 1990s style;',
    '- the original shading style;',
    '- the original line style;',
    '- the original stylization level.',
    '',
    'Instead, fully redraw the same character in the target 1990s style defined by Image B and this backend prompt.',
    '',
    'Image A defines WHO the character is.',
    'Image A does NOT define the final rendering style.',
    'Image B and this backend prompt define HOW the final image must look.',
    '',
    'The final result must clearly read as: the same character from Image A, but fully redrawn in the 1990s manga / anime style shown in Image B.',
    '',
    '--------------------------------------------------',
    '4. 1990s STYLE REFERENCE LOCK',
    '--------------------------------------------------',
    '',
    'Image B is mandatory and must strongly influence the final visual result.',
    '',
    'Use Image B as the visual anchor for:',
    '- large classic 1990s manga / anime eyes;',
    '- large irises / pupils;',
    '- visible bright highlights inside the eyes;',
    '- simplified facial planes;',
    '- very small nose;',
    '- small simple mouth;',
    '- clean old-school lineart;',
    '- simplified but expressive face design;',
    '- black-and-white manga rendering;',
    '- simplified hair rendering;',
    '- iconic 1990s character-design logic.',
    '',
    'Do not treat Image B as optional inspiration.',
    'The final image must look visually compatible with Image B.',
    'The backend prompt explains the style. Image B shows the style. Both must be followed together.',
    'If Image A has a conflicting source style, ignore the source style and prioritize Image B.',
    '',
    '--------------------------------------------------',
    '5. TARGET STYLE: 1990s MANGA / ANIME',
    '--------------------------------------------------',
    '',
    'The target style is a classic 1990s manga / anime style.',
    '',
    'It must NOT be realistic.',
    'It must NOT be photorealistic.',
    'It must NOT be modern semi-realistic manga.',
    'It must NOT be glossy webtoon.',
    '',
    'The style must be:',
    '- older-generation manga / anime;',
    '- clean;',
    '- iconic;',
    '- expressive;',
    '- simplified;',
    '- black-and-white;',
    '- readable;',
    '- emotionally direct;',
    '- visually close to 1990s anime character design.',
    '',
    'FACE CONSTRUCTION:',
    '- simplified and stylized face;',
    '- cleaner and flatter facial planes;',
    '- reduced realistic depth;',
    '- smooth face areas;',
    '- less anatomical detail than realistic manga;',
    '- slightly softer and more iconic face shape;',
    '- classic old-school manga / anime proportions;',
    '- simple but elegant facial structure.',
    '',
    'The face must NOT have heavy realistic cheekbone modeling, deep realistic facial planes, highly rendered lips, realistic nose bridge modeling, modern webtoon rendering, or painterly volume.',
    '',
    'EYES - HIGHEST PRIORITY:',
    'The eyes are the most important feature of the 1990s style.',
    'The final character eyes must follow Image B very closely in logic.',
    '',
    'The eyes must be:',
    '- larger than realistic manga eyes;',
    '- clearly 1990s manga / anime eyes;',
    '- more open and more readable than modern narrow realistic eyes;',
    '- highly expressive;',
    '- clean and iconic;',
    '- stylized, not realistic.',
    '',
    'Eye structure requirements:',
    '- large eye shape;',
    '- large iris;',
    '- large pupil or dark inner pupil area;',
    '- clearly visible bright highlight inside each eye;',
    '- the highlight must be readable and characteristic of 1990s anime/manga eyes;',
    '- the highlight should sit inside the iris / pupil area and must not disappear;',
    '- the iris may contain simple internal linework or subtle classic manga detail;',
    '- upper eyelids should be clean and defined;',
    '- lower eyelids should remain relatively simple;',
    '- lashes should be minimal or stylized, not realistic.',
    '',
    'The bright highlight rule is mandatory: each eye must contain at least one clear white highlight inside the iris / pupil area.',
    '',
    'The eyes must NOT be small, narrow realistic manga eyes, photographic, overly realistic in iris rendering, flat empty circles, dead black dots, modern glossy webtoon eyes, or hyper-rendered realistic human eyes.',
    '',
    'NOSE:',
    '- very small and simplified;',
    '- minimal linework;',
    '- tiny bridge indication only if needed;',
    '- small shadow or simple mark;',
    '- classic anime nose logic;',
    '- no heavy rendering.',
    '',
    'MOUTH:',
    '- small and simple;',
    '- clean thin linework;',
    '- minimal lip rendering;',
    '- simple expression shapes;',
    '- classic anime / manga mouth logic.',
    '',
    'HAIR:',
    '- preserve hairstyle identity from Image A;',
    '- convert it to 1990s manga / anime logic;',
    '- simplify into grouped locks;',
    '- keep the silhouette clean and readable;',
    '- use strong black-and-white shape logic;',
    '- if the character has black hair, keep it black with solid black masses, clean white highlights, and simple internal strand lines.',
    '',
    'Do not use hyper-detailed individual hair strands, modern glossy hair rendering, painterly texture, excessive texture noise, or realistic messy strand overload.',
    '',
    'BODY AND ANATOMY:',
    '- use classic manga / anime body proportions;',
    '- keep the apparent age and build;',
    '- make anatomy clean and readable;',
    '- avoid excessive realism;',
    '- avoid chibi proportions;',
    '- avoid hyper-muscular realism unless requested.',
    '',
    'CLOTHING:',
    '- preserve outfit identity if relevant;',
    '- redraw clothing in the 1990s manga / anime style;',
    '- use simple clothing folds;',
    '- use clean silhouettes;',
    '- use flat black / white / gray values;',
    '- use limited screentones only where necessary;',
    '- keep garment shapes readable.',
    '',
    'VERY IMPORTANT - CLOTHING VALUE LOCK:',
    'The clothes must use solid, unified color/value areas.',
    '',
    'Clothing must be rendered with:',
    '- plain flat blacks;',
    '- plain flat whites;',
    '- clean flat grays if needed;',
    '- smooth unified tones;',
    '- no noisy grain;',
    '- no dirty texture;',
    '- no rough fabric speckling;',
    '- no excessive screentone texture;',
    '- no random manga grain on clothing surfaces.',
    '',
    'If the outfit is dark, it should appear as clean solid black or clean dark gray masses.',
    'If the outfit has gray areas, they should be smooth and unified, not grainy.',
    'The clothing may have simple folds and contour lines, but fabric surfaces must remain clean and uniform.',
    '',
    'LINEART:',
    '- clean;',
    '- readable;',
    '- slightly old-school;',
    '- not sketchy;',
    '- not painterly;',
    '- not over-rendered;',
    '- clear contours;',
    '- simple internal detail;',
    '- controlled line weight;',
    '- strong black-and-white readability.',
    '',
    'SHADING AND VALUES:',
    '- black-and-white unless otherwise requested;',
    '- clean black fills;',
    '- white negative space;',
    '- simple gray areas;',
    '- light screentones if useful;',
    '- minimal hatching;',
    '- old-school manga value logic;',
    '- mostly clean and readable faces.',
    '',
    'Avoid deep realistic grayscale modeling, soft painterly gradients, photorealistic skin shading, muddy shadows, and excessive clothing grain.',
    '',
    '--------------------------------------------------',
    '6. CHARACTER CARD FORMAT',
    '--------------------------------------------------',
    '',
    'The final output must be a CHARACTER CARD / CHARACTER SHEET.',
    '',
    'If Image C is provided, follow its structure strictly.',
    '',
    'If no structure reference is provided, use the following default structure:',
    '- 3:2 format.',
    '- Clean white or very light neutral background.',
    '- Top row: three full-body views of the same character: front view, back view, side/profile view.',
    '- Bottom row: five bust or head-and-shoulders portraits of the same character: content / lightly pleased, very happy, neutral, angry, sad.',
    '',
    'The card must be clean, balanced, organized, easy to read, visually coherent, and consistent with the 1990s style shown in Image B.',
    '',
    '--------------------------------------------------',
    '7. CONSISTENCY RULES',
    '--------------------------------------------------',
    '',
    'All views and portraits must clearly depict the SAME character.',
    '',
    'This consistency is mandatory across face identity, hairstyle, age impression, body build, outfit, proportions, style rendering, and eye design.',
    '',
    'Front view must clearly show the full outfit from the front and preserve identity and silhouette.',
    'Back view must clearly show the hairstyle and outfit from the back and maintain the same body proportions.',
    'Side/profile view must clearly show the facial profile, hairstyle silhouette, and outfit profile construction.',
    'Expression portraits must remain fully recognizable as the same character. Only expression changes. Identity stays locked.',
    'The 1990s eye structure must remain consistent across expressions.',
    '',
    '--------------------------------------------------',
    '8. EXPRESSION RULES IN 1990s STYLE',
    '--------------------------------------------------',
    '',
    '- content / lightly pleased = soft small smile, relaxed large eyes;',
    '- very happy = open cheerful smile, large bright eyes, visible eye highlights;',
    '- neutral = calm, simple mouth, open readable gaze;',
    '- angry = tenser brows, sharper gaze, large eyes still preserved;',
    '- sad = softened large eyes, subdued mouth, slight emotional heaviness.',
    '',
    'Even when angry or sad, the eyes must remain large and classic 1990s in structure. Do not shrink the eyes into realistic narrow eyes.',
    '',
    '--------------------------------------------------',
    '9. STRUCTURE LOCK',
    '--------------------------------------------------',
    '',
    'If Image C is provided:',
    '- preserve its organizational logic;',
    '- preserve its top/bottom arrangement;',
    '- preserve its general composition system;',
    '- preserve its readability and card-like presentation.',
    '',
    'Do NOT copy the character shown in Image C. Only use Image C for structure and layout.',
    '',
    '--------------------------------------------------',
    '10. STYLE CONVERSION LOCK',
    '--------------------------------------------------',
    '',
    'This request requires STYLE CONVERSION.',
    '',
    'The final image must NOT look like:',
    '- the original source style from Image A placed onto a sheet;',
    '- the original art style with minor modifications;',
    '- a realistic version of the source character;',
    '- a modern current manga version of the source character.',
    '',
    'Instead, the final image must look like the same character identity from Image A, fully redesigned and redrawn in the target 1990s black-and-white manga / anime style shown in Image B.',
    '',
    'Mandatory rule: Preserve the identity. Replace the style.',
    'The original source style must disappear. The 1990s target style from Image B must dominate the entire final sheet.',
    '',
    '--------------------------------------------------',
    '11. USER NOTES AND EXTRA REFERENCES',
    '--------------------------------------------------',
    '',
    'User notes:',
    userNotes,
    '',
    'Extra references:',
    formatCharacterCardReferences(input.references),
    '',
    'Extra references may define outfit details, accessories, or visual notes only when their description says so.',
    'They must never override Image A identity, Image B target style, or Image C structure.',
    '',
    '--------------------------------------------------',
    '12. RESTRICTIONS',
    '--------------------------------------------------',
    '',
    'Do not:',
    '- preserve the original source style from Image A;',
    '- ignore the 1990s style reference Image B;',
    '- make the result photorealistic;',
    '- make the face semi-realistic;',
    '- make the eyes small;',
    '- make the eyes narrow and realistic;',
    '- remove the bright eye highlights;',
    '- make the nose realistic or large;',
    '- make the mouth realistic or over-rendered;',
    '- use painterly shading;',
    '- use modern glossy webtoon rendering;',
    '- generate different-looking versions of the character across the sheet;',
    '- change the outfit design between views;',
    '- over-render the clothes with noisy texture;',
    '- add decorative background elements;',
    '- add extra props unless requested;',
    '- add extra character views unless requested.',
    '',
    'Very important clothing restriction:',
    '- do not add grain or noisy texture to the clothing;',
    '- do not render the outfit with dirty screentone grain;',
    '- do not make the coat, jacket, pants, shirt, or sleeves look textured or speckled;',
    '- do not use rough fabric noise;',
    '- clothing values must remain solid, unified, and clean.',
    '',
    'Do not add text unless explicitly requested.',
    'By default: no title, no labels, no captions, no measurements, no annotations, no notes, no decorative typography.',
    '',
    '--------------------------------------------------',
    '13. FINAL MANDATORY INSTRUCTION',
    '--------------------------------------------------',
    '',
    'Generate a complete 3:2 black-and-white 1990s manga / anime character card of the same character shown in Image A.',
    '',
    'Use Image A only for identity.',
    'Use Image B as the mandatory 1990s style reference.',
    'Use Image C, if provided, only for card structure.',
    '',
    'Preserve from Image A:',
    '- the identity;',
    '- the face identity;',
    '- the hairstyle identity;',
    '- the character presence;',
    '- the outfit identity if relevant.',
    '',
    'Do NOT preserve the original rendering style of Image A.',
    '',
    'Fully convert the character into the 1990s style shown in Image B, with:',
    '- much larger classic manga / anime eyes;',
    '- large irises / pupils;',
    '- clear bright highlights inside the eyes;',
    '- very small simplified nose;',
    '- small simple mouth;',
    '- simplified flatter face construction;',
    '- classic grouped hair locks;',
    '- clean old-school black-and-white lineart;',
    '- simple monochrome shading;',
    '- clothing rendered with solid unified black / white / gray values;',
    '- no grain or noisy texture on the clothes;',
    '- clean flat outfit surfaces with only simple folds and controlled linework;',
    '- iconic 1990s manga / anime presentation.',
    '',
    'The final character card must show full-body front view, full-body back view, full-body side/profile view, and five expression portraits: content / lightly pleased, very happy, neutral, angry, sad.',
    '',
    'If Image C is provided, organize the card according to Image C. If Image C is not provided, use the default clean character-sheet structure.',
    '',
    'The final result must clearly read as: the same input character from Image A, fully redrawn in the 1990s manga / anime style of Image B, and presented as a clean professional character card.',
  ].join('\n');
}

function buildClassicCharacterCardPrompt(input) {
  const userNotes =
    input.prompt || 'No extra user instructions. Use Image A as the authoritative identity.';

  return [
    'CLASSIC MANGA CHARACTER CARD BACKEND PROMPT',
    'WITH MANDATORY STYLE IMAGE REFERENCE',
    '',
    'You are generating a CHARACTER CARD / CHARACTER SHEET of a provided character.',
    '',
    'The final result must be a full STYLE CONVERSION and CHARACTER SHEET generation.',
    '',
    'The backend receives:',
    '- Image A: a character identity reference image;',
    '- Image B: a mandatory classic manga style reference image;',
    '- Image C, if provided: a character-card structure reference image;',
    '- extra user instructions, if provided.',
    '',
    'The final output must convert the provided character into the classic manga style shown in Image B and described in this backend prompt.',
    '',
    '--------------------------------------------------',
    '1. IMAGE ROLES',
    '--------------------------------------------------',
    '',
    'Image A is the mandatory CHARACTER IDENTITY REFERENCE.',
    '',
    'It defines:',
    '- who the character is;',
    '- the face identity;',
    '- the hairstyle identity;',
    '- the eye shape identity before style conversion;',
    '- the hair color logic if visible or specified;',
    '- the outfit identity if relevant;',
    '- the silhouette and overall character presence;',
    '- the apparent age unless the user explicitly requests otherwise.',
    '',
    'Image B is the mandatory CLASSIC STYLE REFERENCE.',
    '',
    'It defines the target visual style that the final character card must follow.',
    '',
    'Image B controls:',
    '- the classic manga face design;',
    '- the classic eye design;',
    '- the eye rendering logic;',
    '- the eyelid structure;',
    '- the iris and pupil detail treatment;',
    '- the nose simplification;',
    '- the mouth simplification;',
    '- the black-and-white rendering language;',
    '- the lineart quality;',
    '- the simplified but refined shading logic;',
    '- the overall classic manga finish.',
    '',
    'Image C, if provided, is the CHARACTER CARD STRUCTURE REFERENCE.',
    '',
    'It defines:',
    '- how the final character card must be organized;',
    '- the layout logic;',
    '- the arrangement of the full-body views;',
    '- the arrangement of the expression portraits;',
    '- the spacing and overall presentation logic;',
    '- the visual organization of the card.',
    '',
    'Important:',
    'Image A defines WHO the character is.',
    'Image B defines HOW the final classic style must look.',
    'Image C defines HOW the character card must be organized.',
    'Do not confuse these roles.',
    '',
    '--------------------------------------------------',
    '2. CORE OBJECTIVE',
    '--------------------------------------------------',
    '',
    'Create a black-and-white classic manga character card of the character shown in Image A.',
    '',
    'The final result must:',
    '- preserve the identity of Image A;',
    '- remove the original source style of Image A;',
    '- fully convert the character into the classic manga target style shown in Image B;',
    '- follow the classic backend style rules described below;',
    '- present the character in a clean character card / character sheet format;',
    '- show the same character under multiple angles;',
    '- show the same character with multiple expressions;',
    '- maintain strict consistency across all views.',
    '',
    'This is NOT a request to preserve the original art style of Image A.',
    'This is a request to preserve the character identity from Image A and convert the rendering style into the classic manga style of Image B.',
    '',
    '--------------------------------------------------',
    '3. IDENTITY / STYLE SEPARATION RULE',
    '--------------------------------------------------',
    '',
    'When Image A is provided, separate IDENTITY from STYLE.',
    '',
    'Preserve from Image A:',
    '- face identity;',
    '- hairstyle identity;',
    '- hair color logic if relevant;',
    '- outfit identity if relevant;',
    '- silhouette;',
    '- age impression;',
    '- overall recognizable character presence.',
    '',
    'Do NOT preserve from Image A:',
    '- the original rendering style;',
    '- the original realism level;',
    '- the original eye rendering if it conflicts with the classic style;',
    '- the original shading style;',
    '- the original line style;',
    '- the original stylization level.',
    '',
    'Instead, fully redraw the same character in the classic style defined by Image B and this backend prompt.',
    '',
    'Image A defines WHO the character is.',
    'Image A does NOT define the final rendering style.',
    'Image B and this backend prompt define HOW the final image must look.',
    '',
    'The final result must clearly read as: the same character from Image A, but fully redrawn in the classic manga style shown in Image B.',
    '',
    '--------------------------------------------------',
    '4. CLASSIC STYLE REFERENCE LOCK',
    '--------------------------------------------------',
    '',
    'Image B is mandatory and must strongly influence the final visual result.',
    '',
    'Use Image B as the visual anchor for:',
    '- the face stylization;',
    '- the eye structure;',
    '- the detailed-but-clean iris rendering;',
    '- the refined upper eyelid design;',
    '- the subtle lower eyelid treatment;',
    '- the classic manga lineart;',
    '- the simplified facial planes;',
    '- the black-and-white value organization;',
    '- the refined but not overly realistic finish;',
    '- the overall classic manga appearance.',
    '',
    'Do not treat Image B as optional inspiration.',
    'The final image must look visually compatible with Image B.',
    'The backend prompt explains the style. Image B shows the style. Both must be followed together.',
    'If Image A has a conflicting source style, ignore the source style and prioritize Image B.',
    '',
    '--------------------------------------------------',
    '5. TARGET STYLE: CLASSIC MANGA',
    '--------------------------------------------------',
    '',
    'The target style is a clean, refined, classic manga style.',
    '',
    'It must NOT be photorealistic.',
    'It must NOT be painterly.',
    'It must NOT be a rough sketch style.',
    'It must NOT be a noisy modern webtoon rendering.',
    'It must NOT be a 1990s exaggerated eye style.',
    'It must NOT be hyper-realistic manga.',
    '',
    'The style must be:',
    '- clean;',
    '- elegant;',
    '- refined;',
    '- controlled;',
    '- black-and-white;',
    '- stylized;',
    '- readable;',
    '- expressive;',
    '- polished;',
    '- classically manga-like.',
    '',
    'It should feel like a refined monochrome manga portrait and character sheet with strong visual clarity.',
    '',
    'FACE CONSTRUCTION:',
    '- stylized and refined;',
    '- clean facial construction;',
    '- slightly simplified planes;',
    '- a smooth face surface;',
    '- elegant proportions;',
    '- relatively flat manga simplification;',
    '- controlled facial definition;',
    '- light structure rather than heavy realism.',
    '',
    'The face must NOT have heavy realistic cheekbone modeling, deep photographic facial depth, over-rendered lips, painterly skin rendering, realistic skin pores or texture, or modern glossy webtoon skin.',
    '',
    'EYES - HIGHEST PRIORITY:',
    'The eyes are the most important feature of this classic style.',
    'The final eye treatment must follow Image B very closely in logic.',
    '',
    'The eyes must be:',
    '- clearly manga eyes;',
    '- refined and carefully drawn;',
    '- moderately large, but not exaggerated;',
    '- more detailed than simple minimalist manga eyes;',
    '- not realistic human eyes;',
    '- not giant 1990s anime eyes;',
    '- elegant and expressive;',
    '- clean and iconic.',
    '',
    'Eye structure requirements:',
    '- a clear and well-shaped upper eyelid line;',
    '- a refined almond-like or softly rounded eye shape depending on the identity;',
    '- a visible iris with detailed internal structure;',
    '- a clearly readable dark pupil;',
    '- subtle but distinct internal iris detailing;',
    '- a small, controlled highlight or reflective bright area inside the eye;',
    '- fine lower eyelid indication, lighter and less dominant than the upper lid;',
    '- minimal but refined lash logic;',
    '- clean eye contours;',
    '- high readability.',
    '',
    'Correct eye rendering logic:',
    '- the upper eyelid is the strongest line;',
    '- the iris is clearly visible and carefully rendered;',
    '- the pupil must be clean and centered naturally;',
    '- the highlight must be visible but controlled;',
    '- the lower eyelid remains subtle;',
    '- the eye must feel classically manga, not realistic and not overly cartoonish.',
    '',
    'The eyes must NOT be flat empty circles, tiny realistic eyes, over-glossy webtoon eyes, 1990s oversized round anime eyes, dead simplified dots, hyper-realistic photographic eyes, or chaotic textured eyes.',
    '',
    'The eye feeling should be classic manga: refined, sharp but elegant, controlled, more detailed than a simple modern flat manga eye, expressive without exaggeration.',
    '',
    'Important: the eye area must be one of the main markers of the classic style. If the rest of the face is simple, the eyes must still carry refined line detail and clear visual presence.',
    '',
    'EYEBROWS:',
    '- clean;',
    '- relatively simple;',
    '- well-shaped;',
    '- expressive when needed;',
    '- readable without excessive hair-by-hair detail.',
    '',
    'NOSE:',
    '- small and simplified;',
    '- minimal linework;',
    '- a light bridge indication if needed;',
    '- a small shadow or concise line construction;',
    '- classic manga nose logic;',
    '- subtle and elegant.',
    '',
    'MOUTH:',
    '- small, clean, and restrained;',
    '- thin clean lines;',
    '- simplified lip logic;',
    '- subtle expression control;',
    '- elegant mouth shapes;',
    '- not heavily shaded, glossy, overly realistic, or thickly modeled.',
    '',
    'HAIR:',
    '- preserve hairstyle identity from Image A;',
    '- convert it into the classic manga logic of Image B;',
    '- cleanly organized readable strand groups;',
    '- more refined than very simple old-school anime hair;',
    '- less realistic than semi-realistic illustration hair;',
    '- controlled silhouette;',
    '- strong black-and-white readability.',
    '',
    'If the character has black hair:',
    '- keep the hair black;',
    '- use solid black masses;',
    '- use clean white highlights;',
    '- use internal strand separation where necessary;',
    '- keep the result elegant and readable.',
    '',
    'Do not use hyper-detailed chaotic strand overload, painterly hair texture, excessive realistic texture noise, or messy unresolved hair rendering.',
    '',
    'BODY AND ANATOMY:',
    '- use clean manga anatomy;',
    '- keep the apparent age and build;',
    '- maintain believable but stylized body proportions;',
    '- avoid excessive realism;',
    '- avoid fashion illustration distortion;',
    '- avoid chibi logic.',
    '',
    'CLOTHING:',
    '- preserve outfit identity if relevant;',
    '- redraw it in the classic manga style;',
    '- use simple and clean folds;',
    '- controlled garment construction;',
    '- readable silhouettes;',
    '- clear black / white / gray separation;',
    '- elegant clothing design logic;',
    '- limited and controlled detail.',
    '',
    'VERY IMPORTANT - CLOTHING VALUE LOCK:',
    'The clothes must use solid, unified color/value areas.',
    '',
    'Clothing must be rendered with:',
    '- plain flat blacks;',
    '- plain flat whites;',
    '- clean flat grays if needed;',
    '- smooth unified tones;',
    '- no noisy grain;',
    '- no dirty texture;',
    '- no rough fabric speckling;',
    '- no excessive screentone texture on the clothing;',
    '- no random manga grain on garment surfaces.',
    '',
    'If the outfit is dark, it should appear as clean solid black or clean dark gray masses.',
    'If the outfit has gray areas, they must remain smooth and unified, not grainy.',
    '',
    'The clothing may contain simple fold lines, seam indications, clean contour lines, and restrained internal line detail, but fabric surfaces must remain clean, uniform, visually stable, and free of grain and rough texture.',
    '',
    'LINEART:',
    '- clean;',
    '- controlled;',
    '- polished;',
    '- readable;',
    '- elegant;',
    '- clear contours;',
    '- refined facial lines;',
    '- controlled line weight;',
    '- clean internal details;',
    '- stable, deliberate line placement.',
    '',
    'Do not use rough sketchiness, chaotic scratch lines, painterly edges, or over-rendered crosshatching everywhere.',
    '',
    'SHADING AND VALUES:',
    '- black-and-white unless otherwise requested;',
    '- clean black fills;',
    '- white negative space;',
    '- simple gray areas when useful;',
    '- restrained screentone-like treatment only if necessary;',
    '- light, controlled value modeling;',
    '- minimal to moderate facial shading.',
    '',
    'Avoid photorealistic grayscale rendering, muddy tonal transitions, heavy painterly gradients, noisy grain on clothing, and dirty texture overload.',
    '',
    '--------------------------------------------------',
    '6. CHARACTER CARD FORMAT',
    '--------------------------------------------------',
    '',
    'The final output must be a CHARACTER CARD / CHARACTER SHEET.',
    '',
    'If Image C is provided, follow its structure strictly.',
    '',
    'If no structure reference is provided, use the following default structure:',
    '- 3:2 format.',
    '- Clean white or very light neutral background.',
    '- Top row: three full-body views of the same character: front view, back view, side/profile view.',
    '- Bottom row: five bust or head-and-shoulders portraits of the same character: content / lightly pleased, very happy, neutral, angry, sad.',
    '',
    'The card must be clean, balanced, organized, elegant, easy to read, visually coherent, and consistent with the classic style shown in Image B.',
    '',
    '--------------------------------------------------',
    '7. CONSISTENCY RULES',
    '--------------------------------------------------',
    '',
    'All views and portraits must clearly depict the SAME character.',
    '',
    'This consistency is mandatory across face identity, hairstyle, age impression, body build, outfit, proportions, eye design, and style rendering.',
    '',
    'Front view must clearly show the full outfit from the front and preserve identity and silhouette.',
    'Back view must clearly show the hairstyle and outfit from the back and maintain the same body proportions.',
    'Side/profile view must clearly show the facial profile, preserve hairstyle silhouette, and preserve outfit profile construction.',
    'Expression portraits must remain fully recognizable as the same character. Only expression changes. Identity stays locked. The eye structure must remain consistent across expressions.',
    '',
    '--------------------------------------------------',
    '8. EXPRESSION RULES',
    '--------------------------------------------------',
    '',
    'All expressions must remain in the classic manga style.',
    '',
    '- content / lightly pleased = subtle smile, softened gaze;',
    '- very happy = clear cheerful smile, bright open expression;',
    '- neutral = calm, direct, composed;',
    '- angry = sharper brows, firmer mouth, more intense gaze;',
    '- sad = softened gaze, lowered emotional energy, restrained mouth.',
    '',
    'Important:',
    'The eyes must remain refined and classically detailed in all expressions.',
    'Do not simplify them too much.',
    'Do not turn them into exaggerated cartoon eyes.',
    'Do not turn them into realistic photographic eyes.',
    '',
    '--------------------------------------------------',
    '9. STRUCTURE LOCK',
    '--------------------------------------------------',
    '',
    'If Image C is provided:',
    '- preserve its organizational logic;',
    '- preserve its top/bottom arrangement;',
    '- preserve its general composition system;',
    '- preserve its readability and character-card presentation logic.',
    '',
    'Do NOT copy the character shown in Image C. Only use Image C for structure and layout.',
    '',
    'If Image C is not provided, use the default 3:2 character-card structure.',
    '',
    '--------------------------------------------------',
    '10. STYLE CONVERSION LOCK',
    '--------------------------------------------------',
    '',
    'This request requires STYLE CONVERSION.',
    '',
    'The final image must NOT look like:',
    '- the original source style from Image A placed onto a sheet;',
    '- the source art style with minor modifications;',
    '- a realistic fashion illustration sheet;',
    '- a photorealistic portrait sheet;',
    '- a 1990s anime redesign;',
    '- a modern glossy webtoon card.',
    '',
    'Instead, the final image must look like the same character identity from Image A, fully redesigned and redrawn in the target classic black-and-white manga style shown in Image B.',
    '',
    'Mandatory rule: Preserve the identity. Replace the style.',
    'The original source style must disappear. The classic target style from Image B must dominate the entire final sheet.',
    '',
    '--------------------------------------------------',
    '11. USER NOTES AND EXTRA REFERENCES',
    '--------------------------------------------------',
    '',
    'User notes:',
    userNotes,
    '',
    'Extra references:',
    formatCharacterCardReferences(input.references),
    '',
    'Extra references may define outfit details, accessories, or visual notes only when their description says so.',
    'They must never override Image A identity, Image B target style, or Image C structure.',
    '',
    '--------------------------------------------------',
    '12. RESTRICTIONS',
    '--------------------------------------------------',
    '',
    'Do not:',
    '- preserve the original source style from Image A;',
    '- ignore the classic style reference Image B;',
    '- make the result photorealistic;',
    '- make the face overly realistic;',
    '- make the eyes overly simple;',
    '- make the eyes oversized in a 1990s anime way;',
    '- remove the refined iris detail;',
    '- remove the eye highlights completely;',
    '- make the nose realistic or large;',
    '- make the mouth heavily modeled;',
    '- use painterly shading;',
    '- use modern glossy webtoon rendering;',
    '- generate different-looking versions of the character across the sheet;',
    '- change the outfit design between views;',
    '- over-render the clothes with noisy texture;',
    '- add decorative background elements;',
    '- add extra props unless requested;',
    '- add extra character views unless requested.',
    '',
    'Very important clothing restriction:',
    '- do not add grain or noisy texture to the clothing;',
    '- do not render the outfit with dirty screentone grain;',
    '- do not make the coat, jacket, pants, shirt, sleeves, or other garments look textured or speckled;',
    '- do not use rough fabric noise;',
    '- clothing values must remain solid, unified, and clean.',
    '',
    'Do not add text unless explicitly requested.',
    'By default: no title, no labels, no captions, no measurements, no annotations, no notes, no decorative typography.',
    '',
    '--------------------------------------------------',
    '13. FINAL MANDATORY INSTRUCTION',
    '--------------------------------------------------',
    '',
    'Generate a complete 3:2 black-and-white classic manga character card of the same character shown in Image A.',
    '',
    'Use Image A only for identity.',
    'Use Image B as the mandatory classic style reference.',
    'Use Image C, if provided, only for character-card structure.',
    '',
    'Preserve from Image A:',
    '- the identity;',
    '- the face identity;',
    '- the hairstyle identity;',
    '- the character presence;',
    '- the outfit identity if relevant.',
    '',
    'Do NOT preserve the original rendering style of Image A.',
    '',
    'Fully convert the character into the classic style shown in Image B, with:',
    '- refined classic manga facial construction;',
    '- carefully drawn, moderately large manga eyes;',
    '- a strong upper eyelid line;',
    '- subtle lower eyelid logic;',
    '- clearly visible iris detail;',
    '- clean dark pupils;',
    '- small controlled highlights inside the eyes;',
    '- elegant eye rendering that is detailed but not realistic;',
    '- a small simplified nose;',
    '- a small restrained mouth;',
    '- clean grouped hair rendering;',
    '- polished black-and-white lineart;',
    '- controlled monochrome shading;',
    '- clothing rendered with solid unified black / white / gray values;',
    '- no grain or noisy texture on the clothes;',
    '- clean flat outfit surfaces with only simple folds and controlled linework;',
    '- a refined classic manga presentation.',
    '',
    'The final character card must show full-body front view, full-body back view, full-body side/profile view, and five expression portraits: content / lightly pleased, very happy, neutral, angry, sad.',
    '',
    'If Image C is provided, organize the card according to Image C. If Image C is not provided, use the default clean character-sheet structure.',
    '',
    'The final result must clearly read as: the same input character from Image A, fully redrawn in the classic manga style of Image B, and presented as a clean professional character card.',
  ].join('\n');
}

function buildCurrentCharacterCardPrompt(input) {
  const userNotes =
    input.prompt || 'No extra user instructions. Use Image A as the authoritative identity.';

  return [
    'CURRENT MANGA CHARACTER CARD BACKEND PROMPT',
    'WITH MANDATORY STYLE IMAGE REFERENCE',
    '',
    'You are generating a CHARACTER CARD / CHARACTER SHEET of a provided character.',
    '',
    'The final result must be a full STYLE CONVERSION and CHARACTER SHEET generation.',
    '',
    'The backend receives:',
    '- Image A: a character identity reference image;',
    '- Image B: a mandatory current / modern manga style reference image;',
    '- Image C, if provided: a character-card structure reference image;',
    '- extra user instructions, if provided.',
    '',
    'The final output must convert the provided character into the current modern manga style shown in Image B and described in this backend prompt.',
    '',
    '--------------------------------------------------',
    '1. IMAGE ROLES',
    '--------------------------------------------------',
    '',
    'Image A is the mandatory CHARACTER IDENTITY REFERENCE.',
    '',
    'It defines:',
    '- who the character is;',
    '- the face identity;',
    '- the hairstyle identity;',
    '- the eye shape identity before style conversion;',
    '- the hair color logic if visible or specified;',
    '- the outfit identity if relevant;',
    '- the silhouette and overall character presence;',
    '- the apparent age unless the user explicitly requests otherwise.',
    '',
    'Image B is the mandatory CURRENT MODERN MANGA STYLE REFERENCE.',
    '',
    'It defines the target visual style that the final character card must follow.',
    '',
    'Image B controls:',
    '- the current modern manga face design;',
    '- the clean and simplified facial construction;',
    '- the sharp but restrained eye design;',
    '- the controlled modern eye rendering;',
    '- the simplified nose;',
    '- the small restrained mouth;',
    '- the black-and-white / grayscale rendering language;',
    '- the clean digital manga lineart;',
    '- the smooth monochrome shading;',
    '- the simplified but polished hair treatment;',
    '- the overall current manga character-design feeling.',
    '',
    'Image C, if provided, is the CHARACTER CARD STRUCTURE REFERENCE.',
    '',
    'It defines:',
    '- how the final character card must be organized;',
    '- the layout logic;',
    '- the arrangement of the full-body views;',
    '- the arrangement of the expression portraits;',
    '- the spacing and overall presentation logic;',
    '- the visual organization of the card.',
    '',
    'Important:',
    'Image A defines WHO the character is.',
    'Image B defines HOW the final current manga style must look.',
    'Image C defines HOW the character card must be organized.',
    'Do not confuse these roles.',
    '',
    '--------------------------------------------------',
    '2. CORE OBJECTIVE',
    '--------------------------------------------------',
    '',
    'Create a black-and-white / grayscale current modern manga character card of the character shown in Image A.',
    '',
    'The final result must:',
    '- preserve the identity of Image A;',
    '- remove the original source style of Image A;',
    '- fully convert the character into the current modern manga target style shown in Image B;',
    '- follow the current manga backend style rules described below;',
    '- present the character in a clean character card / character sheet format;',
    '- show the same character under multiple angles;',
    '- show the same character with multiple expressions;',
    '- maintain strict consistency across all views.',
    '',
    'This is NOT a request to preserve the original art style of Image A.',
    'This is a request to preserve the character identity from Image A and convert the rendering style into the current modern manga style of Image B.',
    '',
    '--------------------------------------------------',
    '3. IDENTITY / STYLE SEPARATION RULE',
    '--------------------------------------------------',
    '',
    'When Image A is provided, separate IDENTITY from STYLE.',
    '',
    'Preserve from Image A:',
    '- face identity;',
    '- hairstyle identity;',
    '- hair color logic if relevant;',
    '- outfit identity if relevant;',
    '- silhouette;',
    '- age impression;',
    '- overall recognizable character presence.',
    '',
    'Do NOT preserve from Image A:',
    '- the original rendering style;',
    '- the original realism level;',
    '- the original eye rendering if it conflicts with the current manga style;',
    '- the original shading style;',
    '- the original line style;',
    '- the original stylization level.',
    '',
    'Instead, fully redraw the same character in the current modern manga style defined by Image B and this backend prompt.',
    '',
    'Image A defines WHO the character is.',
    'Image A does NOT define the final rendering style.',
    'Image B and this backend prompt define HOW the final image must look.',
    '',
    'The final result must clearly read as: the same character from Image A, but fully redrawn in the current modern manga style shown in Image B.',
    '',
    '--------------------------------------------------',
    '4. CURRENT STYLE REFERENCE LOCK',
    '--------------------------------------------------',
    '',
    'Image B is mandatory and must strongly influence the final visual result.',
    '',
    'Use Image B as the visual anchor for:',
    '- clean modern manga facial construction;',
    '- sharp but simplified eyes;',
    '- calm and restrained gaze;',
    '- smooth face planes;',
    '- small refined nose;',
    '- small neutral mouth;',
    '- clean monochrome / grayscale value organization;',
    '- polished modern manga lineart;',
    '- smooth hair masses with controlled highlights;',
    '- current character-design clarity.',
    '',
    'Do not treat Image B as optional inspiration.',
    'The final image must look visually compatible with Image B.',
    'The backend prompt explains the style. Image B shows the style. Both must be followed together.',
    'If Image A has a conflicting source style, ignore the source style and prioritize Image B.',
    '',
    '--------------------------------------------------',
    '5. TARGET STYLE: CURRENT MODERN MANGA',
    '--------------------------------------------------',
    '',
    'The target style is a clean, current modern manga style.',
    '',
    'It must NOT be photorealistic.',
    'It must NOT be painterly.',
    'It must NOT be rough sketch manga.',
    'It must NOT be 1990s anime style.',
    'It must NOT be heavily textured realistic manga.',
    '',
    'The style must be:',
    '- clean;',
    '- modern;',
    '- polished;',
    '- sharp;',
    '- controlled;',
    '- black-and-white or grayscale;',
    '- simplified but elegant;',
    '- emotionally restrained;',
    '- visually clear;',
    '- character-design focused.',
    '',
    'It should feel like a modern manga / digital manga character design: smooth, clean, refined, readable, stylish, and not over-rendered.',
    '',
    'FACE CONSTRUCTION:',
    '- clean, modern, and simplified;',
    '- smooth facial planes;',
    '- minimal facial texture;',
    '- clean jawline;',
    '- simple cheek structure;',
    '- refined but not realistic facial anatomy;',
    '- controlled face shape;',
    '- elegant modern manga proportions.',
    '',
    'The face must NOT have heavy realistic cheekbone modeling, deep photographic facial planes, overly detailed skin shading, strong realistic texture, rough crosshatching, painterly volume, or old-school 1990s softness.',
    '',
    'EYES - HIGHEST PRIORITY:',
    'The eyes are one of the key markers of the current modern manga style.',
    'The final eye treatment must follow Image B very closely in logic.',
    '',
    'The eyes must be:',
    '- clean and sharp;',
    '- moderately sized;',
    '- narrower than 1990s anime eyes;',
    '- more restrained than classic exaggerated manga eyes;',
    '- expressive but not overly dramatic;',
    '- modern and controlled;',
    '- clearly manga eyes, not realistic human eyes.',
    '',
    'Eye structure requirements:',
    '- sharp upper eyelid line;',
    '- clean, slightly narrowed eye shape;',
    '- controlled iris size;',
    '- readable dark pupil;',
    '- subtle internal iris detail;',
    '- minimal or small highlight if appropriate;',
    '- restrained lower eyelid line;',
    '- no excessive eyelashes;',
    '- no overly round old-school eye shape.',
    '',
    'Correct eye rendering logic:',
    '- the gaze is calm, direct, and slightly intense;',
    '- the upper eyelid carries the strongest expression;',
    '- the iris is visible but not huge;',
    '- the pupil is clean and dark;',
    '- the eye shape is streamlined and modern;',
    '- the expression is controlled rather than exaggerated.',
    '',
    'The eyes must NOT be giant 1990s anime eyes, round old-school eyes, highly realistic photographic eyes, hyper-detailed seinen eyes, glossy webtoon eyes, flat empty dots, overly cute, or moe-like.',
    '',
    'The eye feeling should be current manga: sharp, composed, restrained, stylish, clean, and emotionally controlled.',
    '',
    'Important: the eye area must remain simple enough to feel modern, but not empty. The eyes should carry the character presence through clean shape, gaze, and controlled contrast.',
    '',
    'EYEBROWS:',
    '- clean;',
    '- straight or slightly angled depending on expression;',
    '- simple and sharp;',
    '- clearly readable;',
    '- not overly textured;',
    '- supportive of the modern restrained expression.',
    '',
    'NOSE:',
    '- small, simple, and clean;',
    '- minimal linework;',
    '- a clean bridge indication if needed;',
    '- a small shadow or angular value shape;',
    '- modern manga nose logic;',
    '- understated and graphically clean.',
    '',
    'The nose must NOT be large, realistic, heavily shaded, anatomically complex, or old-school symbolic dot-only unless the face angle demands it.',
    '',
    'MOUTH:',
    '- small, restrained, and simple;',
    '- clean thin linework;',
    '- minimal lip detail;',
    '- subtle expression control;',
    '- modern manga mouth logic;',
    '- supportive of calm and controlled character presence.',
    '',
    'HAIR:',
    '- preserve the hairstyle identity from Image A;',
    '- convert it into the current modern manga logic of Image B;',
    '- black if the character has black hair;',
    '- cleanly grouped;',
    '- sharp in silhouette;',
    '- composed of readable locks;',
    '- sleek and polished;',
    '- not overly realistic;',
    '- not chaotic;',
    '- not heavily textured.',
    '',
    'If the character has black hair:',
    '- keep the hair black;',
    '- use solid black masses;',
    '- use clean white highlights;',
    '- use smooth grouped strands;',
    '- use controlled internal linework.',
    '',
    'Do not use excessive individual strand noise, old-school spiky clumps unless identity requires it, painterly hair texture, gritty hair grain, or hyper-realistic hair rendering.',
    '',
    'BODY AND ANATOMY:',
    '- use clean modern manga anatomy;',
    '- preserve the apparent age and build;',
    '- maintain believable but stylized body proportions;',
    '- keep the silhouette elegant and readable;',
    '- avoid excessive realism;',
    '- avoid chibi logic;',
    '- avoid stiff mannequin posture.',
    '',
    'CLOTHING:',
    '- preserve outfit identity if relevant;',
    '- redraw it in the current modern manga style;',
    '- clean silhouettes;',
    '- controlled fold lines;',
    '- sharp garment shapes;',
    '- clear black / white / gray separation;',
    '- modern clothing simplification;',
    '- readable design.',
    '',
    'VERY IMPORTANT - CLOTHING VALUE LOCK:',
    'The clothes must use solid, unified color/value areas.',
    '',
    'Clothing must be rendered with:',
    '- plain flat blacks;',
    '- plain flat whites;',
    '- clean flat grays if needed;',
    '- smooth unified tones;',
    '- no noisy grain;',
    '- no dirty texture;',
    '- no rough fabric speckling;',
    '- no excessive screentone texture on the clothing;',
    '- no random manga grain on garment surfaces.',
    '',
    'If the outfit is dark, it should appear as clean solid black or clean dark gray masses.',
    'If the outfit has gray areas, they must remain smooth and unified, not grainy.',
    '',
    'The clothing may contain simple fold lines, seam indications, clean contour lines, and controlled shadow shapes, but fabric surfaces must remain clean, uniform, visually stable, flat, polished, and free of grain and rough texture.',
    '',
    'LINEART:',
    '- clean;',
    '- crisp;',
    '- polished;',
    '- readable;',
    '- modern;',
    '- sharp contours;',
    '- minimal internal detail;',
    '- controlled line weight;',
    '- clean face and hair lines;',
    '- deliberate line placement.',
    '',
    'Do not use rough sketchiness, chaotic scratch lines, painterly edges, dense crosshatching everywhere, or dirty printed texture.',
    '',
    'SHADING AND VALUES:',
    '- black-and-white or grayscale unless otherwise requested;',
    '- clean black fills;',
    '- white negative space;',
    '- smooth gray areas;',
    '- controlled shadow shapes;',
    '- limited screentone only if necessary;',
    '- simple modern value hierarchy.',
    '',
    'Avoid muddy tonal transitions, gritty noise, photorealistic grayscale modeling, painterly gradients, dirty texture overload, and grain on clothing.',
    '',
    'The face should remain clean and smooth. The values should support form without becoming realistic illustration rendering.',
    '',
    '--------------------------------------------------',
    '6. CHARACTER CARD FORMAT',
    '--------------------------------------------------',
    '',
    'The final output must be a CHARACTER CARD / CHARACTER SHEET.',
    '',
    'If Image C is provided, follow its structure strictly.',
    '',
    'If no structure reference is provided, use the following default structure:',
    '- 3:2 format.',
    '- Clean white or very light neutral background.',
    '- Top row: three full-body views of the same character: front view, back view, side/profile view.',
    '- Bottom row: five bust or head-and-shoulders portraits of the same character: content / lightly pleased, very happy, neutral, angry, sad.',
    '',
    'The card must be clean, balanced, organized, minimal, easy to read, visually coherent, and consistent with the current modern manga style shown in Image B.',
    '',
    '--------------------------------------------------',
    '7. CONSISTENCY RULES',
    '--------------------------------------------------',
    '',
    'All views and portraits must clearly depict the SAME character.',
    '',
    'This consistency is mandatory across face identity, hairstyle, age impression, body build, outfit, proportions, eye design, and style rendering.',
    '',
    'Front view must clearly show the full outfit from the front and preserve identity and silhouette.',
    'Back view must clearly show the hairstyle and outfit from the back and maintain the same body proportions.',
    'Side/profile view must clearly show the facial profile, preserve hairstyle silhouette, and preserve outfit profile construction.',
    'Expression portraits must remain fully recognizable as the same character. Only expression changes. Identity stays locked. The eye structure must remain consistent across expressions.',
    '',
    '--------------------------------------------------',
    '8. EXPRESSION RULES',
    '--------------------------------------------------',
    '',
    'All expressions must remain in the current modern manga style.',
    '',
    '- content / lightly pleased = subtle controlled smile, calm eyes;',
    '- very happy = clear smile, brighter expression, still clean and modern;',
    '- neutral = calm, direct, composed;',
    '- angry = sharper brows, more intense gaze, firmer mouth;',
    '- sad = softened eyes, subdued mouth, restrained sadness.',
    '',
    'Important: the eyes must remain sharp and modern in all expressions. Do not enlarge them into a 1990s style. Do not turn them into realistic eyes. Do not overact the expressions unless explicitly requested.',
    '',
    '--------------------------------------------------',
    '9. STRUCTURE LOCK',
    '--------------------------------------------------',
    '',
    'If Image C is provided:',
    '- preserve its organizational logic;',
    '- preserve its top/bottom arrangement;',
    '- preserve its general composition system;',
    '- preserve its readability and character-card presentation logic.',
    '',
    'Do NOT copy the character shown in Image C. Only use Image C for structure and layout.',
    '',
    'If Image C is not provided, use the default 3:2 character-card structure.',
    '',
    '--------------------------------------------------',
    '10. STYLE CONVERSION LOCK',
    '--------------------------------------------------',
    '',
    'This request requires STYLE CONVERSION.',
    '',
    'The final image must NOT look like:',
    '- the original source style from Image A placed onto a sheet;',
    '- the source art style with minor modifications;',
    '- a realistic manga portrait sheet;',
    '- a 1990s anime redesign;',
    '- a classic manga card if the style becomes too detailed around the eyes;',
    '- a glossy webtoon character sheet.',
    '',
    'Instead, the final image must look like the same character identity from Image A, fully redesigned and redrawn in the target current modern manga style shown in Image B.',
    '',
    'Mandatory rule: Preserve the identity. Replace the style.',
    'The original source style must disappear. The current modern target style from Image B must dominate the entire final sheet.',
    '',
    '--------------------------------------------------',
    '11. USER NOTES AND EXTRA REFERENCES',
    '--------------------------------------------------',
    '',
    'User notes:',
    userNotes,
    '',
    'Extra references:',
    formatCharacterCardReferences(input.references),
    '',
    'Extra references may define outfit details, accessories, or visual notes only when their description says so.',
    'They must never override Image A identity, Image B target style, or Image C structure.',
    '',
    '--------------------------------------------------',
    '12. RESTRICTIONS',
    '--------------------------------------------------',
    '',
    'Do not:',
    '- preserve the original source style from Image A;',
    '- ignore the current style reference Image B;',
    '- make the result photorealistic;',
    '- make the face overly realistic;',
    '- make the eyes oversized in a 1990s anime way;',
    '- make the eyes too detailed in a realistic or classic ornate way;',
    '- make the nose large or realistic;',
    '- make the mouth heavily modeled;',
    '- use painterly shading;',
    '- use glossy webtoon coloring;',
    '- generate different-looking versions of the character across the sheet;',
    '- change the outfit design between views;',
    '- over-render the clothes with noisy texture;',
    '- add decorative background elements;',
    '- add extra props unless requested;',
    '- add extra character views unless requested.',
    '',
    'Very important clothing restriction:',
    '- do not add grain or noisy texture to the clothing;',
    '- do not render the outfit with dirty screentone grain;',
    '- do not make the coat, jacket, pants, shirt, sleeves, or other garments look textured or speckled;',
    '- do not use rough fabric noise;',
    '- clothing values must remain solid, unified, and clean.',
    '',
    'Do not add text unless explicitly requested.',
    'By default: no title, no labels, no captions, no measurements, no annotations, no notes, no decorative typography.',
    '',
    '--------------------------------------------------',
    '13. FINAL MANDATORY INSTRUCTION',
    '--------------------------------------------------',
    '',
    'Generate a complete 3:2 black-and-white / grayscale current modern manga character card of the same character shown in Image A.',
    '',
    'Use Image A only for identity.',
    'Use Image B as the mandatory current modern manga style reference.',
    'Use Image C, if provided, only for character-card structure.',
    '',
    'Preserve from Image A:',
    '- the identity;',
    '- the face identity;',
    '- the hairstyle identity;',
    '- the character presence;',
    '- the outfit identity if relevant.',
    '',
    'Do NOT preserve the original rendering style of Image A.',
    '',
    'Fully convert the character into the current modern manga style shown in Image B, with:',
    '- clean modern facial construction;',
    '- sharp restrained manga eyes;',
    '- controlled iris and pupil rendering;',
    '- calm modern gaze;',
    '- small simplified nose;',
    '- small restrained mouth;',
    '- clean grouped black hair;',
    '- polished black-and-white / grayscale lineart;',
    '- smooth controlled monochrome shading;',
    '- clothing rendered with solid unified black / white / gray values;',
    '- no grain or noisy texture on the clothes;',
    '- clean flat outfit surfaces with only simple folds and controlled linework;',
    '- a polished current manga presentation.',
    '',
    'The final character card must show full-body front view, full-body back view, full-body side/profile view, and five expression portraits: content / lightly pleased, very happy, neutral, angry, sad.',
    '',
    'If Image C is provided, organize the card according to Image C. If Image C is not provided, use the default clean character-sheet structure.',
    '',
    'The final result must clearly read as: the same input character from Image A, fully redrawn in the current modern manga style of Image B, and presented as a clean professional character card.',
  ].join('\n');
}

function buildGenericCharacterCardPrompt(input) {
  return [
    'Generate one 3:2 character card / character sheet from the provided character identity image.',
    '',
    'IMAGE ROLES:',
    '- Image A defines the character identity: face, hairstyle, eyes, outfit, silhouette, age impression, and overall presence.',
    '- Image B, if provided, defines the character-card structure and layout only.',
    '- Image C, if provided, defines the selected rendering style only.',
    '',
    `Selected style: ${input.styleName}${input.styleDescription ? ` - ${input.styleDescription}` : ''}.`,
    input.prompt ? `User notes: ${input.prompt}` : 'User notes: none.',
    '',
    'Preserve Image A identity while replacing the original source style with the selected target style.',
    'Show the same character in front, back, and side/profile full-body views.',
    'Show five head-and-shoulders portraits: content / lightly pleased, very happy, neutral, angry, sad.',
    'Use a clean white or very light background, no labels, no captions, no measurements, no decorative typography.',
    'Do not copy the character from Image B or Image C. They only define structure/style.',
    '',
    'Extra references:',
    formatCharacterCardReferences(input.references),
  ].join('\n');
}

function buildCharacterCardPrompt(input) {
  if (input.styleId.toLowerCase() === 'realistic') {
    return buildRealisticCharacterCardPrompt(input);
  }
  if (is1990sCharacterStyle(input)) {
    return build1990sCharacterCardPrompt(input);
  }
  if (isClassicCharacterStyle(input)) {
    return buildClassicCharacterCardPrompt(input);
  }
  if (isCurrentCharacterStyle(input)) {
    return buildCurrentCharacterCardPrompt(input);
  }
  return buildGenericCharacterCardPrompt(input);
}

function buildCharacterCardImageInputs(input) {
  const images = [];
  const addImage = (dataUrl, filename) => {
    if (!dataUrl) return;
    const image = dataUrlToImageBlob(dataUrl, filename);
    if (image) images.push(image);
  };

  addImage(input.identityImageDataUrl, 'image-a-character-identity');
  if (is1990sCharacterStyle(input)) {
    addImage(input.styleImageDataUrl, 'image-b-1990s-style-reference');
    addImage(input.structureImageDataUrl, 'image-c-card-structure');
  } else if (isClassicCharacterStyle(input)) {
    addImage(input.styleImageDataUrl, 'image-b-classic-style-reference');
    addImage(input.structureImageDataUrl, 'image-c-card-structure');
  } else if (isCurrentCharacterStyle(input)) {
    addImage(input.styleImageDataUrl, 'image-b-current-style-reference');
    addImage(input.structureImageDataUrl, 'image-c-card-structure');
  } else {
    addImage(input.structureImageDataUrl, 'image-b-card-structure');
    addImage(input.styleImageDataUrl, 'image-c-style-reference');
  }

  for (const reference of input.references) {
    addImage(reference.imageDataUrl, reference.id || reference.name || 'extra-reference');
  }

  return images;
}

function normalizeSketchFinalReferences(references) {
  if (!Array.isArray(references)) return [];
  return references
    .map((reference) => ({
      id: cleanText(reference?.id),
      name: cleanText(reference?.name, 'Element reference'),
      imageDataUrl: cleanImageDataUrl(reference?.imageDataUrl),
      description: cleanText(reference?.description || reference?.notes),
    }))
    .filter((reference) => reference.imageDataUrl);
}

function normalizeSketchFinalInput(body) {
  const requestedImageSize = normalizeMangaImageSize(
    body?.size || mangaImageSizeFromAspectRatio(body?.aspectRatio),
    imageSize,
  );

  return {
    prompt: cleanText(body?.prompt || body?.notes),
    sketchImageDataUrl: cleanImageDataUrl(
      body?.sketchImageDataUrl || body?.baseImageDataUrl || body?.imageDataUrl,
    ),
    styleImageDataUrl: cleanImageDataUrl(body?.styleImageDataUrl || body?.finishedStyleImageDataUrl),
    styleId: cleanText(body?.styleId, 'custom'),
    styleName: cleanText(body?.styleName, 'Finished style reference'),
    styleDescription: cleanText(body?.styleDescription),
    elementReferences: normalizeSketchFinalReferences(
      body?.elementReferences || body?.references || body?.referenceImages,
    ),
    size: requestedImageSize,
  };
}

function formatSketchFinalReferences(references) {
  if (!references.length) return '- none provided';
  return references
    .map((reference, index) => {
      const label = `Image ${String.fromCharCode(67 + index)}`;
      return [
        `- ${label}: ${reference.name}`,
        reference.description ? `  User role: ${reference.description}` : '',
        '  This reference defines the identity, design, material, outfit, face, prop, or environment detail of an element already present in Image A.',
        '  It must not change pose, framing, hand placement, camera angle, bubble placement, panel logic, or spatial relationships from Image A.',
      ]
        .filter(Boolean)
        .join('\n');
    })
    .join('\n');
}

function buildSketchFinalPrompt(input) {
  return [
    'SKETCH TO FINISHED IMAGE BACKEND PROMPT',
    'WITH MANDATORY STYLE REFERENCE',
    '',
    '1. IMAGE ROLES',
    '',
    'Image A is the sketch reference.',
    'It defines exactly:',
    '- composition;',
    '- framing;',
    '- camera angle;',
    '- pose;',
    '- expression;',
    '- hand placement;',
    '- body orientation;',
    '- speech bubble placement;',
    '- panel logic;',
    '- spatial relationships.',
    '',
    'Image B is the finished-style reference.',
    'It defines exactly:',
    '- final rendering style;',
    '- lineart;',
    '- face rendering;',
    '- eye rendering;',
    '- hair rendering;',
    '- shading;',
    '- texture level;',
    '- color/value logic;',
    '- polish level.',
    '',
    'Image C and following, if provided, are element / character identity references.',
    'They define:',
    '- face identity;',
    '- hairstyle identity;',
    '- outfit identity;',
    '- object identity;',
    '- background identity;',
    '- material, value, and design details;',
    '- character or element presence.',
    '',
    'Image A defines WHAT is drawn and WHERE everything is placed.',
    'Image B defines HOW the final image is rendered.',
    'Image C and following define WHO or WHAT specific sketched elements are, if provided.',
    '',
    'Do not confuse these roles.',
    '',
    '2. CORE RULE',
    '',
    'Image A controls WHAT is drawn and WHERE everything is placed.',
    'Image B controls HOW the final image is rendered.',
    'Image C and following control WHO/WHAT the matching sketched elements are, if provided.',
    '',
    'Do not let Image B change the composition.',
    'Do not let Image C or later references change the pose.',
    'Do not let any reference image invent a new scene.',
    '',
    '3. FINAL OBJECTIVE',
    '',
    'Create a polished finished version of Image A.',
    '',
    'The final image must:',
    '- preserve the sketch composition;',
    '- preserve the pose;',
    '- preserve the expression;',
    '- preserve the hand placement;',
    '- preserve the camera angle;',
    '- preserve the bubble placement if present;',
    '- preserve panel logic if present;',
    '- preserve all spatial relationships;',
    '- render everything in the finished style of Image B;',
    '- preserve the identity of matching elements from Image C and following if provided.',
    '',
    '4. STRICT SKETCH LOCK',
    '',
    'The sketch is the blueprint.',
    '',
    'Do not:',
    '- change the pose;',
    '- change the expression;',
    '- change the framing;',
    '- change the camera angle;',
    '- move the hands;',
    '- move the bubbles;',
    '- change panel logic;',
    '- add new characters;',
    '- remove important elements;',
    '- reinterpret the scene.',
    '',
    '5. STYLE REFERENCE LOCK',
    '',
    'Image B is mandatory.',
    `Selected style name: ${input.styleName}.`,
    input.styleDescription ? `Selected style description: ${input.styleDescription}.` : '',
    '',
    'The final image must visually match Image B in:',
    '- line quality;',
    '- finishing level;',
    '- eye style;',
    '- hair rendering;',
    '- shading logic;',
    '- black/white/gray or color treatment;',
    '- texture level;',
    '- overall visual finish.',
    '',
    'Do not use a generic style.',
    'Do not ignore Image B.',
    'Do not produce a result that looks unrelated to Image B.',
    '',
    '6. ELEMENT REFERENCE LOCK',
    '',
    'Use each element reference only for the element already present in the sketch.',
    'If a reference shows a character, preserve that character identity only where the sketch already contains that character.',
    'If a reference shows an object, outfit, background, or prop, preserve its design only where the sketch already contains the matching element.',
    'Never let an element reference replace Image A composition.',
    '',
    'Element references:',
    formatSketchFinalReferences(input.elementReferences),
    '',
    '7. ANATOMY CLEANUP RULE',
    '',
    'Correct rough anatomy only when necessary.',
    '',
    'Allowed:',
    '- clean proportions;',
    '- clarify fingers;',
    '- refine face;',
    '- clean hair;',
    '- finish clothes;',
    '- remove construction lines;',
    '- clarify perspective while keeping the same camera and layout.',
    '',
    'Forbidden:',
    '- changing the gesture;',
    '- moving hands;',
    '- changing the body direction;',
    '- changing the expression;',
    '- changing the scene.',
    '',
    input.prompt
      ? ['8. USER INSTRUCTIONS', '', input.prompt].join('\n')
      : '',
    '',
    '9. FINAL INSTRUCTION',
    '',
    'Generate the same scene as Image A, faithfully finished in the style of Image B, using Image C and following only for matching element identity if provided.',
    '',
    'The result must look like:',
    'the sketch from Image A was professionally completed using the visual style of Image B.',
  ]
    .filter(Boolean)
    .join('\n');
}

function buildSketchFinalImageInputs(input) {
  const images = [];
  const addImage = (dataUrl, filename) => {
    if (!dataUrl) return;
    const image = dataUrlToImageBlob(dataUrl, filename);
    if (image) images.push(image);
  };

  addImage(input.sketchImageDataUrl, 'image-a-sketch-reference');
  addImage(input.styleImageDataUrl, 'image-b-finished-style-reference');

  for (const [index, reference] of input.elementReferences.entries()) {
    const label = `image-${String.fromCharCode(99 + index)}-element-reference`;
    addImage(reference.imageDataUrl, reference.id || label);
  }

  return images;
}

app.get('/health', (_, res) => {
  res.json({ ok: true, service: 'ultimate-audio-recorder-backend' });
});

app.get('/api/manga/status', requireAuth, (_, res) => {
  res.json({
    ok: true,
    service: 'pulsenote-manga-backend',
    mangaForgeEnabled,
    imageModel,
    imageSize,
    supportedImageSizes: Array.from(supportedMangaImageSizes),
    imageQuality,
    imageFormat,
    creditCost: mangaPageCreditCost,
    referenceImagesEnabled: true,
    referenceImageAnalysisEnabled: imageAnalysisEnabled,
    referenceImageAnalysisModel: imageAnalysisModel,
    referenceImageAspectGuard: true,
    referenceCopyGuard: false,
    flatMangaStyleGuard: false,
    generationEndpoint: '/api/manga/generate-page',
    characterGenerationEndpoint: '/api/character/generate',
    sketchFinalGenerationEndpoint: '/api/sketch-final/generate',
    characterCardStyles: ['realistic', 'retro90', 'classic', 'current'],
    characterCardCreditCost,
    sketchFinalCreditCost,
  });
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

  try {
    const transcription = await openai.audio.transcriptions.create({
      file: fs.createReadStream(req.file.path),
      model: transcriptionModel,
      language: defaultLanguage,
      response_format: 'json',
    });

    res.json({
      text: transcription.text || '',
      model: transcriptionModel,
    });
  } catch (error) {
    console.error('Transcription failed:', error);
    res.status(500).json({
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
    res.status(500).json({
      error: 'Summary failed.',
      details: safeOpenAiError(error),
    });
  }
});

app.post('/api/sketch-final/generate', requireAuth, async (req, res) => {
  if (!mangaForgeEnabled) {
    return res.status(403).json({ error: 'Manga Forge generation is disabled.' });
  }

  const input = normalizeSketchFinalInput(req.body);

  if (!input.sketchImageDataUrl) {
    return res.status(400).json({
      error: 'Missing sketch image. Provide sketchImageDataUrl as Image A.',
    });
  }

  if (!input.styleImageDataUrl) {
    return res.status(400).json({
      error: 'Missing finished-style reference image. Provide styleImageDataUrl as Image B.',
    });
  }

  try {
    const imageInputs = buildSketchFinalImageInputs(input);
    if (imageInputs.length < 2) {
      return res.status(400).json({
        error: 'Sketch-to-final requires both Image A sketch and Image B style reference.',
      });
    }

    const finalPrompt = buildSketchFinalPrompt(input);
    const imageDataUrl = await requestMangaImageEdit(finalPrompt, imageInputs, input.size);

    res.json({
      imageDataUrl,
      imageUrl: imageDataUrl,
      finalPrompt,
      taskType: 'sketch_to_final',
      model: imageModel,
      size: input.size,
      quality: imageQuality,
      creditsUsed: sketchFinalCreditCost,
      createdAt: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Sketch-to-final generation failed:', error);
    res.status(500).json({
      error: 'Sketch-to-final generation failed.',
      details: safeOpenAiError(error),
    });
  }
});

app.post('/api/character/generate', requireAuth, async (req, res) => {
  if (!mangaForgeEnabled) {
    return res.status(403).json({ error: 'Manga Forge generation is disabled.' });
  }

  const input = normalizeCharacterCardInput(req.body);

  if (!input.identityImageDataUrl) {
    return res.status(400).json({
      error: 'Missing character identity image. Provide identityImageDataUrl as Image A.',
    });
  }

  if (is1990sCharacterStyle(input) && !input.styleImageDataUrl) {
    return res.status(400).json({
      error: 'Missing 1990s style reference image. Provide styleImageDataUrl as Image B.',
    });
  }

  if (isClassicCharacterStyle(input) && !input.styleImageDataUrl) {
    return res.status(400).json({
      error: 'Missing classic style reference image. Provide styleImageDataUrl as Image B.',
    });
  }

  if (isCurrentCharacterStyle(input) && !input.styleImageDataUrl) {
    return res.status(400).json({
      error: 'Missing current manga style reference image. Provide styleImageDataUrl as Image B.',
    });
  }

  try {
    const imageInputs = buildCharacterCardImageInputs(input);
    if (!imageInputs.length) {
      return res.status(400).json({ error: 'No valid character reference image was provided.' });
    }

    const finalPrompt = buildCharacterCardPrompt(input);
    const imageDataUrl = await requestMangaImageEdit(finalPrompt, imageInputs, input.size);

    res.json({
      imageDataUrl,
      imageUrl: imageDataUrl,
      finalPrompt,
      taskType: 'character_card_generation',
      model: imageModel,
      size: input.size,
      quality: imageQuality,
      creditsUsed: characterCardCreditCost,
      createdAt: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Character card generation failed:', error);
    res.status(500).json({
      error: 'Character card generation failed.',
      details: safeOpenAiError(error),
    });
  }
});

app.post('/api/manga/generate-page', requireAuth, async (req, res) => {
  if (!mangaForgeEnabled) {
    return res.status(403).json({ error: 'Manga Forge generation is disabled.' });
  }

  const operation = ['generate', 'edit', 'regenerate'].includes(req.body?.operation)
    ? req.body.operation
    : 'generate';
  const prompt = cleanText(req.body?.prompt);
  const editPrompt = cleanText(req.body?.editPrompt);
  const finalUserPrompt = operation === 'edit' ? editPrompt || prompt : prompt;
  const requestedImageSize = normalizeMangaImageSize(
    req.body?.size || mangaImageSizeFromAspectRatio(req.body?.aspectRatio),
    imageSize,
  );

  if (!finalUserPrompt) {
    return res.status(400).json({ error: 'Missing manga generation prompt.' });
  }

  const input = {
    operation,
    prompt: prompt || finalUserPrompt,
    editPrompt,
    editScope: cleanText(req.body?.editScope, 'single'),
    activePage: Number.isFinite(Number(req.body?.activePage))
      ? Number(req.body.activePage)
      : 1,
    pages: Array.isArray(req.body?.pages) ? req.body.pages : [1],
    panelCount: clampPanelCount(req.body?.panelCount),
    panelInstructions: Array.isArray(req.body?.panelInstructions)
      ? req.body.panelInstructions.map((line) => cleanText(line)).filter(Boolean)
      : [],
    selectedAssets: normalizeMangaAssets(req.body?.selectedAssets),
    characters: normalizeMangaCharacters(req.body?.characters),
    styleMode: ['auto', 'black-white', 'color'].includes(req.body?.styleMode)
      ? req.body.styleMode
      : 'auto',
    backgroundLevel: ['auto', 'empty', 'minimal', 'detailed'].includes(req.body?.backgroundLevel)
      ? req.body.backgroundLevel
      : 'auto',
    readingDirection: ['right-to-left', 'left-to-right'].includes(req.body?.readingDirection)
      ? req.body.readingDirection
      : 'right-to-left',
    aspectRatio: normalizeMangaAspectRatio(req.body?.aspectRatio, requestedImageSize),
    size: requestedImageSize,
    existingImageDataUrl: cleanText(req.body?.existingImageDataUrl),
  };

  try {
    const taskType = classifyMangaTask(input);
    const analyzedInput = await analyzeMangaReferenceImages(input, taskType);
    const { prompt: finalPrompt } = buildMangaImagePrompt(analyzedInput);
    const diagnostics = buildMangaDiagnostics(analyzedInput, taskType, finalPrompt);
    const imageDataUrl = await requestMangaImage(finalPrompt, analyzedInput, taskType);

    console.log(
      `[manga] prompt=${diagnostics.promptLength}c compacted=${diagnostics.promptCompacted} ` +
        `images=${diagnostics.imagesSentToOpenAI}/${diagnostics.maxImages} ` +
        `dropped=${diagnostics.droppedImageCount} ` +
        `perCharacter=${JSON.stringify(diagnostics.perCharacterImageCount)} ` +
        `missing=${JSON.stringify(diagnostics.charactersWithoutImage)}`,
    );

    res.json({
      imageDataUrl,
      imageUrl: imageDataUrl,
      finalPrompt,
      taskType,
      model: imageModel,
      size: requestedImageSize,
      quality: imageQuality,
      creditsUsed: mangaPageCreditCost,
      createdAt: new Date().toISOString(),
      diagnostics,
    });
  } catch (error) {
    console.error('Manga page generation failed:', error);
    res.status(500).json({
      error: 'Manga page generation failed.',
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
