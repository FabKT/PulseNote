import test from 'node:test';
import assert from 'node:assert/strict';
import { createFalMeshy, prepareFalMeshyInput } from './fal-meshy.js';

const requestId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const json = (body, status = 200) => new Response(JSON.stringify(body), { status });
const queue = { request_id: requestId, status_url: `https://queue.fal.run/fal-ai/meshy/requests/${requestId}/status`, response_url: `https://queue.fal.run/fal-ai/meshy/requests/${requestId}` };

test('fal Meshy submits one textured model with bounded geometry and optional rigging', () => {
  const text = prepareFalMeshyInput({ prompt: 'a tree', polycount: 4000 });
  assert.equal(text.endpoint, 'fal-ai/meshy/v6/text-to-3d');
  assert.equal(text.input.mode, 'full');
  assert.equal(text.input.target_polycount, 4000);
  const character = prepareFalMeshyInput({ image: 'data:image/png;base64,YQ==', character: true });
  assert.equal(character.endpoint, 'fal-ai/meshy/v6/image-to-3d');
  assert.equal(character.input.enable_rigging, true);
  assert.equal(character.input.animation_action_id, 0);
  assert.throws(() => prepareFalMeshyInput({ prompt: 'x', polycount: 999999 }), /polygon/);
  assert.throws(() => prepareFalMeshyInput({ image: 'file:///private' }), /Invalid/);
});

test('fal jobs are idempotent and signed tickets recover status after restart', async () => {
  let submissions = 0;
  const fetchImpl = async (url, options) => {
    assert.equal(options.headers.Authorization, 'Key test-key');
    if (options.method === 'POST') { submissions++; return json(queue); }
    if (url.endsWith('/status')) return json({ status: 'COMPLETED' });
    return json({ model_glb: { url: 'https://v3.fal.media/model.glb' } });
  };
  const jobs = createFalMeshy({ secret: 'test-secret', apiKey: 'test-key', fetchImpl, billingDelayMs: 0 });
  const body = { requestId, prompt: 'a tree' };
  const job = await jobs.start('owner', body);
  assert.deepEqual(await jobs.start('owner', body), job);
  assert.equal(submissions, 1);
  await assert.rejects(jobs.start('owner', { ...body, prompt: 'a car' }), /different input/);
  const restarted = createFalMeshy({ secret: 'test-secret', apiKey: 'test-key', fetchImpl, billingDelayMs: 0 });
  assert.equal((await restarted.read('owner', requestId, job.ticket)).status, 'COMPLETED');
  await assert.rejects(restarted.read('attacker', requestId, job.ticket), /belong/);
  await assert.rejects(restarted.read('owner', requestId, `${job.ticket}x`), /Invalid/);
  assert.equal(submissions, 1);
});

test('ambiguous fal submission never retries or switches to direct Meshy', async () => {
  let calls = 0;
  const jobs = createFalMeshy({ secret: 'test', apiKey: 'test', fetchImpl: () => { calls++; throw new Error('lost acknowledgement'); } });
  const body = { requestId, prompt: 'a tree' };
  await assert.rejects(jobs.start('owner', body), /lost acknowledgement/);
  await assert.rejects(jobs.start('owner', body), /lost acknowledgement/);
  assert.equal(calls, 1);
});

test('fal credentials are never sent to a foreign status host', async () => {
  const jobs = createFalMeshy({ secret: 'test', apiKey: 'test', fetchImpl: async () => json({ ...queue, status_url: 'https://attacker.example/private' }) });
  await assert.rejects(jobs.start('owner', { requestId, prompt: 'a tree' }), /Invalid fal queue URL/);
});

test('fal cancellation targets the signed original job only', async () => {
  let cancelled;
  const jobs = createFalMeshy({ secret: 'test', apiKey: 'test', fetchImpl: async (url, options) => {
    if (options.method === 'POST') return json(queue);
    cancelled = { url, method: options.method };
    return json({ status: 'CANCELLATION_REQUESTED' });
  } });
  const job = await jobs.start('owner', { requestId, prompt: 'a tree' });
  await jobs.cancel('owner', requestId, job.ticket);
  assert.equal(cancelled.method, 'PUT');
  assert.equal(cancelled.url, `https://queue.fal.run/fal-ai/meshy/requests/${requestId}/cancel`);
  await assert.rejects(jobs.cancel('other-owner', requestId, job.ticket), /belong/);
});

test('fal estimate uses the current per-call price and is cached per endpoint', async () => {
  let calls = 0;
  const jobs = createFalMeshy({ secret: 'test', apiKey: 'test', fetchImpl: async (url, options) => {
    calls++;
    assert.equal(url, 'https://api.fal.ai/v1/models/pricing/estimate');
    const body = JSON.parse(options.body);
    assert.equal(body.estimate_type, 'historical_api_price');
    assert.deepEqual(Object.keys(body.endpoints), ['fal-ai/meshy/v6/text-to-3d']);
    return json({ estimate_type: 'historical_api_price', total_cost: 0.8, currency: 'USD' });
  } });
  assert.deepEqual(await jobs.estimate({ prompt: 'a tree' }), { endpoint: 'fal-ai/meshy/v6/text-to-3d', costUsd: 0.8, currency: 'USD' });
  await jobs.estimate({ prompt: 'a car' });
  assert.equal(calls, 1);
  const broken = createFalMeshy({ secret: 'test', apiKey: 'test', fetchImpl: async () => json({ total_cost: 0 }) });
  await assert.rejects(broken.estimate({ prompt: 'a tree' }), /estimate unavailable/);
});

test('completed fal job reports the billed cost, or null without blocking', async () => {
  const billed = (events) => async (url, options) => {
    if (options.method === 'POST') return json(queue);
    if (url.startsWith('https://api.fal.ai/v1/models/billing-events')) {
      assert.ok(url.includes('request_id=' + requestId));
      return events === 'forbidden' ? json({ error: 'no' }, 403) : json({ billing_events: events, has_more: false, next_cursor: null });
    }
    if (url.endsWith('/status')) return json({ status: 'COMPLETED' });
    return json({ model_glb: { url: 'https://v3.fal.media/model.glb' } });
  };
  const paid = createFalMeshy({ secret: 'test', apiKey: 'test', billingDelayMs: 0, fetchImpl: billed([{ request_id: requestId, cost_total: 0.72 }]) });
  const job = await paid.start('owner', { requestId, prompt: 'a tree' });
  const done = await paid.read('owner', requestId, job.ticket);
  assert.equal(done.status, 'COMPLETED');
  assert.equal(done.costUsd, 0.72);
  const pending = createFalMeshy({ secret: 'test', apiKey: 'test', billingDelayMs: 0, fetchImpl: billed([]) });
  assert.equal((await pending.read('owner', requestId, job.ticket)).costUsd, null);
  const noRight = createFalMeshy({ secret: 'test', apiKey: 'test', billingDelayMs: 0, fetchImpl: billed('forbidden') });
  const result = await noRight.read('owner', requestId, job.ticket);
  assert.equal(result.status, 'COMPLETED');
  assert.equal(result.costUsd, null);
});
