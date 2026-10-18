import crypto from 'node:crypto';
import { owner } from './text-job-routes.js';

const BASE = 'https://queue.fal.run';
const endpoints = { text: 'fal-ai/meshy/v6/text-to-3d', image: 'fal-ai/meshy/v6/image-to-3d' };
const uuid = /^[a-f\d]{8}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{4}-[a-f\d]{12}$/i;
const fail = (status, message) => { throw Object.assign(new Error(message), { status }); };

export function prepareFalMeshyInput(body) {
  const image = typeof body?.image === 'string' ? body.image : '';
  const prompt = typeof body?.prompt === 'string' ? body.prompt.trim() : '';
  if (!image && (!prompt || prompt.length > 600)) fail(400, 'A prompt of 1 to 600 characters is required.');
  if (image && (!/^(https:\/\/|data:image\/(?:png|jpeg|webp);base64,)/.test(image) || image.length > 20_000_000)) fail(400, 'Invalid Meshy reference image.');
  if (body?.character !== undefined && typeof body.character !== 'boolean') fail(400, 'Invalid character option.');
  const count = body?.polycount ?? 12000;
  if (!Number.isInteger(count) || count < 100 || count > 30000) fail(400, 'Meshy polygon budget must be between 100 and 30000.');
  const height = body?.height ?? 1.75;
  if (!Number.isFinite(height) || height < 0.2 || height > 5) fail(400, 'Invalid character height.');
  return {
    endpoint: image ? endpoints.image : endpoints.text,
    input: {
      ...(image ? { image_url: image, should_texture: true } : { prompt, mode: 'full' }),
      topology: 'triangle', target_polycount: count, should_remesh: true, enable_pbr: true,
      ...(body?.character ? { pose_mode: 'a-pose', enable_rigging: true, rigging_height_meters: height, enable_animation: true, animation_action_id: 0 } : {}),
    },
  };
}

export function createFalMeshy({ secret, apiKey, fetchImpl = fetch }) {
  const submissions = new Map();
  const sign = (claims) => {
    const encoded = Buffer.from(JSON.stringify(claims)).toString('base64url');
    return `${encoded}.${crypto.createHmac('sha256', secret).update(encoded).digest('base64url')}`;
  };
  const decode = (ticket, identity, requestId) => {
    if (typeof ticket !== 'string' || ticket.length > 6000) fail(403, 'Invalid 3D job ticket.');
    const [encoded, signature, extra] = ticket.split('.');
    const actual = Buffer.from(signature || '', 'base64url');
    const expected = crypto.createHmac('sha256', secret).update(encoded || '').digest();
    if (extra || actual.length !== expected.length || !crypto.timingSafeEqual(actual, expected)) fail(403, 'Invalid 3D job ticket.');
    let claims;
    try { claims = JSON.parse(Buffer.from(encoded, 'base64url').toString()); } catch { fail(403, 'Invalid 3D job ticket.'); }
    if (claims.owner !== identity || claims.requestId !== requestId) fail(403, '3D job ticket does not belong to this request.');
    return claims;
  };
  const safeQueueUrl = (url) => {
    const target = new URL(url);
    if (target.origin !== BASE || target.username || target.password || !/^\/fal-ai\/meshy\/requests\/[\w-]+(?:\/status|\/response|\/cancel)?$/.test(target.pathname)) fail(502, 'Invalid fal queue URL.');
    return target.href;
  };
  const call = async (url, body, method) => {
    if (!apiKey) fail(503, 'FAL_KEY / FALAI_API_KEY is not configured on Render.');
    const response = await fetchImpl(url, {
      method: method || (body ? 'POST' : 'GET'), headers: { Authorization: `Key ${apiKey}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(90000),
    });
    const json = await response.json();
    if (!response.ok) fail(response.status, `Meshy via fal.ai HTTP ${response.status}. No automatic submission retry was made.`);
    return json;
  };
  return {
    available: !!apiKey,
    async start(identity, body) {
      if (!uuid.test(body?.requestId || '')) fail(400, 'Invalid 3D request ID.');
      const { endpoint, input } = prepareFalMeshyInput(body);
      const key = `${identity}:${body.requestId}`;
      const digest = crypto.createHash('sha256').update(JSON.stringify({ endpoint, input })).digest('hex');
      const previous = submissions.get(key);
      if (previous) { if (previous.digest !== digest) fail(409, '3D request ID already used for different input.'); return previous.promise; }
      for (const [id, value] of submissions) if (Date.now() - value.at > 86400000) submissions.delete(id);
      if (submissions.size >= 1000) fail(429, '3D submission capacity reached.');
      const promise = (async () => {
        const result = await call(`${BASE}/${endpoint}`, input);
        if (!/^[\w-]{1,160}$/.test(result.request_id || '')) fail(502, 'fal returned no recoverable job ID.');
        const claims = { owner: identity, requestId: result.request_id, statusUrl: safeQueueUrl(result.status_url), responseUrl: safeQueueUrl(result.response_url) };
        return { requestId: result.request_id, ticket: sign(claims), provider: 'fal', referenceCount: body.image ? 1 : 0 };
      })();
      // Keep rejected submissions too: a lost acknowledgement is not permission to charge again.
      submissions.set(key, { digest, promise, at: Date.now() });
      return promise;
    },
    async read(identity, requestId, ticket) {
      const claims = decode(ticket, identity, requestId);
      const status = await call(safeQueueUrl(claims.statusUrl));
      if (status.status !== 'COMPLETED') return { status: status.status, requestId };
      if (status.error) return { status: 'FAILED', requestId, error: 'Meshy generation failed at fal.ai.' };
      const result = await call(safeQueueUrl(claims.responseUrl));
      return { status: 'COMPLETED', requestId, result };
    },
    async cancel(identity, requestId, ticket) {
      const claims = decode(ticket, identity, requestId);
      const statusUrl = new URL(safeQueueUrl(claims.statusUrl));
      statusUrl.pathname = statusUrl.pathname.replace(/\/status$/, '/cancel');
      return call(safeQueueUrl(statusUrl.href), undefined, 'PUT');
    },
  };
}

export function registerFalMeshyRoutes(app, { requireAuth, ...options }) {
  const jobs = createFalMeshy(options);
  app.use('/api/3d', (_, res, next) => { res.set('Cache-Control', 'no-store'); next(); });
  app.get('/api/3d/capabilities', requireAuth, (_, res) => res.json({ provider: 'fal', available: jobs.available, textTo3d: true, imageTo3d: true, rigging: true, referenceImages: 1 }));
  app.post('/api/3d/jobs', requireAuth, async (req, res) => {
    try { res.status(202).json(await jobs.start(owner(req), req.body)); }
    catch (error) { res.status(Number(error.status) || 502).json({ error: error.status ? error.message : '3D submission connection interrupted. Do not submit again until its status has been checked.' }); }
  });
  app.get('/api/3d/jobs/:requestId', requireAuth, async (req, res) => {
    try { res.json(await jobs.read(owner(req), req.params.requestId, req.header('x-3d-job-ticket'))); }
    catch (error) { res.status(Number(error.status) || 502).json({ error: error.status ? error.message : '3D status temporarily unavailable.' }); }
  });
  app.post('/api/3d/jobs/:requestId/cancel', requireAuth, async (req, res) => {
    try { res.json(await jobs.cancel(owner(req), req.params.requestId, req.header('x-3d-job-ticket'))); }
    catch (error) { res.status(Number(error.status) || 502).json({ error: '3D cancellation could not be confirmed. Accepted work may still be charged.' }); }
  });
}
