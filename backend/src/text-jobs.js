import crypto from 'node:crypto';
import { prepareClaudeBody, DEFAULT_CLAUDE_MODEL } from './claude-provider.js';

export function prepareTextBody(input, defaultModel, claudeModel = DEFAULT_CLAUDE_MODEL) {
  if (input?.provider && !['gpt', 'claude'].includes(input.provider)) throw Object.assign(new Error('Unsupported text provider.'), { status: 400 });
  if (input?.provider === 'claude') return prepareClaudeBody(input, claudeModel);
  const clean = (value) => typeof value === 'string' ? value.trim() : '';
  const requested = clean(input?.model);
  const model = /^(gpt|o\d|chatgpt)[\w.-]*$/i.test(requested) ? requested : defaultModel;
  const system = clean(input?.system);
  const content = (Array.isArray(input?.content) ? input.content : []).flatMap((part) => {
    if (part?.type === 'text' && typeof part.text === 'string') return [{ type: 'input_text', text: part.text }];
    const url = part?.type === 'image_url' ? part.image_url?.url : null;
    return typeof url === 'string' && url ? [{ type: 'input_image', image_url: url }] : [];
  });
  if (!content.length) throw Object.assign(new Error('Missing text content.'), { status: 400 });
  const effort = clean(input?.reasoningEffort);
  return {
    model,
    input: [...(system ? [{ role: 'system', content: system }] : []), { role: 'user', content }],
    max_output_tokens: Math.min(Math.max(Number(input?.maxOutputTokens) || 12000, 256), 128000),
    ...(['minimal', 'low', 'medium', 'high', 'xhigh'].includes(effort) ? { reasoning: { effort } } : {}),
    ...(input?.json ? { text: { format: { type: 'json_object' } } } : {}),
  };
}

const requestPattern = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const pending = new Set(['queued', 'in_progress']);
const fail = (status, message) => { throw Object.assign(new Error(message), { status }); };

/** Creation is never retried. Signed response tickets survive a backend restart. */
export function createTextJobs({ secret, create, retrieve, cancel, extractText, now = Date.now }) {
  const jobs = new Map();
  const sign = (value) => {
    const encoded = Buffer.from(JSON.stringify(value)).toString('base64url');
    return `${encoded}.${crypto.createHmac('sha256', secret).update(encoded).digest('base64url')}`;
  };
  const decode = (ticket, owner, requestId) => {
    if (typeof ticket !== 'string' || ticket.length > 2000) fail(403, 'Invalid text job ticket.');
    const [encoded, signature, extra] = ticket.split('.');
    const expected = crypto.createHmac('sha256', secret).update(encoded || '').digest();
    const supplied = Buffer.from(signature || '', 'base64url');
    if (extra || supplied.length !== expected.length || !crypto.timingSafeEqual(supplied, expected)) fail(403, 'Invalid text job ticket.');
    let claims;
    try { claims = JSON.parse(Buffer.from(encoded, 'base64url').toString()); } catch { fail(403, 'Invalid text job ticket.'); }
    if (claims.v !== 1 || claims.owner !== owner || claims.requestId !== requestId || !/^resp_[\w-]{1,160}$/.test(claims.responseId || '')) fail(403, 'Invalid text job ticket.');
    return claims;
  };
  const snapshot = (job) => ({
    requestId: job.requestId,
    state: job.state,
    ...(job.responseId ? { ticket: sign({ v: 1, owner: job.owner, requestId: job.requestId, responseId: job.responseId, digest: job.digest }) } : {}),
    ...(job.error ? { error: job.error } : {}),
  });
  const locate = (owner, requestId, ticket) => {
    if (!requestPattern.test(requestId)) fail(400, 'Invalid request ID.');
    const key = `${owner}:${requestId}`;
    let job = jobs.get(key);
    if (ticket) {
      const claims = decode(ticket, owner, requestId);
      if (!job) {
        job = { ...claims, state: 'in_progress', at: now() };
        jobs.set(key, job);
      } else if (claims.responseId !== job.responseId) fail(409, 'Text job ticket conflicts with the existing job.');
    }
    if (!job) fail(404, 'Text job not found. Do not create another generation automatically.');
    return job;
  };
  const applyPayload = (job, payload) => {
    job.state = payload.status;
    job.at = now();
    if (!pending.has(job.state)) {
      return {
        ...snapshot(job),
        result: {
          text: extractText(payload), model: payload.model,
          usage: payload.usage || null, status: payload.status,
          incompleteReason: payload.incomplete_details?.reason || null,
          ...(payload.error ? { error: payload.error.message || 'Text provider failed.' } : {}),
        },
      };
    }
    return snapshot(job);
  };
  return {
    start(owner, requestId, body) {
      if (!requestPattern.test(requestId)) fail(400, 'Invalid request ID.');
      const key = `${owner}:${requestId}`;
      const digest = crypto.createHash('sha256').update(JSON.stringify(body)).digest('hex');
      const existing = jobs.get(key);
      if (existing) {
        if (existing.digest !== digest) fail(409, 'Request ID already belongs to a different input.');
        return snapshot(existing);
      }
      for (const [id, job] of jobs) if (!['submitting', 'queued', 'in_progress'].includes(job.state) && now() - job.at > 86_400_000) jobs.delete(id);
      if (jobs.size >= 1000) fail(429, 'Text job capacity reached; no provider request was started.');
      const job = { owner, requestId, digest, state: 'submitting', at: now(), cancelRequested: false };
      jobs.set(key, job);
      // Persist the operation identity before making exactly one billable submission.
      Promise.resolve().then(async () => {
        if (job.cancelRequested) { job.state = 'cancelled'; return; }
        const payload = await create({ ...body, background: true, store: true });
        if (!/^resp_[\w-]{1,160}$/.test(payload?.id || '')) fail(502, 'Provider returned no recoverable response ID.');
        job.responseId = payload.id;
        applyPayload(job, payload);
        if (job.cancelRequested && pending.has(job.state)) applyPayload(job, await cancel(job.responseId));
      }).catch((error) => {
        job.state = job.responseId ? 'in_progress' : (error.status ? 'failed' : 'submission_unknown');
        job.error = error.status ? error.message : 'Provider connection interrupted. Submission was not repeated.';
      });
      return snapshot(job);
    },
    async read(owner, requestId, ticket) {
      const job = locate(owner, requestId, ticket);
      if (!job.responseId) return snapshot(job);
      if (job.reading) return job.reading;
      // A failed GET leaves the response ID intact for the next read.
      const reading = (async () => {
        const payload = await retrieve(job.responseId);
        if (job.cancelRequested && pending.has(payload.status)) return applyPayload(job, await cancel(job.responseId));
        delete job.error;
        return applyPayload(job, payload);
      })();
      job.reading = reading;
      try { return await reading; }
      finally { if (job.reading === reading) delete job.reading; }
    },
    async cancel(owner, requestId, ticket) {
      const job = locate(owner, requestId, ticket);
      job.cancelRequested = true;
      if (job.responseId) return applyPayload(job, await cancel(job.responseId));
      return snapshot(job);
    },
  };
}
