import express from 'express';
import test from 'node:test';
import assert from 'node:assert/strict';
import { registerTextJobRoutes } from './text-job-routes.js';
import { createTextJobs, prepareTextBody } from './text-jobs.js';

test('authenticated HTTP endpoints acknowledge promptly, recover reads and isolate owners', { timeout: 5000 }, async () => {
  let creates = 0;
  let reads = 0;
  const jobs = createTextJobs({ secret: 'test key',
    create: async () => { creates++; return { id: 'resp_test', status: 'in_progress' }; },
    retrieve: async () => {
      if (++reads === 1) throw Object.assign(new Error('Temporary outage'), { status: 503 });
      return { status: 'completed', model: 'same-model', output_text: '{"ok":true}' };
    }, cancel: async () => ({ status: 'cancelled' }), extractText: (payload) => payload.output_text || '',
  });
  const app = express();
  app.use(express.json());
  registerTextJobRoutes(app, { jobs, prepare: (input) => prepareTextBody(input, 'same-model'), requireAuth: (req, res, next) => {
    if (req.header('x-app-token') !== 'test token') return res.status(401).json({ error: 'Unauthorized' });
    next();
  } });
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  const headers = { 'x-app-token': 'test token', 'x-app-id': 'first', 'Content-Type': 'application/json' };
  const requestId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  try {
    assert.equal((await fetch(`${origin}/api/text/capabilities`)).status, 401);
    assert.equal((await fetch(`${origin}/api/text/capabilities`, { headers })).status, 200);
    assert.equal((await fetch(`${origin}/api/text/jobs`, { method: 'POST', headers, body: JSON.stringify({ requestId, content: [] }) })).status, 400);
    assert.equal(creates, 0);
    const body = JSON.stringify({ requestId, model: 'same-model', content: [{ type: 'text', text: 'test' }] });
    const started = await fetch(`${origin}/api/text/jobs`, { method: 'POST', headers, body });
    assert.equal(started.status, 202);
    assert.equal((await started.json()).requestId, requestId);
    assert.equal((await fetch(`${origin}/api/text/jobs`, { method: 'POST', headers, body })).status, 202);
    assert.equal(creates, 1);
    const statusUrl = `${origin}/api/text/jobs/${requestId}`;
    assert.equal((await fetch(statusUrl, { headers: { ...headers, 'x-app-id': 'other' } })).status, 404);
    const disconnected = await fetch(statusUrl, { headers });
    assert.equal(disconnected.status, 503);
    assert.equal((await disconnected.json()).recoverable, true);
    const recovered = await (await fetch(statusUrl, { headers })).json();
    assert.equal(recovered.result.text, '{"ok":true}');
    assert.equal(creates, 1);
    assert.equal((await fetch(`${origin}/api/text/capabilities`, { headers })).headers.get('cache-control'), 'no-store');
    assert.equal((await fetch(statusUrl, { headers: { ...headers, 'x-app-id': 'other', 'x-text-job-ticket': recovered.ticket } })).status, 403);
  } finally {
    server.closeAllConnections();
    await new Promise((resolve) => server.close(resolve));
  }
});
