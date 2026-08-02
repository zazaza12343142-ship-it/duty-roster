const CACHE_NAME = "duty-roster-v2";
const APP_SHELL = ["./icon-192.png", "./icon-512.png"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(APP_SHELL)));
  self.skipWaiting();
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k))))
  );
  self.clients.claim();
});

self.addEventListener("message", (e) => {
  if (e.data === "SKIP_WAITING") self.skipWaiting();
});

self.addEventListener("fetch", (e) => {
  if (e.request.method !== "GET") return;

  // صفحات التنقّل (index.html وأي فتح للتطبيق) — شبكة فقط، بدون أي كاش إطلاقًا
  // هيك أي تحديث نرفعه عالسيرفر بيوصل فورًا بدون ما يعلق على نسخة قديمة محفوظة.
  if (e.request.mode === "navigate") {
    e.respondWith(
      fetch(e.request, { cache: "no-store" }).catch(() => caches.match("./index.html"))
    );
    return;
  }

  // الملفات الثابتة (أيقونات فقط) — كاش مع تحديث بالخلفية
  e.respondWith(
    fetch(e.request, { cache: "no-store" })
      .then((res) => {
        const resClone = res.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(e.request, resClone));
        return res;
      })
      .catch(() => caches.match(e.request))
  );
});

self.addEventListener("push", (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = { title: "🚨 رسالة طارئة", body: event.data ? event.data.text() : "" }; }
  const title = data.title || "🚨 رسالة طارئة";
  const options = {
    body: data.body || "",
    icon: "./icon-192.png",
    badge: "./icon-192.png",
    vibrate: [200, 100, 200, 100, 200],
    requireInteraction: true,
    data: { url: data.url || "./?checkin=1" },
  };
  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const targetUrl = (event.notification.data && event.notification.data.url) || "./?checkin=1";
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ("focus" in client) return client.focus();
      }
      if (clients.openWindow) return clients.openWindow(targetUrl);
    })
  );
});
