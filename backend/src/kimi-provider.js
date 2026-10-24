import crypto from 'node:crypto';
import { mkdir, readFile, writeFile, rename, readdir, unlink } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';

/**
 * Kimi (Moonshot AI) : API compatible Chat Completions (https://api.moonshot.ai/v1).
 * Même contrat que les autres fournisseurs : réponse normalisée au format Responses (texte,
 * statut, usage avec la part servie par le cache), tâche suivie par identifiant.
 */
export const DEFAULT_KIMI_MODEL = 'kimi-k3.1-pro';
export const DEFAULT_KIMI_BASE_URL = 'https://api.moonshot.ai/v1';

/** Clé lue sous les noms usuels (le nom choisi sur Render n'importe pas). */
export function kimiApiKey(env = process.env) {
  return (env.KIMI_API_KEY || env.KIMI_AI || env.MOONSHOT_API_KEY || env.KIMI_KEY || env.MOONSHOT_KEY || '').trim();
}

// Niveaux de réflexion du site → Kimi K3 (low, high, max ; réflexion toujours active).
const EFFORTS = { minimal: 'low', low: 'low', medium: 'high', high: 'high', xhigh: 'max' };

export function prepareKimiBody(input, model = DEFAULT_KIMI_MODEL) {
  if (!/^kimi-[\w.-]+$/.test(model)) throw Object.assign(new Error('Invalid KIMI_MODEL configuration.'), { status: 503 });
  const content = (Array.isArray(input?.content) ? input.content : []).flatMap((part) => {
    if (part?.type === 'text' && typeof part.text === 'string' && part.text) return [{ type: 'text', text: part.text }];
    const url = part?.type === 'image_url' ? part.image_url?.url : null;
    return typeof url === 'string' && url ? [{ type: 'image_url', image_url: { url } }] : [];
  });
  if (!content.length) throw Object.assign(new Error('Missing text content.'), { status: 400 });
  const system = typeof input?.system === 'string' ? input.system.trim() : '';
  const effort = EFFORTS[input?.reasoningEffort];
  return {
    model,
    messages: [...(system ? [{ role: 'system', content: system }] : []), { role: 'user', content }],
    max_completion_tokens: Math.min(Math.max(Number(input?.maxOutputTokens) || 12000, 256), 128000),
    ...(effort ? { reasoning_effort: effort } : {}),
    // JSON : le format attendu est décrit dans les consignes (exigence de json_object).
    ...(input?.json ? { response_format: { type: 'json_object' } } : {}),
    // Cache automatique des débuts de requête identiques ; clé pour regrouper une conversation.
    ...(typeof input?.cacheKey === 'string' && /^[\w:.-]{1,64}$/.test(input.cacheKey) ? { prompt_cache_key: input.cacheKey } : {}),
    stream: true,
    stream_options: { include_usage: true },
  };
}

/** Flux SSE Chat Completions → réponse normalisée (le raisonnement n'est jamais pris pour le texte). */
export async function readKimiStream(response) {
  let buffer = '', text = '', model = '', finish = '', done = false;
  let usage = null;
  const decoder = new TextDecoder();
  const consume = (frame) => {
    const data = frame.split(/\r?\n/).filter((line) => line.startsWith('data:')).map((line) => line.slice(5).trim()).join('\n');
    if (!data) return;
    if (data === '[DONE]') { done = true; return; }
    const event = JSON.parse(data);
    if (event.error) throw new Error(`Kimi interrupted the response: ${event.error.message || 'error'}`);
    model = event.model || model;
    const choice = event.choices?.[0];
    if (choice?.delta?.content) text += choice.delta.content;
    if (choice?.finish_reason) finish = choice.finish_reason;
    if (event.usage) usage = event.usage;
  };
  if (!response.body) throw new Error('Kimi returned no response stream.');
  for await (const chunk of response.body) {
    buffer += decoder.decode(chunk, { stream: true });
    let match;
    while ((match = /\r?\n\r?\n/.exec(buffer))) {
      consume(buffer.slice(0, match.index));
      buffer = buffer.slice(match.index + match[0].length);
    }
  }
  buffer += decoder.decode();
  if (buffer.trim()) consume(buffer);
  if (!done && !finish) throw new Error('Kimi stream interrupted before completion; no automatic resubmission was made.');
  const incomplete = finish === 'length';
  const cached = usage?.prompt_tokens_details?.cached_tokens ?? usage?.cached_tokens ?? 0;
  return {
    model, status: incomplete ? 'incomplete' : 'completed',
    output: [{ type: 'message', content: [{ type: 'output_text', text }] }],
    // Écriture de cache Kimi : pas de supplément (prix d'entrée normal) → pas de cache_creation.
    usage: {
      input_tokens: usage?.prompt_tokens ?? 0,
      output_tokens: usage?.completion_tokens ?? 0,
      input_tokens_details: { cached_tokens: cached },
      output_tokens_details: { reasoning_tokens: usage?.completion_tokens_details?.reasoning_tokens ?? 0 },
    },
    ...(incomplete ? { incomplete_details: { reason: 'max_output_tokens' } } : {}),
    ...(finish === 'content_filter' ? { status: 'failed', error: { message: 'Kimi stopped with content_filter.' } } : {}),
  };
}

/** Tâches suivies par identifiant (relues sur disque) ; un envoi au fournisseur n'est jamais répété. */
export function createKimiProvider({ apiKey, baseUrl = DEFAULT_KIMI_BASE_URL, fetchImpl = fetch, directory = path.join(os.tmpdir(), 'pulsenote-kimi-jobs') }) {
  const active = new Map();
  const valid = (id) => /^resp_kimi_[a-f0-9-]{36}$/.test(id);
  const file = (id) => {
    if (!valid(id)) throw Object.assign(new Error('Invalid Kimi job ID.'), { status: 400 });
    return path.join(directory, `${id}.json`);
  };
  const save = async (payload) => {
    await mkdir(directory, { recursive: true });
    const target = file(payload.id), temporary = `${target}.${crypto.randomUUID()}.tmp`;
    await writeFile(temporary, JSON.stringify(payload), { mode: 0o600 });
    await rename(temporary, target);
  };
  const retrieve = async (id) => {
    const live = active.get(id);
    if (live) return live.payload;
    let payload;
    try { payload = JSON.parse(await readFile(file(id), 'utf8')); }
    catch (error) { if (error.code !== 'ENOENT') throw error; throw Object.assign(new Error('Kimi result no longer available. No new request was started.'), { status: 410 }); }
    if (payload.status === 'in_progress') {
      payload = { ...payload, status: 'failed', error: { message: 'Backend restarted during a Kimi request. It was not resubmitted.' } };
      await save(payload);
    }
    return payload;
  };
  return {
    async create(body) {
      if (!apiKey) throw Object.assign(new Error('KIMI_API_KEY / MOONSHOT_API_KEY is not configured.'), { status: 503 });
      const id = `resp_kimi_${crypto.randomUUID()}`;
      const controller = new AbortController();
      const job = { controller, payload: { id, status: 'in_progress', model: body.model } };
      await save(job.payload);
      active.set(id, job);
      void (async () => {
        try {
          const { background, store, ...request } = body;
          const response = await fetchImpl(`${baseUrl.replace(/\/+$/, '')}/chat/completions`, {
            method: 'POST',
            headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
            body: JSON.stringify(request),
            signal: controller.signal,
          });
          if (!response.ok) {
            // Message réel du fournisseur (sans la clé) : le diagnostic reste possible.
            const detail = await response.text().catch(() => '');
            throw new Error(`Kimi HTTP ${response.status}: ${detail.slice(0, 300)}`);
          }
          job.payload = { id, ...await readKimiStream(response) };
        } catch (error) {
          job.payload = { id, model: body.model, status: controller.signal.aborted ? 'cancelled' : 'failed', error: { message: controller.signal.aborted ? 'Kimi request cancelled.' : error.message } };
        }
        try { await save(job.payload); }
        finally { active.delete(id); }
      })().catch(() => { active.delete(id); });
      void readdir(directory, { withFileTypes: true }).then(async (entries) => {
        const cutoff = Date.now() - 86400000;
        const { stat } = await import('node:fs/promises');
        for (const entry of entries) {
          const jobId = entry.name.replace(/\.json$/, '');
          if (!valid(jobId) || active.has(jobId)) continue;
          const target = file(jobId);
          if ((await stat(target)).mtimeMs < cutoff) await unlink(target);
        }
      }).catch(() => {});
      return job.payload;
    },
    retrieve,
    async cancel(id) {
      const job = active.get(id);
      if (job?.payload.status === 'in_progress') { job.controller.abort(); job.payload = { ...job.payload, status: 'cancelled' }; await save(job.payload); }
      return retrieve(id);
    },
  };
}
