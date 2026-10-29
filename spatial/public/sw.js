// Offline cache for the static spatial app. Hashed assets are cache-first;
// navigations and library JSON stay network-first so exports never go stale.
const CACHE = 'mindme-spatial-v2';

const isHashedAsset = (url) =>
  /\/assets\//.test(url.pathname) || /\.(?:png|jpe?g|svg|ico|webp|woff2?|css|js|webmanifest)$/i.test(url.pathname);

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      const cached = await cache.match(request);

      if (isHashedAsset(url) && cached) return cached;

      try {
        const response = await fetch(request);
        if (response.ok) cache.put(request, response.clone());
        return response;
      } catch {
        if (cached) return cached;
        throw new Error('offline and not cached');
      }
    })(),
  );
});
