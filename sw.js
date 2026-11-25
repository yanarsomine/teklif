/* Yanar Şömine – çevrimdışı açılış için önbellek.
   Strateji: önce ağ (her zaman en güncel sürüm), ağ yoksa önbellekteki son sürüm.
   Yalnız bu sitenin dosyaları önbelleğe alınır; Supabase (kayıtlar) hiçbir zaman önbellekten verilmez. */
const CACHE = 'ys-v2';
const SHELL = ['./', 'index.html', 'backend.js', 'config.js', 'logo.png', 'data/products.json', 'data/thumbs-idx.json',
  'vendor/fonts/IBMPlexSans-var.woff', 'vendor/fonts/Figtree-var.woff', 'manifest.webmanifest', 'apple-touch-icon.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL).catch(() => {})).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return; // Supabase, yazı tipi vb. dış istekler: tarayıcıya bırak
  e.respondWith((async () => {
    const c = await caches.open(CACHE);
    try {
      // sayfa, kod ve veri dosyaları her seferinde sunucuya sorulur (değişmediyse 304, hızlı); resimler normal önbellekle
      const fresh = req.mode === 'navigate' || /\.(html|js|json|webmanifest)$/.test(url.pathname) || url.pathname.endsWith('/');
      const res = fresh ? await fetch(req.url, { cache: 'no-cache', credentials: 'same-origin' }) : await fetch(req);
      if (res.ok && res.type === 'basic') c.put(req, res.clone()).catch(() => {});
      return res;
    } catch (err) {
      const hit = await c.match(req, { ignoreSearch: true }) || (req.mode === 'navigate' ? await c.match('index.html') : null);
      if (hit) return hit;
      throw err;
    }
  })());
});
