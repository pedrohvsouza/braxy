// Braxy service worker: Web Push with Braxy closed.
//
// Pushes carry no payload. On each one the worker fetches what to show from
// /api/push/latest (same origin, so the session cookie goes along).

self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));

self.addEventListener("push", (event) => {
  event.waitUntil(
    (async () => {
      let content = null;
      try {
        const res = await fetch("/api/push/latest", { credentials: "same-origin", headers: { Accept: "application/json" } });
        if (res.ok) content = (await res.json()).content;
      } catch {
        // Offline or signed out: fall back to a generic notice below.
      }
      await self.registration.showNotification(content?.title ?? "Braxy", {
        body: content?.body ?? "Você tem novidades no Braxy.",
        icon: "/braxy-logo.png",
        badge: "/braxy-logo.png",
        tag: content?.tag ?? "braxy",
        data: { url: content?.url ?? "/" },
      });
    })(),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const url = new URL(event.notification.data?.url ?? "/", self.location.origin).href;
  event.waitUntil(
    (async () => {
      const tabs = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
      for (const tab of tabs) {
        if (new URL(tab.url).origin !== self.location.origin) continue;
        await tab.focus();
        if ("navigate" in tab) await tab.navigate(url);
        return;
      }
      await self.clients.openWindow(url);
    })(),
  );
});
