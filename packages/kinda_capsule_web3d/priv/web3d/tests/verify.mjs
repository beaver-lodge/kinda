import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(process.argv[2] || process.cwd());
const artifacts = path.resolve(process.argv[3] || path.join(root, 'artifacts'));
const require = createRequire(path.join(root, 'package.json'));
const { chromium } = require('@playwright/test');
const verifierDigest = createHash('sha256').update(await readFile(fileURLToPath(import.meta.url))).digest('hex');
await mkdir(artifacts, { recursive: true });
const vite = path.join(root, 'node_modules', 'vite', 'bin', 'vite.js');
const server = spawn(process.execPath, [vite, '--host', '127.0.0.1', '--port', '4173'], { cwd: root, stdio: 'ignore' });

try {
  await waitForServer('http://127.0.0.1:4173');
  const browser = await chromium.launch({ headless: true });

  const baseline = await browser.newPage({ viewport: { width: 1440, height: 900 } });
  await baseline.goto('http://127.0.0.1:4173/?mode=broken', { waitUntil: 'networkidle' });
  await baseline.screenshot({ path: path.join(artifacts, 'before.png') });
  await baseline.close();

  const context = await browser.newContext({ viewport: { width: 1440, height: 900 }, recordVideo: { dir: artifacts, size: { width: 1280, height: 720 } } });
  const page = await context.newPage();
  const consoleErrors = [];
  page.on('console', message => { if (message.type() === 'error') consoleErrors.push(message.text()); });
  page.on('pageerror', error => consoleErrors.push(error.message));
  const started = performance.now();
  await page.goto('http://127.0.0.1:4173', { waitUntil: 'networkidle' });
  const timeToInteractive = performance.now() - started;
  await page.waitForFunction(() => window.__web3dEpisode);
  await page.waitForFunction(() => window.__web3dEpisode.snapshot().metrics.frameCount >= 120);
  await page.evaluate(() => window.__web3dEpisode.resetMetrics());
  const initial = await snapshot(page);

  await page.locator('[data-hotspot="acoustic"]').hover();
  const canvas = page.locator('canvas');
  const box = await canvas.boundingBox();
  await page.mouse.move(box.x + box.width * .45, box.y + box.height * .5);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width * .68, box.y + box.height * .38, { steps: 14 });
  await page.mouse.up();
  await page.waitForTimeout(350);
  const afterDrag = await snapshot(page);

  await canvas.hover();
  await page.mouse.wheel(0, -2400);
  await page.mouse.wheel(0, 5000);
  const afterZoom = await snapshot(page);
  await page.setViewportSize({ width: 768, height: 720 });
  await page.waitForTimeout(100);
  const afterResize = await snapshot(page);
  await page.locator('[data-hotspot="controls"]').click();
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.waitForTimeout(150);
  await page.waitForFunction(() => window.__web3dEpisode.snapshot().metrics.frameCount >= 1200, null, { timeout: 30000 });
  const final = await snapshot(page);
  await page.screenshot({ path: path.join(artifacts, 'after.png') });

  const interaction = { initial, afterDrag, afterZoom, afterResize, final, consoleErrors, timeToInteractive };
  const performanceEvidence = { ...final.metrics, timeToInteractive, samples: final.metrics.frameCount, warmupFrames: 120 };
  const expertReview = {
    version: 'web3d-expert-illustrative@0.1.0',
    illustrative: true,
    score: .70,
    findings: [
    { code: 'hotspot_narrow_overlap', message: 'Hotspot 02 competes with the product silhouette at narrow viewport.', severity: 'warning', artifact: 'after.png' },
    { code: 'inertia_tail_knee', message: 'The inertia tail retains a slight visible deceleration knee.', severity: 'warning', artifact: 'interaction.webm', fragment: '04:10-04:14' },
    { code: 'reduced_motion_residual', message: 'A small residual camera response remains after reduced-motion activation.', severity: 'info', artifact: 'interaction.json', fragment: 'final' }
    ]
  };
  const browserEvidence = { browser: await browser.version(), viewport: '1440x900', device_pixel_ratio: 1, verifier_digest: verifierDigest };

  await writeJson('interaction.json', interaction);
  await writeJson('performance.json', performanceEvidence);
  await writeJson('expert-review.json', expertReview);
  await writeJson('browser.json', browserEvidence);
  const video = page.video();
  await page.close();
  await context.close();
  await video.saveAs(path.join(artifacts, 'interaction.webm'));
  await browser.close();
  await assertArtifacts(['before.png', 'after.png', 'interaction.webm', 'interaction.json', 'performance.json', 'expert-review.json', 'browser.json']);
  const envelope = { schema: 'kinda.web3d.evidence/v1', artifacts: {} };
  for (const name of ['before.png', 'after.png', 'interaction.webm', 'interaction.json', 'performance.json', 'expert-review.json', 'browser.json']) envelope.artifacts[name] = (await readFile(path.join(artifacts, name))).toString('base64');
  await writeStdout(JSON.stringify(envelope));

} finally {
  server.kill('SIGTERM');
}

async function snapshot(page) { return page.evaluate(() => window.__web3dEpisode.snapshot()); }
async function writeJson(name, value) { await writeFile(path.join(artifacts, name), JSON.stringify(value, null, 2)); }
async function writeStdout(value) { await new Promise((resolve, reject) => process.stdout.write(value, error => error ? reject(error) : resolve())); }
async function assertArtifacts(names) { for (const name of names) { const info = await stat(path.join(artifacts, name)); if (!info.isFile() || info.size === 0) throw new Error(`missing verifier artifact: ${name}`); } }
async function waitForServer(url) {
  for (let attempt = 0; attempt < 100; attempt++) {
    try { const response = await fetch(url); if (response.ok) return; } catch {}
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  throw new Error('Vite server did not become ready');
}
