"use strict";
const CACHE_NAME = "playam-shell-v2";
const APP_SHELL = [
  "./",
  "./index.html",
  "./site/game.html",
  "./manifest.webmanifest",
  "./assets/playam-icon.svg"
];

self.addEventListener("install", event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(APP_SHELL);
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", event => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter(name => name.startsWith("playam-shell-") && name !== CACHE_NAME).map(name => caches.delete(name)));
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== "GET" || url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith((async () => {
      try {
        const response = await fetch(request);
        if (response && response.ok) {
          const cache = await caches.open(CACHE_NAME);
          const key = url.pathname.endsWith("/game.html") ? "./site/game.html" : "./index.html";
          await cache.put(key, response.clone());
        }
        return response;
      } catch (_) {
        const cache = await caches.open(CACHE_NAME);
        const key = url.pathname.endsWith("/game.html") ? "./site/game.html" : "./index.html";
        return (await cache.match(key)) || (await cache.match("./index.html")) || Response.error();
      }
    })());
    return;
  }

  if (url.pathname.endsWith("/manifest.webmanifest") || url.pathname.endsWith("/assets/playam-icon.svg")) {
    event.respondWith((async () => (await caches.match(request)) || fetch(request))());
  }
});
