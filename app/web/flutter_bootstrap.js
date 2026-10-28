{{flutter_js}}
{{flutter_build_config}}

(() => {
  const version = '__VC_SETS_BUILD__';
  const listeners = new Set();
  let databaseReady = false;
  let storageAvailable = true;
  let checking = false;
  let registration;
  const offline = window.vcSetsOffline = {
    state: 'preparing',
    subscribe(callback) { listeners.add(callback); callback(offline.state); },
    databaseReady(available) {
      storageAvailable = available;
      databaseReady = true;
      if (!available) publish('storage-unavailable');
      else check();
    },
    retry() { prepare(); },
  };
  function publish(state) {
    offline.state = state;
    for (const callback of listeners) callback(state);
  }
  function status(worker) {
    return new Promise((resolve, reject) => {
      const channel = new MessageChannel();
      const timeout = setTimeout(() => {
        channel.port1.close();
        reject(new Error('Offline status timed out'));
      }, 15000);
      channel.port1.onmessage = event => {
        clearTimeout(timeout);
        channel.port1.close();
        resolve(event.data);
      };
      worker.postMessage({type: 'OFFLINE_STATUS'}, [channel.port2]);
    });
  }
  async function check() {
    if (!databaseReady || !storageAvailable || checking || !navigator.serviceWorker?.controller) return;
    checking = true;
    try {
      const result = await status(navigator.serviceWorker.controller);
      if (!storageAvailable) return;
      publish(result.complete && result.version === version ? 'ready' : 'failed');
    } catch (_) { if (storageAvailable) publish('failed'); }
    finally { checking = false; }
  }
  function watch(worker) {
    if (!worker) return;
    worker.addEventListener('statechange', () => {
      if (worker.state === 'activated') check();
      if (worker.state === 'redundant' && offline.state !== 'ready' && storageAvailable) publish('failed');
    });
  }
  async function prepare() {
    if (!navigator.serviceWorker || !window.isSecureContext ||
        !('caches' in window)) { publish('unsupported'); return; }
    if (version.startsWith('__')) { publish('unsupported'); return; }
    if (!storageAvailable) { publish('storage-unavailable'); return; }
    publish('preparing');
    try {
      await check();
      const root = new URL('.', document.baseURI);
      registration = await navigator.serviceWorker.register(
        new URL('flutter_service_worker.js', root),
        {scope: root.pathname, updateViaCache: 'none'},
      );
      watch(registration.installing);
      registration.addEventListener('updatefound', () => watch(registration.installing));
      await check();
      // Denial or an unsupported persistence API must not block scoring.
      navigator.storage?.persist?.().catch(() => {});
    } catch (_) {
      if (offline.state !== 'ready' && storageAvailable) publish('failed');
    }
  }
  navigator.serviceWorker?.addEventListener('controllerchange', check);
  window.addEventListener('pageshow', check);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') check();
  });
  prepare();
})();

_flutter.loader.load({config: {canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href}});
