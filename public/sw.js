/*
 * BAPBAP Modding — hand-written app-shell service worker (no dependencies).
 * Registered in production only (see src/main.tsx). Bump CACHE whenever a
 * precached file changes shape (e.g. new favicon or manifest fields).
 */
const CACHE = 'bapbap-v1'
const PRECACHE = ['./', './index.html', './favicon.svg', './manifest.webmanifest']

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((cache) => cache.addAll(PRECACHE)))
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))),
      )
      .then(() => self.clients.claim()),
  )
})

/** Network-first for navigations: fresh HTML when online, app shell offline. */
function handleNavigate(request) {
  return fetch(request)
    .then((response) => {
      const copy = response.clone()
      caches.open(CACHE).then((cache) => cache.put('./index.html', copy))
      return response
    })
    .catch(() => caches.match('./index.html'))
}

/** Cache-first with background put — for immutable/content-hashed resources. */
function handleCacheFirst(request) {
  return caches.match(request).then(
    (cached) =>
      cached ||
      fetch(request).then((response) => {
        if (response.ok) {
          const copy = response.clone()
          caches.open(CACHE).then((cache) => cache.put(request, copy))
        }
        return response
      }),
  )
}

self.addEventListener('fetch', (event) => {
  const { request } = event
  if (request.method !== 'GET') return

  if (request.mode === 'navigate') {
    event.respondWith(handleNavigate(request))
    return
  }

  const url = new URL(request.url)
  const sameOriginAsset =
    url.origin === self.location.origin && url.pathname.startsWith('/assets/')
  const fontHost =
    url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com'

  if (sameOriginAsset || fontHost) {
    event.respondWith(handleCacheFirst(request))
  }
  // Everything else (mod thumbnails on raw.githubusercontent.com,
  // img.youtube.com, …) passes through untouched — never cached.
})
