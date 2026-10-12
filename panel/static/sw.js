const CACHE = "mc-panel-v1";
self.addEventListener("install", e => { self.skipWaiting(); });
self.addEventListener("activate", e => { e.waitUntil(self.clients.claim()); });
self.addEventListener("fetch", e => {
  if (e.request.method !== "GET") return;
  e.respondWith(
    fetch(e.request).then(r => {
      const c = r.clone();
      caches.open(CACHE).then(c2 => c2.put(e.request, c)).catch(() => {});
      return r;
    }).catch(() => caches.match(e.request))
  );
});
