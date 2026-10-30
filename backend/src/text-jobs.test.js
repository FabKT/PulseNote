import test from 'node:test';
import assert from 'node:assert/strict';
import { createTextJobs, prepareTextBody } from './text-jobs.js';

const id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const tick = () => new Promise((resolve) => setImmediate(resolve));
const pending = { id: 'resp_test', status: 'in_progress' };
const complete = { ...pending, status: 'completed', model: 'unchanged-model', output_text: '{"ok":true}', usage: { input_tokens: 3, output_tokens: 5 } };
function setup(overrides = {}) {
  return createTextJobs({ secret: 'test secret', create: async () => pending, retrieve: async () => complete, cancel: async () => ({ ...pending, status: 'cancelled' }), extractText: (payload) => payload.output_text || '', ...overrides });
}

test('acknowledgement is immediate and repeated submissions create only one provider response', async () => {
  let calls = 0;
  let finish;
  const jobs = setup({ create: (body) => {
    calls++;
    assert.equal(body.background, true);
    assert.equal(body.store, true);
    return new Promise((resolve) => { finish = resolve; });
  } });
  assert.equal(jobs.start('owner', id, { model: 'same' }).state, 'submitting');
  jobs.start('owner', id, { model: 'same' });
  await tick();
  assert.equal(calls, 1);
  finish(pending);
  await tick();
  const result = await jobs.read('owner', id);
  assert.equal(result.result.text, '{"ok":true}');
  assert.deepEqual(result.result.usage, complete.usage);
  assert.throws(() => jobs.start('owner', id, { model: 'changed' }), /different input/);
});

test('temporary status failures retain the provider ID without creating another response', async () => {
  let creates = 0;
  let reads = 0;
  const jobs = setup({ create: async () => { creates++; return pending; }, retrieve: async () => {
    if (++reads === 1) throw new Error('Socket closed');
    return complete;
  } });
  jobs.start('owner', id, {});
  await tick();
  await assert.rejects(jobs.read('owner', id), /Socket closed/);
  assert.equal((await jobs.read('owner', id)).result.status, 'completed');
  assert.equal(creates, 1);
});

test('overlapping status reads share the same provider request', async () => {
  let reads = 0;
  let finish;
  const jobs = setup({ retrieve: () => { reads++; return new Promise((resolve) => { finish = resolve; }); } });
  jobs.start('owner', id, {});
  await tick();
  const first = jobs.read('owner', id);
  const second = jobs.read('owner', id);
  assert.equal(reads, 1);
  finish(complete);
  assert.deepEqual(await first, await second);
});

test('a signed ticket restores a job after restart and is scoped to its owner and request', async () => {
  const first = setup({ retrieve: async () => pending });
  first.start('owner', id, {});
  await tick();
  const { ticket } = await first.read('owner', id);
  let creates = 0;
  const restarted = setup({ create: async () => { creates++; return pending; } });
  assert.equal((await restarted.read('owner', id, ticket)).result.status, 'completed');
  assert.equal(creates, 0);
  await assert.rejects(restarted.read('other-owner', id, ticket), /Invalid text job ticket/);
  await assert.rejects(restarted.read('owner', 'bbbbbbbb-bbbb-cccc-dddd-eeeeeeeeeeee', ticket), /Invalid text job ticket/);
  await assert.rejects(restarted.read('owner', id, `${ticket}x`), /Invalid text job ticket/);
});

test('an ambiguous provider submission is never automatically retried', async () => {
  let creates = 0;
  const jobs = setup({ create: async () => { creates++; throw new Error('Connection lost after upload'); } });
  jobs.start('owner', id, {});
  await tick();
  assert.equal((await jobs.read('owner', id)).state, 'submission_unknown');
  jobs.start('owner', id, {});
  await tick();
  assert.equal(creates, 1);
});

test('cancellation before provider submission prevents billing and later cancellation uses the original ID', async () => {
  let creates = 0;
  const early = setup({ create: async () => { creates++; return pending; } });
  early.start('owner', id, {});
  await early.cancel('owner', id);
  await tick();
  assert.equal(creates, 0);
  assert.equal((await early.read('owner', id)).state, 'cancelled');
  let cancelled;
  const later = setup({ cancel: async (responseId) => { cancelled = responseId; return { ...pending, status: 'cancelled' }; } });
  later.start('owner', id, {});
  await tick();
  assert.equal((await later.cancel('owner', id)).state, 'cancelled');
  assert.equal(cancelled, 'resp_test');
});

test('request preparation preserves models, images and token budgets', () => {
  const body = prepareTextBody({ model: 'gpt-6.1-sol', system: 'rules', reasoningEffort: 'high', json: true, maxOutputTokens: 125000, content: [{ type: 'text', text: 'request' }, { type: 'image_url', image_url: { url: 'https://example.com/image.png' } }] }, 'default');
  assert.equal(body.model, 'gpt-6.1-sol');
  assert.equal(body.max_output_tokens, 125000);
  assert.equal(body.input[1].content[1].type, 'input_image');
  assert.equal(body.reasoning.effort, 'high');
  assert.throws(() => prepareTextBody({ content: [] }, 'default'), /Missing text content/);
  assert.equal(prepareTextBody({ cacheKey: 'game-agent:p1', content: [{ type: 'text', text: 'x' }] }, 'default').prompt_cache_key, 'game-agent:p1');
  assert.equal(prepareTextBody({ cacheKey: 'bad key!', content: [{ type: 'text', text: 'x' }] }, 'default').prompt_cache_key, undefined);
});

test('a full job table frees the oldest finished jobs instead of refusing new work', async () => {
  let clock = 0;
  const jobs = setup({ now: () => clock, maxJobs: 3 });
  const ids = ['1', '2', '3', '4'].map((n) => `aaaaaaaa-bbbb-cccc-dddd-00000000000${n}`);
  for (const job of ids.slice(0, 3)) { clock++; jobs.start('owner', job, { model: 'm' }); }
  await tick();
  for (const job of ids.slice(0, 3)) await jobs.read('owner', job);
  clock++;
  assert.equal(jobs.start('owner', ids[3], { model: 'm' }).state, 'submitting');
  await assert.rejects(() => jobs.read('owner', ids[0]), /not found/);
  assert.equal((await jobs.read('owner', ids[1])).state, 'completed');
});

test('stale jobs are forgotten after their retention time', async () => {
  let clock = 0;
  const jobs = setup({ now: () => clock, maxJobs: 2, create: () => new Promise(() => {}) });
  jobs.start('owner', 'aaaaaaaa-bbbb-cccc-dddd-000000000001', { model: 'm' });
  jobs.start('owner', 'aaaaaaaa-bbbb-cccc-dddd-000000000002', { model: 'm' });
  assert.throws(() => jobs.start('owner', 'aaaaaaaa-bbbb-cccc-dddd-000000000003', { model: 'm' }), /capacity/);
  clock = 6 * 3_600_000 + 1;
  assert.equal(jobs.start('owner', 'aaaaaaaa-bbbb-cccc-dddd-000000000003', { model: 'm' }).state, 'submitting');
});
