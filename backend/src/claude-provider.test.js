import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { prepareTextBody, createTextJobs } from './text-jobs.js';
import { prepareClaudeBody, readClaudeStream, createClaudeProvider } from './claude-provider.js';

const events = (stop = 'end_turn') => [
  { type: 'message_start', message: { model: 'claude-sonnet-5-5', usage: { input_tokens: 11 } } },
  { type: 'content_block_delta', delta: { type: 'thinking_delta', thinking: 'private' } },
  { type: 'content_block_delta', delta: { type: 'text_delta', text: '{"ok":true}' } },
  { type: 'message_delta', delta: { stop_reason: stop }, usage: { output_tokens: 9 } },
  { type: 'message_stop' },
];
const stream = (items) => new Response(items.map((item) => `data: ${JSON.stringify(item)}\n\n`).join(''), { headers: { 'Content-Type': 'text/event-stream' } });
const tick = () => new Promise((resolve) => setTimeout(resolve, 20));

test('Claude selection preserves references and never sends OpenAI-only fields', () => {
  const body = prepareTextBody({ provider: 'claude', model: 'gpt-6.1-sol', reasoningEffort: 'xhigh', json: true, content: [{ type: 'text', text: 'request' }, { type: 'image_url', image_url: { url: 'data:image/png;base64,YQ==' } }] }, 'gpt-6.1-sol');
  assert.equal(body.model, 'claude-sonnet-5-5');
  assert.equal(body.messages[0].content[1].source.type, 'base64');
  assert.equal(body.output_config.effort, 'high');
  assert.equal(body.input, undefined);
  assert.equal(body.reasoning, undefined);
  assert.match(body.system, /valid JSON/);
  assert.throws(() => prepareTextBody({ provider: 'unknown' }), /Unsupported/);
  assert.throws(() => prepareClaudeBody({ content: [{ type: 'text', text: 'x' }] }, 'gpt-6.1-sol'), /Invalid CLAUDE_MODEL/);
});

test('Claude stream normalizes usage and truncation without including thinking', async () => {
  const result = await readClaudeStream(stream(events('max_tokens')));
  assert.equal(result.status, 'incomplete');
  assert.equal(result.incomplete_details.reason, 'max_output_tokens');
  assert.equal(result.output[0].content[0].text, '{"ok":true}');
  assert.deepEqual(result.usage, { input_tokens: 11, output_tokens: 9 });
  await assert.rejects(readClaudeStream(stream(events().slice(0, -1))), /interrupted/);
});

test('Claude uses short job polling, survives lost browser connections and persists the completed result', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'claude-test-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  let calls = 0, finish;
  const provider = createClaudeProvider({ apiKey: 'test', workspaceId: 'workspace-test', directory, fetchImpl: async (url, input) => {
    calls++;
    assert.equal(url, 'https://api.anthropic.com/v1/messages');
    assert.equal(input.headers['anthropic-workspace-id'], 'workspace-test');
    assert.equal(JSON.parse(input.body).background, undefined);
    return new Promise((resolve) => { finish = () => resolve(stream(events())); });
  } });
  const setup = () => createTextJobs({ secret: 'test-secret', create: (body) => provider.create(body), retrieve: (id) => provider.retrieve(id), cancel: (id) => provider.cancel(id), extractText: (p) => p.output?.[0]?.content?.[0]?.text || '' });
  const jobs = setup(), requestId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  const body = prepareClaudeBody({ content: [{ type: 'text', text: 'go' }] });
  jobs.start('owner', requestId, body);
  for (let i = 0; !finish && i < 100; i++) await tick();
  const { ticket } = await jobs.read('owner', requestId);
  assert.ok(ticket);
  jobs.start('owner', requestId, body);
  assert.equal(calls, 1);
  finish();
  let result;
  for (let i = 0; i < 100; i++) { result = await setup().read('owner', requestId, ticket); if (result.result) break; await tick(); }
  assert.equal(result.result.text, '{"ok":true}');
  await tick();
  const restarted = createClaudeProvider({ apiKey: 'test', directory, fetchImpl: () => { throw new Error('Must not submit'); } });
  const claims = JSON.parse(Buffer.from(ticket.split('.')[0], 'base64url').toString());
  assert.equal((await restarted.retrieve(claims.responseId)).status, 'completed');
  assert.equal(calls, 1);
});

test('Claude cancellation aborts the original provider request and never starts another', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'claude-cancel-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  let signal;
  const provider = createClaudeProvider({ apiKey: 'test', directory, fetchImpl: (_, input) => {
    signal = input.signal;
    return new Promise((_, reject) => signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true }));
  } });
  const job = await provider.create(prepareClaudeBody({ content: [{ type: 'text', text: 'go' }] }));
  await provider.cancel(job.id);
  assert.equal(signal.aborted, true);
  await tick();
  assert.equal((await provider.retrieve(job.id)).status, 'cancelled');
});
