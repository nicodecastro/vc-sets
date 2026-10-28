import assert from 'node:assert/strict';
import {after, before, test} from 'node:test';
import {createServer} from 'node:http';
import {createHash} from 'node:crypto';
import {readFile, mkdir, writeFile, mkdtemp, rm} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve, extname} from 'node:path';

const {chromium, webkit} = await import(process.env.VC_SETS_PLAYWRIGHT || 'playwright');
const directory = fileURLToPath(new URL('../../build/web/', import.meta.url));
const fixture = fileURLToPath(new URL('fixture.vcbackup', import.meta.url));
const output = fileURLToPath(new URL('test-results/', import.meta.url));
const hash = value => createHash('sha256').update(value).digest('hex');
const index = await readFile(resolve(directory, 'index.html'), 'utf8');
const base = index.match(/<base href="([^"]+)"/)[1];
const originalWorker = await readFile(resolve(directory, 'flutter_service_worker.js'), 'utf8');
const originalVersion = JSON.parse(originalWorker.match(/const VERSION = (.*);/)[1]);
const originalAssets = JSON.parse(originalWorker.match(/const ASSETS = (.*);/)[1]);
const originalBootstrap = await readFile(resolve(directory, 'flutter_bootstrap.js'), 'utf8');
let server, origin;
let release = 'a', broken = null, disconnected = false, interruptDownload = false;
const served = [];
const mime = {'.js': 'text/javascript', '.html': 'text/html', '.json': 'application/json',
  '.wasm': 'application/wasm', '.png': 'image/png', '.ttf': 'font/ttf', '.otf': 'font/otf'};
const version = () => release === 'a' ? originalVersion : hash(release);
const bootstrap = () => originalBootstrap.replaceAll(originalVersion, version());
const worker = () => {
  const assets = {...originalAssets, 'flutter_bootstrap.js': hash(bootstrap())};
  return originalWorker.replace(/const VERSION = .*;/, `const VERSION = "${version()}";`)
    .replace(/const ASSETS = .*;/, `const ASSETS = ${JSON.stringify(assets)};`);
};

before(async () => {
  assert(base.startsWith('/') && base !== '/', 'Test a GitHub Pages repository subpath');
  await mkdir(output, {recursive: true});
  server = createServer(async (request, response) => {
    const pathname = new URL(request.url, 'http://localhost').pathname;
    if (disconnected) { response.destroy(); return; }
    served.push(pathname);
    response.setHeader('Cache-Control', 'no-store');
    try {
      if (!pathname.startsWith(base)) {
        response.writeHead(404).end('Outside app scope'); return;
      }
      let path = decodeURIComponent(pathname.slice(base.length)) || 'index.html';
      if (path === broken) {
        if (interruptDownload) response.destroy();
        else response.writeHead(200).end('Corrupt asset');
        return;
      }
      let body;
      if (path === 'flutter_service_worker.js') body = worker();
      else if (path === 'flutter_bootstrap.js') body = bootstrap();
      else {
        const file = resolve(directory, path);
        assert(file.startsWith(directory));
        try { body = await readFile(file); }
        catch { path = 'index.html'; body = index; }
      }
      response.setHeader('Content-Type', mime[extname(path)] || 'application/octet-stream');
      response.end(body);
    } catch (_) { response.writeHead(500).end(); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  origin = `http://127.0.0.1:${server.address().port}`;
});
after(async () => { await new Promise(resolve => server.close(resolve)); });

async function ready(page) {
  await page.waitForFunction(() => window.vcSetsOffline?.state === 'ready', null,
    {timeout: 90000});
}
async function poll(page, expression, argument, timeout = 30000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    if (await page.evaluate(expression, argument)) return;
    await page.waitForTimeout(100);
  }
  throw new Error('Timed out waiting for service worker lifecycle');
}
async function semantics(page) {
  await page.bringToFront();
  await page.waitForFunction(() => {
    document.querySelectorAll('flt-semantics-placeholder').forEach(element => element.click());
    return document.querySelectorAll('flt-semantics[role="button"]').length > 0;
  });
}
async function launch(engine) {
  const type = engine === 'chromium' ? chromium : webkit;
  return type.launch({headless: true,
    ...(engine === 'chromium' && process.env.VC_SETS_CHROMIUM_PATH
      ? {executablePath: process.env.VC_SETS_CHROMIUM_PATH} : {}),
  });
}
async function activeVersion(page) {
  return page.evaluate(() => new Promise((resolve, reject) => {
    const channel = new MessageChannel();
    const timeout = setTimeout(() => {channel.port1.close(); reject(new Error('Worker status timed out'));}, 15000);
    channel.port1.onmessage = event => {
      clearTimeout(timeout); channel.port1.close(); resolve(event.data.version);
    };
    navigator.serviceWorker.controller.postMessage({type: 'OFFLINE_STATUS'}, [channel.port2]);
  }));
}
async function run(engine, body) {
  release = 'a'; broken = null; disconnected = false; interruptDownload = false;
  const browser = await launch(engine);
  const context = await browser.newContext({viewport: {width: 1280, height: 1000}});
  const external = [];
  context.on('request', request => {
    if (/^https?:/.test(request.url()) && !request.url().startsWith(origin)) {
      external.push(request.url());
    }
  });
  context.setDefaultTimeout(30000);
  try {
    await body(context);
    assert.deepEqual(external, [], 'No runtime CDN or font requests');
  } catch (error) {
    for (const [index, page] of context.pages().entries()) {
      await page.screenshot({path: resolve(output, `${engine}-failure-${index}.png`)}).catch(() => {});
      await writeFile(resolve(output, `${engine}-failure-${index}.html`), await page.content()).catch(() => {});
    }
    throw error;
  } finally { await browser.close(); }
}

for (const engine of (process.env.VC_SETS_BROWSERS || 'chromium,webkit').split(',')) {
  test(`${engine}: a fully restarted browser loads saved data without a server`,
    {timeout: 180000}, async () => {
      release = 'a'; broken = null; disconnected = false; interruptDownload = false;
      const profile = await mkdtemp(resolve(output, `${engine}-profile-`));
      const type = engine === 'chromium' ? chromium : webkit;
      const options = {headless: true, viewport: {width: 1280, height: 1000},
        ...(engine === 'chromium' && process.env.VC_SETS_CHROMIUM_PATH
          ? {executablePath: process.env.VC_SETS_CHROMIUM_PATH} : {}),
      };
      let context;
      try {
        context = await type.launchPersistentContext(profile, options);
        let page = context.pages()[0] || await context.newPage();
        await page.goto(`${origin}${base}#/tournaments`); await ready(page); await semantics(page);
        await page.getByRole('button', {name: 'New tournament', exact: true}).click();
        await page.getByRole('textbox', {name: 'Tournament name', exact: true}).fill('Cold start cup');
        await page.getByRole('button', {name: 'Create', exact: true}).click();
        await page.getByRole('group', {name: /Cold start cup/}).waitFor();
        await context.close(); context = null;
        disconnected = true;
        context = await type.launchPersistentContext(profile, options);
        if (engine === 'chromium') await context.setOffline(true);
        page = context.pages()[0] || await context.newPage();
        await page.goto(`${origin}${base}#/tournaments`); await ready(page); await semantics(page);
        await page.getByRole('button', {name: /Cold start cup/}).waitFor();
        await page.screenshot({path: resolve(output, `${engine}-cold-start.png`)});
      } finally {
        if (context) await context.close();
        assert(profile.startsWith(output));
        await rm(profile, {recursive: true, force: true, maxRetries: 3});
      }
    });

  test(`${engine}: denied persistence still works; unavailable storage cannot advertise readiness`,
    {timeout: 180000}, () => run(engine, async context => {
      await context.addInitScript(() => {
        if (navigator.storage) navigator.storage.persist = async () => false;
      });
      const page = await context.newPage();
      await page.goto(`${origin}${base}`); await ready(page); await semantics(page);
      await page.setViewportSize({width: 390, height: 844});
      const app = page.locator('flt-semantics-host');
      await app.getByText('Ready for offline use', {exact: true}).waitFor();
      await page.screenshot({path: resolve(output, `${engine}-readiness-phone.png`)});
      await page.evaluate(() => window.vcSetsOffline.databaseReady(false));
      await app.getByText('This browser cannot save data between visits. Export a backup before closing.',
        {exact: true}).waitFor();
      assert.equal(await app.getByText('Ready for offline use', {exact: true}).count(), 0);
    }));

  test(`${engine}: unsupported service workers are reported honestly`,
    {timeout: 180000}, () => run(engine, async context => {
      await context.addInitScript(() => {
        Object.defineProperty(navigator, 'serviceWorker', {value: undefined});
      });
      const page = await context.newPage();
      await page.goto(`${origin}${base}`); await semantics(page);
      await page.locator('flt-semantics-host').getByText('Offline loading is unavailable in this browser or preview.',
        {exact: true}).waitFor();
      assert.equal(await page.getByText('Ready for offline use', {exact: true}).count(), 0);
    }));

  test(`${engine}: offline restart preserves data, scoring, reports and exports`,
    {timeout: 240000}, () => run(engine, async context => {
      let page = await context.newPage();
      await page.goto(`${origin}${base}#/backup`);
      await ready(page); await semantics(page);
      const emptyDownload = page.waitForEvent('download');
      await page.getByRole('button', {name: 'Export full backup', exact: true}).click();
      const empty = JSON.parse(await readFile(await (await emptyDownload).path(), 'utf8'));
      const backup = JSON.parse(await readFile(fixture, 'utf8'));
      backup.payload.deviceId = empty.payload.deviceId;
      for (const game of backup.payload.tournaments[0].games) {
        for (const log of game.logs) log.deviceId = empty.payload.deviceId;
      }
      backup.manifest.payloadSha256 = hash(JSON.stringify(backup.payload));
      const chooser = page.waitForEvent('filechooser');
      await page.getByRole('button', {name: 'Preview & restore', exact: true}).click();
      await (await chooser).setFiles({name: 'fixture.vcbackup', mimeType: 'application/json',
        buffer: Buffer.from(JSON.stringify(backup))});
      await page.getByRole('button', {name: 'Replace local data', exact: true}).click();
      await page.getByText('Backup restored successfully.', {exact: true}).waitFor();
      // A sentinel from a different project on the same origin must survive activation.
      await page.evaluate(async () => {
        const cache = await caches.open('vc-sets:/other-project/:sentinel');
        await cache.put('/other-project/test', new Response('keep'));
      });
      const keeper = await context.newPage();
      await keeper.goto(`${origin}/outside`);
      await page.close();
      // Dropped connections also test WebKit without its protocol-level offline
      // emulation, which prevents even service-worker navigations on Windows.
      disconnected = true;
      if (engine === 'chromium') await context.setOffline(true);
      const requestsBefore = served.length;
      page = await context.newPage();
      await page.goto(`${origin}${base}#/tournaments`);
      await ready(page); await semantics(page);
      await page.getByRole('button', {name: /Club Cup/}).waitFor();
      await page.goto(`${origin}${base}#/tournaments/tournament/games/game/track`);
      // Semantics remains enabled within a document, but goto creates a new document.
      await semantics(page);
      await page.getByRole('button', {name: 'OPP ERR  •  OP+', exact: true}).click();
      await page.getByRole('button', {name: 'Enter', exact: true}).click();
      // Export through the real app and inspect the saved rally, not only the UI.
      await page.goto(`${origin}${base}#/backup`);
      await ready(page); await semantics(page);
      const download = page.waitForEvent('download');
      await page.getByRole('button', {name: 'Export full backup', exact: true}).click();
      const exported = JSON.parse(await readFile(await (await download).path(), 'utf8'));
      assert.equal(exported.payload.tournaments[0].games[0].logs[0].rallies.length, 1);
      await page.goto(`${origin}${base}#/reports`);
      await ready(page); await semantics(page);
      await page.getByRole('button', {name: 'Standings CSV', exact: true}).waitFor();
      const csvDownload = page.waitForEvent('download');
      await page.getByRole('button', {name: 'Standings CSV', exact: true}).click();
      const csv = await readFile(await (await csvDownload).path(), 'utf8');
      assert(csv.includes('Home Club') && csv.includes('Away Club'));
      assert.match(csv, /"Home Club",1,1,0,3,1,0,1,0/,
        'The finalized fixture contributes one win and one point to standings');
      assert.equal(served.length, requestsBefore, 'Offline restart never reaches the server');
      await page.screenshot({path: resolve(output, `${engine}-offline-reports.png`)});
    }));

  test(`${engine}: incomplete preparation withholds readiness and retries`,
    {timeout: 180000}, () => run(engine, async context => {
      const page = await context.newPage();
      // Use an unused precached asset so scoring itself can still start.
      broken = Object.keys(originalAssets).find(path => path.includes('skwasm') && path.endsWith('.wasm'));
      assert(broken);
      interruptDownload = true;
      await page.goto(`${origin}${base}`);
      await page.waitForFunction(() => window.vcSetsOffline?.state === 'failed', null,
        {timeout: 90000});
      await semantics(page);
      await page.getByRole('group', {name: 'Offline preparation failed. Reconnect and retry.', exact: true}).waitFor();
      assert.equal(await page.getByText('Ready for offline use', {exact: true}).count(), 0);
      broken = null;
      interruptDownload = false;
      await page.getByRole('button', {name: 'Retry', exact: true}).click();
      await ready(page);
    }));

  test(`${engine}: failed update preserves release; complete update waits for all windows`,
    {timeout: 240000}, () => run(engine, async context => {
      let page = await context.newPage();
      await page.goto(`${origin}${base}#/tournaments`);
      await ready(page); await semantics(page);
      await page.getByRole('button', {name: 'New tournament', exact: true}).click();
      await page.getByRole('textbox', {name: 'Tournament name', exact: true}).fill('Survives update');
      await page.getByRole('button', {name: 'Create', exact: true}).click();
      const second = await context.newPage();
      await second.goto(`${origin}${base}`); await ready(second);
      await page.evaluate(async () => {
        const cache = await caches.open('vc-sets:/other-project/:sentinel');
        await cache.put('/other-project/test', new Response('keep'));
      });
      release = 'b';
      broken = Object.keys(originalAssets).find(path => path.includes('skwasm') && path.endsWith('.wasm'));
      await page.evaluate(async () => {
        const registration = await navigator.serviceWorker.getRegistration();
        window.failedUpdate = false;
        registration.addEventListener('updatefound', () => {
          const worker = registration.installing;
          worker.addEventListener('statechange', () => {
            if (worker.state === 'redundant') window.failedUpdate = true;
          });
        });
        await registration.update();
      });
      await page.waitForFunction(() => window.failedUpdate, null, {timeout: 90000});
      await ready(page);
      disconnected = true;
      if (engine === 'chromium') await context.setOffline(true);
      await page.reload(); await ready(page); await semantics(page);
      await page.getByRole('group', {name: /Survives update/}).waitFor();
      await page.evaluate(() => window.noReloadMarker = 'scoring continues');
      disconnected = false;
      await context.setOffline(false);
      broken = null; release = 'c';
      await page.evaluate(async () => (await navigator.serviceWorker.getRegistration()).update());
      await poll(page, async () => Boolean((await navigator.serviceWorker.getRegistration()).waiting),
        null, 90000);
      assert.equal(await activeVersion(page), originalVersion);
      assert.equal(await page.evaluate(() => window.noReloadMarker), 'scoring continues',
        'An update must not reload an open app');
      assert.equal(await page.evaluate(() => window.vcSetsOffline.state), 'ready');
      await poll(second, async () => Boolean((await navigator.serviceWorker.getRegistration()).waiting));
      await page.close();
      assert.equal(await activeVersion(second), originalVersion,
        'Closing only one window must not activate an update');
      // Keep the profile alive with a page outside the worker scope until activation completes.
      const observer = await context.newPage();
      await observer.goto(`${origin}/outside`);
      await second.close();
      try {
        await poll(observer, async ({scope, expected}) => {
          const registration = await navigator.serviceWorker.getRegistration(scope);
          if (registration?.active?.state !== 'activated') return false;
          return new Promise(resolve => {
            const channel = new MessageChannel();
            const timeout = setTimeout(() => {channel.port1.close(); resolve(false);}, 2000);
            channel.port1.onmessage = event => {
              clearTimeout(timeout); channel.port1.close();
              resolve(event.data.version === expected && event.data.complete);
            };
            registration.active.postMessage({type: 'OFFLINE_STATUS'}, [channel.port2]);
          });
        }, {scope: `${origin}${base}`, expected: hash('c')}, 90000);
      } catch (error) {
        console.log('Remaining worker clients', JSON.stringify(await Promise.all(context.serviceWorkers().map(worker =>
          worker.evaluate(async () => ({version: VERSION, clients: (await self.clients.matchAll({includeUncontrolled: true}))
            .map(client => ({id: client.id, url: client.url, type: client.type}))})).catch(() => null)))));
        throw error;
      }
      disconnected = true;
      if (engine === 'chromium') await context.setOffline(true);
      page = await context.newPage();
      await page.goto(`${origin}${base}#/tournaments`); await ready(page); await semantics(page);
      await page.getByRole('button', {name: /Survives update/}).waitFor();
      const names = await page.evaluate(() => caches.keys());
      assert(names.includes('vc-sets:/other-project/:sentinel'));
      const ours = names.filter(name => name.startsWith(`vc-sets:${base}:`));
      assert.deepEqual(ours, [`vc-sets:${base}:${hash('c')}`]);
    }));
}
