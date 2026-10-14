import crypto from 'node:crypto';

function owner(req) {
  const identity = req.authProvider ? `${req.authProvider}:${req.user?.uid || req.user?.id}` : `app:${req.header('x-app-id') || 'default'}`;
  return crypto.createHash('sha256').update(identity).digest('hex');
}
function failure(res, error, submitting = false) {
  const status = Number(error.status) || 503;
  res.status(status).json({ error: error.message || 'Text job unavailable.', recoverable: !submitting && [408, 429, 500, 502, 503, 504].includes(status) });
}

export function registerTextJobRoutes(app, { requireAuth, jobs, prepare }) {
  app.get('/api/text/capabilities', requireAuth, (_, res) => res.json({ transport: 'text-jobs-v1', resumable: true }));
  app.post('/api/text/jobs', requireAuth, (req, res) => {
    try { res.status(202).json(jobs.start(owner(req), req.body?.requestId, prepare(req.body))); }
    catch (error) { failure(res, error, true); }
  });
  app.get('/api/text/jobs/:requestId', requireAuth, async (req, res) => {
    try { res.json(await jobs.read(owner(req), req.params.requestId, req.header('x-text-job-ticket'))); }
    catch (error) { failure(res, error); }
  });
  app.post('/api/text/jobs/:requestId/cancel', requireAuth, async (req, res) => {
    try { res.json(await jobs.cancel(owner(req), req.params.requestId, req.header('x-text-job-ticket'))); }
    catch (error) { failure(res, error); }
  });
}
