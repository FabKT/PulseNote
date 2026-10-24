/**
 * Banc d'essai des jeux CollabGaming : lance le code d'un jeu dans un navigateur invisible,
 * joue quelques actions et rend erreurs, journal, rapport de jouabilité et captures.
 * L'agent de jeu de CollabGaming s'en sert pour vérifier son travail avant de le livrer.
 *
 * Partage la machine des IA : UN SEUL essai à la fois, navigateur ouvert puis refermé à
 * chaque essai (mémoire rendue aussitôt), et chargé seulement à la demande (le démarrage du
 * serveur n'en dépend pas). Sur Linux (Render), Chromium autonome de @sparticuz/chromium.
 *
 *   POST /api/game/run  { bootDocument, start: { type: "start", code, context }, seconds?, shots?, inputs? }
 */
const MAX_SECONDS = 60;
let queue = Promise.resolve();

async function launchBrowser() {
  const { chromium } = await import('playwright-core');
  if (process.env.GAME_RUNNER_CHANNEL) return chromium.launch({ headless: true, channel: process.env.GAME_RUNNER_CHANNEL });
  const { default: portable } = await import('@sparticuz/chromium');
  return chromium.launch({
    headless: true,
    executablePath: await portable.executablePath(),
    // WebGL logiciel (pas de carte graphique) ; mémoire limitée.
    args: [...portable.args, '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--disable-dev-shm-usage'],
  });
}

/** Actions jouées pendant l'essai : touches (code DOM) et clics, à des instants donnés. */
async function play(page, inputs, t0) {
  for (const input of [...inputs].sort((a, b) => a.at - b.at)) {
    const wait = t0 + input.at * 1000 - Date.now();
    if (wait > 0) await page.waitForTimeout(wait);
    if (input.type === 'key') {
      await page.keyboard.down(input.key);
      await page.waitForTimeout(Math.min(5000, input.ms ?? 300));
      await page.keyboard.up(input.key);
    } else if (input.type === 'click') {
      await page.mouse.click(input.x ?? 480, input.y ?? 270, { button: input.button === 'right' ? 'right' : 'left' });
    }
  }
}

export async function runGame(body) {
  const seconds = Math.min(MAX_SECONDS, Math.max(3, Number(body.seconds ?? 12)));
  const shots = (body.shots ?? [seconds * 0.5, seconds]).map(Number).filter((s) => s >= 0 && s <= seconds).slice(0, 4);
  const result = { booted: false, ready: false, started: false, errors: [], logs: [], selfTest: null, metrics: null, renderingMode: null, screenshots: [] };
  const browser = await launchBrowser();
  try {
    // 960×540 : moitié moins de pixels à dessiner sans carte graphique, captures lisibles.
    const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
    page.on('pageerror', (e) => result.errors.push({ where: 'page', message: e.message }));
    await page.setContent(`<body style="margin:0;background:#000"><script>
      window.messages = [];
      addEventListener('message', e => {
        if (e.data?.type === 'booted') e.source.postMessage(window.start, '*');
        if (e.data?.source === 'cg-game') window.messages.push(e.data);
      });
    </script><iframe sandbox="allow-scripts allow-pointer-lock" style="border:0;width:100vw;height:100vh"></iframe></body>`);
    await page.evaluate((start) => { window.start = start; }, body.start);
    await page.locator('iframe').evaluate((frame, doc) => { frame.srcdoc = doc; }, body.bootDocument);
    await page.waitForFunction(() => window.messages.some((m) => m.type === 'ready' || m.type === 'error'), null, { timeout: 60_000 })
      .catch(() => result.errors.push({ where: 'essai', message: "Le jeu n'a pas démarré en 60 s." }));
    // « Cliquer pour jouer », puis les actions demandées.
    await page.mouse.click(480, 300);
    const t0 = Date.now();
    const inputs = play(page, (body.inputs ?? []).slice(0, 30), t0);
    for (const at of shots.sort((a, b) => a - b)) {
      const wait = t0 + at * 1000 - Date.now();
      if (wait > 0) await page.waitForTimeout(wait);
      const jpeg = await page.screenshot({ type: 'jpeg', quality: 62 });
      result.screenshots.push({ at, jpeg: jpeg.toString('base64') });
    }
    await inputs;
    const left = t0 + seconds * 1000 - Date.now();
    if (left > 0) await page.waitForTimeout(left);
    if (body.start?.context?.selfTest)
      await page.waitForFunction(() => window.messages.some((m) => m.type === 'selftest'), null, { timeout: 45_000 }).catch(() => undefined);
    for (const m of await page.evaluate(() => window.messages)) {
      if (m.type === 'booted') result.booted = true;
      else if (m.type === 'ready') result.ready = true;
      else if (m.type === 'started') result.started = true;
      else if (m.type === 'log') result.logs.push(String(m.text ?? '').slice(0, 500));
      else if (m.type === 'error') result.errors.push({ where: m.where ?? '', message: m.message ?? '', stack: String(m.stack ?? '').slice(0, 1500), scope: m.scope ?? 'game' });
      else if (m.type === 'selftest') result.selfTest = m.report ?? null;
      else if (m.type === 'rendering-mode') result.renderingMode = m.mode ?? null;
    }
    result.logs = result.logs.slice(-40);
    result.errors = result.errors.slice(0, 20);
    return result;
  } finally {
    await browser.close().catch(() => undefined);
  }
}

export function registerGameRunnerRoutes(app, { requireAuth }) {
  app.post('/api/game/run', requireAuth, async (req, res) => {
    // Désactivé par défaut : sur une petite instance, le navigateur épuise la mémoire et fait
    // redémarrer le serveur (IA des deux sites coupées). À activer seulement avec assez de mémoire.
    if (process.env.GAME_RUNNER_ENABLED !== 'true')
      return res.status(503).json({ error: "Banc d'essai désactivé sur ce serveur (mémoire insuffisante)." });
    const body = req.body ?? {};
    if (typeof body.bootDocument !== 'string' || typeof body.start?.code !== 'string')
      return res.status(400).json({ error: 'bootDocument et start.code sont obligatoires.' });
    // Un essai à la fois : les suivants attendent leur tour.
    const turn = queue.then(() => runGame(body));
    queue = turn.catch(() => undefined);
    try {
      res.json(await turn);
    } catch (error) {
      res.status(500).json({ error: `Banc d'essai : ${error instanceof Error ? error.message : String(error)}` });
    }
  });
}
