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
const realtimeTranscriptionModel = [
  'whisper-1',
  'gpt-4o-transcribe',
  'gpt-4o-transcribe-latest',
  'gpt-4o-mini-transcribe',
].includes(requestedRealtimeTranscriptionModel)
  ? requestedRealtimeTranscriptionModel
  : transcriptionModel;
const summaryModel = process.env.SUMMARY_MODEL || 'gpt-4.1-mini';
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
app.use(express.json({ limit: '1mb' }));

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

app.get('/health', (_, res) => {
  res.json({ ok: true, service: 'ultimate-audio-recorder-backend' });
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

app.post('/realtime/transcription-session', requireAuth, async (_, res) => {
  try {
    const response = await fetch(
      'https://api.openai.com/v1/realtime/transcription_sessions',
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${openaiApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          input_audio_format: 'pcm16',
          input_audio_transcription: {
            model: realtimeTranscriptionModel,
            language: defaultLanguage,
          },
          input_audio_noise_reduction: {
            type: 'near_field',
          },
          turn_detection: null,
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
