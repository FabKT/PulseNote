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
const imageGenerationTimeoutMs = Number(process.env.IMAGE_GENERATION_TIMEOUT_MS || 420000);
const imageEditTimeoutMs = Number(process.env.IMAGE_EDIT_TIMEOUT_MS || 540000);
const imageAnalysisEnabled = process.env.IMAGE_ANALYSIS_ENABLED !== 'false';
const imageAnalysisTimeoutMs = Number(process.env.IMAGE_ANALYSIS_TIMEOUT_MS || 120000);
const referenceAnalysisCacheLimit = Number(process.env.REFERENCE_ANALYSIS_CACHE_LIMIT || 160);
const imageRequestMaxAttempts = Math.max(
  1,
  Math.min(4, Number(process.env.IMAGE_REQUEST_MAX_ATTEMPTS || 2)),
);
const mangaPageCreditCost = Number(process.env.CREDIT_COST_MANGA_PAGE || 10);
const mangaForgeEnabled = process.env.MANGA_FORGE_ENABLED !== 'false';
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
app.use(express.json({ limit: '35mb' }));

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
    'defines character identity only: face, hair, outfit, silhouette, expression baseline, and distinctive traits',
  Background: 'defines decor, location, atmosphere, and allowed background complexity',
  Object: 'defines prop identity, shape, scale, and narrative ownership',
  Storyboard:
    'defines panel structure, framing, reading order, camera angles, character placement, and action order',
  Pose: 'defines body angle, gesture, limb placement, movement mechanics, and orientation only',
  Style:
    'defines rendering style, inking, screentone, hatching, contrast, color policy, and finish level',
  Inspiration:
    'influences only mood, energy, impact, motion feeling, or visual intensity; it must not override identity or structure',
  Target:
    'defines the existing image or page to preserve and modify directly',
  'Generated Page':
    'defines the current generated page structure and successful elements to preserve',
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

function truncateText(value, maxLength = 900) {
  const text = cleanText(value);
  if (text.length <= maxLength) return text;
  return `${text.slice(0, maxLength - 1).trim()}…`;
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
        '- Storyboard or Generated Page: extract panel layout, reading order, framing, gutters, composition, foreground/background placement, and action sequence.',
        '- Style: extract medium, linework, shading, screentone, contrast, color policy, rendering finish, and texture.',
        '- Background: extract location, decor, atmosphere, depth, perspective, foreground/background layers, and environmental constraints.',
        '- Object: extract prop shape, scale, material, position, ownership, and narrative function.',
        '- Target: extract what must be preserved and what can be changed.',
        '- Inspiration: extract mood, impact, energy, rhythm, and visual intensity only; do not copy identity or layout.',
        '',
        `Task type: ${mangaTaskLabel(taskType)}.`,
        `User prompt: ${truncateText(labelledInput.prompt, 1200) || '(empty)'}`,
        labelledInput.editPrompt
          ? `Edit prompt: ${truncateText(labelledInput.editPrompt, 900)}`
          : '',
        labelledInput.panelInstructions.length
          ? `Panel notes: ${truncateText(labelledInput.panelInstructions.join(' | '), 1400)}`
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

  let imageCount = labelledInput.targetImageLabel && labelledInput.existingImageDataUrl ? 1 : 0;
  for (const asset of labelledInput.selectedAssets) {
    if (!asset.imageDataUrl) continue;
    if (imageCount >= 8) break;
    imageCount += 1;
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
  let count = labelledInput.targetImageLabel && labelledInput.existingImageDataUrl ? 1 : 0;
  for (const asset of labelledInput.selectedAssets) {
    if (asset.imageDataUrl && count < 8) count += 1;
  }
  return count;
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
    const cleanAnalysis = truncateText(analysis, 9000);
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

function buildMangaImagePrompt(input) {
  const taskType = classifyMangaTask(input);
  const isModification = [
    'existing_image_modification',
    'strict_character_replacement',
    'targeted_correction',
  ].includes(taskType);
  const labelledInput = assignImageLabels(input, isModification);
  const inventory = inventoryMangaAssets(labelledInput);
  const characterNames = inventory.identityRefs.slice(0, 4);
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
        `- ${asset.imageLabel}: ${asset.name} / role=${asset.role}. ${
          asset.omitFromImageGeneration
            ? 'This reference is analysis-only for final generation; use the written visual facts and do not copy its canvas ratio, page silhouette, support, or margins.'
            : `This image ${imageRoleCopy[asset.role]}.`
        } ${
          asset.characterName ? `Assigned character profile: ${asset.characterName}.` : ''
        } ${asset.description ? `User notes: ${asset.description}.` : ''}`.trim(),
    );

  return {
    taskType,
    prompt: [
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
      'Character references define WHO the characters are: face, hair, outfit, silhouette, and distinctive traits.',
      'Storyboard or generated page references define HOW the page is organized: panel structure, framing, action order, and composition.',
      'Posture references define body angle, gesture, action mechanics, and orientation only.',
      'Inspiration references influence only energy, mood, motion, or visual impact. They must not override identity, structure, roles, or dialogue.',
      'Background and object references define decor and props only.',
      'Text instructions override ambiguous image interpretation. Never let inspiration override identity, panel function, role assignment, or dialogue.',
      '',
      'TASK TYPE LOCK:',
      mangaTaskLabel(taskType),
      '',
      'IDENTITY LOCK:',
      characterNames.length > 1
        ? `${characterNames.map((asset) => asset.characterName || asset.name).join(
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
      panelLines.join('\n'),
      '',
      'PANEL GEOMETRY LOCK:',
      panelGeometryLine,
      '',
      'POSE / ACTION LOCK:',
      'The requested pose, action mechanics, body angle, and gesture are not optional. Do not replace them with a generic pose.',
      inventory.postureRefs.length
        ? 'Pose references define action mechanics only. They do not define identity unless explicitly assigned as character references.'
        : '',
      '',
      'ORIENTATION / PERSPECTIVE LOCK:',
      'Preserve camera angle, foreshortening, scale, spatial direction, and stated orientation. Back view stays back view, profile stays profile, front view stays front view, and three-quarter view stays three-quarter view.',
      '',
      'ANATOMY / COMPLETENESS LOCK:',
      'Do not omit important limbs. Both arms and both legs must remain readable unless intentionally cropped. Do not lose the arm or leg that carries the action.',
      '',
      'EXPRESSION LOCK:',
      'If the prompt gives a specific expression, it overrides a default expression from a character reference for that panel only. Identity remains unchanged.',
      '',
      'DIALOGUE LOCK:',
      'If dialogue is requested, reproduce the exact text, keep the requested language, assign each line to the correct speaker, and place each bubble in the correct panel. Do not invent dialogue.',
      '',
      'STYLE LOCK:',
      labelledInput.styleMode === 'black-white'
        ? 'Use finished black-and-white manga artwork. Do not use color. Use clean ink, flat values, screentones, controlled hatching, manga linework, and readable silhouettes.'
        : labelledInput.styleMode === 'color'
          ? 'Use finished manga artwork in color while preserving clean ink, readable silhouettes, and controlled values.'
          : 'Use finished manga artwork. If black and white manga is requested, do not use color. Use clean ink, flat values, screentones, controlled hatching, manga linework, and readable silhouettes.',
      'Do not use photorealism, glossy rendering, painterly shading, or noisy texture unless explicitly requested.',
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
      'RESTRICTIONS:',
      isModification
        ? 'Do not alter what is already correct. Do not regenerate the page from scratch unless the user explicitly asks.'
        : 'No identity swapping. No character fusion. No unwanted color if black-and-white manga is implied. No missing limbs. No random extra characters. No text changes unless dialogue is explicitly requested.',
      '',
      'FINAL MANDATORY INSTRUCTION:',
      isModification
        ? `${canvasFormatLine} Modify only the requested parts while preserving the current manga page structure, successful elements, identity fidelity, pose readability, and exact style.`
        : `${canvasFormatLine} Generate the final manga artwork so the selected character identities, narrative roles, panel functions, pose mechanics, orientation, style, and background level all follow the prompt and locks above.`,
    ]
      .filter((line) => line !== '')
      .join('\n'),
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

  for (const asset of input.selectedAssets) {
    if (!asset.imageDataUrl) continue;
    if (asset.omitFromImageGeneration) continue;
    if (!shouldAttachMangaAssetImage(input, asset)) continue;
    const image = dataUrlToImageBlob(asset.imageDataUrl, asset.id || asset.name);
    if (image) images.push(image);
    if (images.length >= 8) break;
  }

  return images;
}

function shouldAttachMangaAssetImage(input, asset) {
  if (asset.omitFromImageGeneration) return false;
  if (!asset.imageWidth || !asset.imageHeight) return true;
  if (asset.role === 'Character') return true;

  const sourceRatio = asset.imageWidth / asset.imageHeight;
  const targetRatio = input.aspectRatio === '3:2' ? 3 / 2 : 2 / 3;
  const mismatch = Math.abs(sourceRatio - targetRatio) / targetRatio > 0.18;
  if (!mismatch) return true;

  const layoutDominantRoles = new Set([
    'Storyboard',
    'Generated Page',
    'Target',
    'Inspiration',
    'Style',
  ]);
  return !layoutDominantRoles.has(asset.role);
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
    maxReferenceImages: 8,
    generationEndpoint: '/api/manga/generate-page',
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
      ? req.body.panelInstructions.map((line) => cleanText(line)).filter(Boolean).slice(0, 12)
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
    const imageDataUrl = await requestMangaImage(finalPrompt, analyzedInput, taskType);

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
