import crypto from 'node:crypto';
import { mkdir, readFile, writeFile, rename, readdir, unlink } from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';

export const DEFAULT_CLAUDE_MODEL = 'claude-sonnet-5-5';

export function prepareClaudeBody(input, model = DEFAULT_CLAUDE_MODEL) {
  if (!/^claude-[\w.-]+$/.test(model)) throw Object.assign(new Error('Invalid CLAUDE_MODEL configuration.'), { status: 503 });
  const content = (Array.isArray(input?.content) ? input.content : []).flatMap((part) => {
    if (part?.type === 'text' && typeof part.text === 'string') return [{ type: 'text', text: part.text }];
    const url = part?.type === 'image_url' ? part.image_url?.url : null;
    if (!url) return [];
    const data = /^data:(image\/(?:png|jpeg|gif|webp));base64,([A-Za-z0-9+/=\r\n]+)$/.exec(url);
    if (data) return [{ type: 'image', source: { type: 'base64', media_type: data[1], data: data[2].replace(/\s/g, '') } }];
    if (/^https:\/\//.test(url)) return [{ type: 'image', source: { type: 'url', url } }];
    throw Object.assign(new Error('Unsupported Claude image reference.'), { status: 400 });
  });
  if (!content.length) throw Object.assign(new Error('Missing text content.'), { status: 400 });
  const effort = input?.reasoningEffort === 'xhigh' ? 'high' : input?.reasoningEffort;
  return {
    model,
    system: [typeof input?.system === 'string' ? input.system.trim() : '', input?.json ? 'Return only a valid JSON object, without markdown fences or commentary.' : ''].filter(Boolean).join('\n'),
    messages: [{ role: 'user', content }],
    max_tokens: Math.min(Math.max(Number(input?.maxOutputTokens) || 12000, 256), 128000),
    ...(['low', 'medium', 'high'].includes(effort) ? { output_config: { effort } } : {}),
    stream: true,
  };
}

/** Parse SSE incrementally; thinking deltas are never mistaken for the requested JSON. */
export async function readClaudeStream(response) {
  let buffer = '', text = '', model = '', stopReason = '', stopped = false;
  let usage = {};
  const decoder = new TextDecoder();
  const consume = (frame) => {
    const data = frame.split(/\r?\n/).filter((line) => line.startsWith('data:')).map((line) => line.slice(5).trim()).join('\n');
    if (!data) return;
    const event = JSON.parse(data);
    if (event.type === 'error') throw new Error('Claude interrupted the response; no automatic resubmission was made.');
    if (event.type === 'message_start') { model = event.message?.model || ''; usage = { ...event.message?.usage }; }
    if (event.type === 'content_block_start' && event.content_block?.type === 'text') text += event.content_block.text || '';
    if (event.type === 'content_block_delta' && event.delta?.type === 'text_delta') text += event.delta.text || '';
    if (event.type === 'message_delta') { stopReason = event.delta?.stop_reason || stopReason; usage = { ...usage, ...event.usage }; }
    if (event.type === 'message_stop') stopped = true;
  };
  if (!response.body) throw new Error('Claude returned no response stream.');
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
  if (!stopped) throw new Error('Claude stream interrupted before completion; no automatic resubmission was made.');
  const incomplete = stopReason === 'max_tokens';
  return {
    model, status: incomplete ? 'incomplete' : 'completed',
    output: [{ type: 'message', content: [{ type: 'output_text', text }] }],
    usage: { ...usage, input_tokens: (usage.input_tokens || 0) + (usage.cache_creation_input_tokens || 0) + (usage.cache_read_input_tokens || 0) },
    ...(incomplete ? { incomplete_details: { reason: 'max_output_tokens' } } : {}),
    ...(['refusal', 'tool_use'].includes(stopReason) ? { status: 'failed', error: { message: `Claude stopped with ${stopReason}.` } } : {}),
  };
}

/** Short polling survives browser disconnections. A provider POST is never repeated. */
export function createClaudeProvider({ apiKey, workspaceId, fetchImpl = fetch, directory = path.join(os.tmpdir(), 'pulsenote-claude-jobs') }) {
  const active = new Map();
  const valid = (id) => /^resp_claude_[a-f0-9-]{36}$/.test(id);
  const file = (id) => {
    if (!valid(id)) throw Object.assign(new Error('Invalid Claude job ID.'), { status: 400 });
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
    catch (error) { if (error.code !== 'ENOENT') throw error; throw Object.assign(new Error('Claude result no longer available. No new request was started.'), { status: 410 }); }
    if (payload.status === 'in_progress') {
      payload = { ...payload, status: 'failed', error: { message: 'Backend restarted during a Claude request. This request cannot be resumed at Anthropic; it was not resubmitted.' } };
      await save(payload);
    }
    return payload;
  };
  return {
    async create(body) {
      if (!apiKey) throw Object.assign(new Error('CLAUDE_API_KEY / ANTHROPIC_API_KEY is not configured.'), { status: 503 });
      const id = `resp_claude_${crypto.randomUUID()}`;
      const controller = new AbortController();
      const job = { controller, payload: { id, status: 'in_progress', model: body.model } };
      await save(job.payload);
      active.set(id, job);
      void (async () => {
        try {
          const { background, store, ...message } = body;
          const response = await fetchImpl('https://api.anthropic.com/v1/messages', {
            method: 'POST', headers: { 'x-api-key': apiKey, 'anthropic-version': '2023-06-01', 'Content-Type': 'application/json', ...(workspaceId ? { 'anthropic-workspace-id': workspaceId } : {}) },
            body: JSON.stringify(message), signal: controller.signal,
          });
          if (!response.ok) throw new Error(`Claude HTTP ${response.status}. Check model access, API credits and credentials in Render.`);
          job.payload = { id, ...await readClaudeStream(response) };
        } catch (error) {
          job.payload = { id, model: body.model, status: controller.signal.aborted ? 'cancelled' : 'failed', error: { message: controller.signal.aborted ? 'Claude request cancelled.' : error.message } };
        }
        try { await save(job.payload); }
        finally { active.delete(id); }
      })().catch(() => { active.delete(id); });
      // Bound retained result files without ever deleting an active operation.
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
