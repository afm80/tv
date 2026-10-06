const CACHE_PREFIX = 'alfaham-tv-cache-';
const CACHE_NAME = `${CACHE_PREFIX}v9`;
const ASSETS = ['./', './index.html', './admin.html', './manifest.json', './icon-192.png', './icon-512.png', './icon-1024.png'];

self.addEventListener('install', event => {
    event.waitUntil(
        caches.open(CACHE_NAME)
            .then(cache => cache.addAll(ASSETS))
            .then(() => self.skipWaiting())
    );
});

self.addEventListener('activate', event => {
    event.waitUntil(
        caches.keys().then(keys =>
            Promise.all(keys
                .filter(key => key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME)
                .map(key => caches.delete(key)))
        ).then(() => self.clients.claim())
    );
});

self.addEventListener('fetch', event => {
    if (event.request.method !== 'GET') return;
    const requestUrl = new URL(event.request.url);
    if (requestUrl.origin !== self.location.origin) return;

    const isPageOrManifest = event.request.mode === 'navigate' || /\.(html|json)$/i.test(requestUrl.pathname);
    if (isPageOrManifest) {
        event.respondWith(
            fetch(event.request, { cache: 'no-cache' })
                .then(response => {
                    if (response && response.status === 200) {
                        const copy = response.clone();
                        caches.open(CACHE_NAME).then(cache => cache.put(event.request, copy));
                    }
                    return response;
                })
                .catch(() => caches.match(event.request).then(cached => {
                    if (cached) return cached;
                    if (event.request.mode === 'navigate') return caches.match('./index.html');
                    return Response.error();
                }))
        );
        return;
    }

    event.respondWith(
        caches.match(event.request).then(cached => {
            if (cached) return cached;
            return fetch(event.request).then(response => {
                if (!response || response.status !== 200 || response.type !== 'basic') return response;
                const clone = response.clone();
                caches.open(CACHE_NAME).then(cache => cache.put(event.request, clone));
                return response;
            }).catch(() => {
                if (event.request.mode === 'navigate') return caches.match('./index.html');
                throw new Error('Network request failed');
            });
        })
    );
});