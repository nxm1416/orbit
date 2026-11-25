// Orbit のサービスワーカー：プッシュ通知の表示と、通知を押したときに Orbit を開く処理だけを行います
// （ページの保存（キャッシュ）はしないので、更新はすぐに反映されます）
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()));

self.addEventListener('push', (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { title: 'Orbit', body: e.data ? e.data.text() : '' }; }
  e.waitUntil(self.registration.showNotification(d.title || 'Orbit', {
    body: d.body || '',
    icon: '/icons/icon-192.png',
    badge: '/icons/favicon-64.png',
    tag: d.tag || undefined,
    data: { url: d.url || '/' },
  }));
});

self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || '/', self.location.origin).href;
  e.waitUntil((async () => {
    const list = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of list) {
      if (c.url.startsWith(self.location.origin)) {
        await c.focus();
        try { await c.navigate(url); } catch (_) { c.postMessage({ type: 'open', url }); }
        return;
      }
    }
    await self.clients.openWindow(url);
  })());
});
