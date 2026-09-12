// Nessuna cache: l'app richiede sempre la rete per leggere le lezioni da Supabase.
// Il service worker esiste solo per soddisfare i criteri di installabilità PWA.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", (event) => {
  event.respondWith(fetch(event.request));
});
