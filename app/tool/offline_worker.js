'use strict';

const ROOT = new URL(self.registration.scope);
const PREFIX = `vc-sets:${ROOT.pathname}:`;
const CACHE = `${PREFIX}${VERSION}`;
const COMPLETE = new URL('__offline_complete__', ROOT).href;
const assetUrl = path => new URL(path, ROOT).href;
const hex = buffer => [...new Uint8Array(buffer)]
  .map(byte => byte.toString(16).padStart(2, '0')).join('');

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    try {
      // Verify responses too: a CDN may briefly serve files from two releases.
      // Sequential downloads bound memory use on phones during WASM hashing.
      for (const [path, digest] of Object.entries(ASSETS)) {
        const controller = new AbortController();
        const timeout = setTimeout(() => controller.abort(), 30000);
        try {
          const response = await fetch(assetUrl(path), {cache: 'reload', signal: controller.signal});
          if (!response.ok || hex(await crypto.subtle.digest(
            'SHA-256', await response.clone().arrayBuffer())) !== digest) {
            throw new Error(`Offline preparation failed: ${path}`);
          }
          await cache.put(assetUrl(path), response);
        } finally {
          clearTimeout(timeout);
        }
      }
      await cache.put(COMPLETE, new Response(VERSION));
    } catch (error) {
      await caches.delete(CACHE);
      throw error;
    }
    // Updates wait for all old clients to close. Never interrupt live scoring.
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    if (!(await cache.match(COMPLETE))) throw new Error('Incomplete offline cache');
    for (const name of await caches.keys()) {
      if (name.startsWith(PREFIX) && name !== CACHE) await caches.delete(name);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== ROOT.origin ||
      !url.pathname.startsWith(ROOT.pathname)) return;
  const path = decodeURIComponent(url.pathname.slice(ROOT.pathname.length));
  if (event.request.mode !== 'navigate' && !(path in ASSETS)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const key = event.request.mode === 'navigate' ? 'index.html' : path;
    const response = await cache.match(assetUrl(key));
    // Do not silently mix a damaged cached release with files from a newer one.
    return response || new Response('App files are missing. Reconnect and prepare offline use again.',
      {status: 503, headers: {'Content-Type': 'text/plain'}});
  })());
});

self.addEventListener('message', event => {
  if (event.data?.type !== 'OFFLINE_STATUS' || !event.ports[0]) return;
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    const complete = Boolean(await cache.match(COMPLETE)) &&
      (await Promise.all(Object.keys(ASSETS).map(path =>
        cache.match(assetUrl(path))))).every(Boolean);
    event.ports[0].postMessage({version: VERSION, complete});
  })());
});
