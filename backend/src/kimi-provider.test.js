import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { prepareKimiBody, readKimiStream, createKimiProvider, kimiApiKey } from './kimi-provider.js';
import { prepareTextBody } from './text-jobs.js';

const stream = (frames) => ({
  body: (async function* () {
    for (const frame of frames) yield new TextEncoder().encode(`data: ${frame}\n\n`);
  })(),
});
const chunk = (delta, extra = {}) => JSON.stringify({ model: 'kimi-k3.1-pro', choices: [{ delta, ...extra }] });

test('Kimi body: messages, JSON, cache key, reasoning and images', () => {
  const body = prepareKimiBody({
    system: 'rules',
    json: true,
    cacheKey: 'game-agent:p1',
    reasoningEffort: 'medium',
    maxOutputTokens: 5000,
    content: [{ type: 'text', text: 'fixed', cache: true }, { type: 'image_url', image_url: { url: 'data:image/jpeg;base64,AAAA' } }],
  });
  assert.equal(body.model, 'kimi-k3.1-pro');
  assert.deepEqual(body.messages[0], { role: 'system', content: 'rules' });
  assert.deepEqual(body.messages[1].content, [{ type: 'text', text: 'fixed' }, { type: 'image_url', image_url: { url: 'data:image/jpeg;base64,AAAA' } }]);
  assert.deepEqual(body.response_format, { type: 'json_object' });
  assert.equal(body.prompt_cache_key, 'game-agent:p1');
  assert.equal(body.reasoning_effort, 'high');
  assert.equal(body.max_completion_tokens, 5000);
  assert.equal(body.stream, true);
  assert.deepEqual(body.stream_options, { include_usage: true });
  assert.equal(prepareKimiBody({ reasoningEffort: 'low', content: [{ type: 'text', text: 'x' }] }).reasoning_effort, 'low');
  assert.equal(prepareKimiBody({ reasoningEffort: 'xhigh', content: [{ type: 'text', text: 'x' }] }).reasoning_effort, 'max');
  assert.throws(() => prepareKimiBody({ content: [] }), /Missing text content/);
  assert.throws(() => prepareKimiBody({ content: [{ type: 'text', text: 'x' }] }, 'gpt-5'), /Invalid KIMI_MODEL/);
});

test('Kimi is the third text provider', () => {
  assert.equal(prepareTextBody({ provider: 'kimi', content: [{ type: 'text', text: 'x' }] }, 'gpt-default').model, 'kimi-k3.1-pro');
  assert.equal(prepareTextBody({ provider: 'kimi', content: [{ type: 'text', text: 'x' }] }, 'gpt-default', undefined, 'kimi-k3').model, 'kimi-k3');
  assert.throws(() => prepareTextBody({ provider: 'other', content: [{ type: 'text', text: 'x' }] }, 'gpt'), /Unsupported/);
});

test('Kimi key is read under the usual names', () => {
  assert.equal(kimiApiKey({ MOONSHOT_API_KEY: ' sk-1 ' }), 'sk-1');
  assert.equal(kimiApiKey({ KIMI_API_KEY: 'sk-2', MOONSHOT_API_KEY: 'sk-1' }), 'sk-2');
  assert.equal(kimiApiKey({}), '');
});

test('Kimi stream: text without reasoning, usage with cache, truncation', async () => {
  const usage = { prompt_tokens: 1000, completion_tokens: 40, prompt_tokens_details: { cached_tokens: 900 }, completion_tokens_details: { reasoning_tokens: 30 } };
  const result = await readKimiStream(stream([
    chunk({ reasoning_content: 'je réfléchis' }),
    chunk({ content: '{"ok":' }),
    chunk({ content: 'true}' }, { finish_reason: 'stop' }),
    JSON.stringify({ model: 'kimi-k3.1-pro', choices: [], usage }),
    '[DONE]',
  ]));
  assert.equal(result.status, 'completed');
  assert.equal(result.output[0].content[0].text, '{"ok":true}');
  assert.deepEqual(result.usage, { input_tokens: 1000, output_tokens: 40, input_tokens_details: { cached_tokens: 900 }, output_tokens_details: { reasoning_tokens: 30 } });
  const cut = await readKimiStream(stream([chunk({ content: '{"a"' }, { finish_reason: 'length' }), '[DONE]']));
  assert.equal(cut.status, 'incomplete');
  assert.equal(cut.incomplete_details.reason, 'max_output_tokens');
  await assert.rejects(readKimiStream(stream([chunk({ content: 'x' })])), /interrupted/);
});

test('Kimi provider: background job, result kept on disk, provider error surfaced', async () => {
  const directory = path.join(os.tmpdir(), `kimi-test-${crypto.randomUUID()}`);
  const calls = [];
  const ok = createKimiProvider({
    apiKey: 'sk-test',
    directory,
    fetchImpl: async (url, init) => {
      calls.push({ url, auth: init.headers.Authorization, body: JSON.parse(init.body) });
      return { ok: true, ...stream([chunk({ content: '{"ok":true}' }, { finish_reason: 'stop' }), '[DONE]']) };
    },
  });
  const started = await ok.create(prepareKimiBody({ content: [{ type: 'text', text: 'go' }] }));
  assert.match(started.id, /^resp_kimi_/);
  let done;
  for (let i = 0; i < 50 && (!done || done.status === 'in_progress'); i++) {
    await new Promise((r) => setTimeout(r, 10));
    done = await ok.retrieve(started.id);
  }
  assert.equal(done.status, 'completed');
  assert.equal(calls[0].url, 'https://api.moonshot.ai/v1/chat/completions');
  assert.equal(calls[0].auth, 'Bearer sk-test');
  const failing = createKimiProvider({ apiKey: 'sk-test', directory, fetchImpl: async () => ({ ok: false, status: 400, text: async () => '{"error":{"message":"bad model"}}' }) });
  const bad = await failing.create(prepareKimiBody({ content: [{ type: 'text', text: 'go' }] }));
  let failed;
  for (let i = 0; i < 50 && (!failed || failed.status === 'in_progress'); i++) {
    await new Promise((r) => setTimeout(r, 10));
    failed = await failing.retrieve(bad.id);
  }
  assert.equal(failed.status, 'failed');
  assert.match(failed.error.message, /Kimi HTTP 400: .*bad model/);
  await assert.rejects(createKimiProvider({ apiKey: '', directory }).create({ model: 'kimi-k3.1-pro' }), /not configured/);
});
