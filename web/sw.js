/* Ghani Group — Service Worker
 * - واجهة التطبيق (HTML/CSS/JS/الشعار): تُحفظ وتعمل بدون إنترنت
 * - الصور: من الكاش أولاً (سريعة)
 * - بيانات API (GET): من الشبكة أولاً، ومن الكاش عند انقطاع الإنترنت
 * - الطلبات وتسجيل الدخول (POST...): من الشبكة دائماً
 */
const VERSION = 'gg-1.2.3';
const SHELL = ['./', 'assets/app.css?v=1.2.3', 'assets/app.js?v=1.2.3', 'assets/brand/mark.png', 'assets/brand/icon-192.png', 'manifest.webmanifest'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION + '-shell').then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => !k.startsWith(VERSION)).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

async function networkFirst(req, cacheName) {
  const cache = await caches.open(cacheName);
  try {
    const res = await fetch(req);
    if (res.ok) cache.put(req, res.clone());
    return res;
  } catch (err) {
    const hit = await cache.match(req);
    if (hit) return hit;
    throw err;
  }
}

async function cacheFirst(req, cacheName) {
  const cache = await caches.open(cacheName);
  const hit = await cache.match(req);
  if (hit) return hit;
  const res = await fetch(req);
  if (res.ok) cache.put(req, res.clone());
  return res;
}

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;               // الخطوط وغيرها
  if (url.pathname.includes('/admin') || url.pathname.includes('/install')) return;
  if (/\/api\/v1\/(auth|me|orders|notifications)/.test(url.pathname)) return; // بيانات الحساب والإشعارات لا تُحفظ

  if (req.mode === 'navigate') {
    e.respondWith(networkFirst(req, VERSION + '-shell').catch(() => caches.match('./')));
  } else if (url.pathname.includes('/api/v1/')) {
    e.respondWith(networkFirst(req, VERSION + '-api'));
  } else if (url.pathname.includes('/uploads/')) {
    e.respondWith(cacheFirst(req, VERSION + '-img'));
  } else if (url.pathname.includes('/assets/')) {
    e.respondWith(cacheFirst(req, VERSION + '-shell'));
  }
});
