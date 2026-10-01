#!/usr/bin/env node
// Serveur statique minimal de Dungeon 666 — aucune dépendance.
// Écoute sur toutes les interfaces : un téléphone sur le même Wi-Fi peut jouer via
// l'adresse LAN affichée au démarrage.
//
// Usage : node server.mjs          (port DUNGEON_666_PORT, 4666 par défaut)

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { networkInterfaces } from 'node:os';
import { fileURLToPath } from 'node:url';
import { dirname, join, normalize, sep } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PORT = Number.parseInt(process.env.DUNGEON_666_PORT ?? '4666', 10);
const HOST = process.env.DUNGEON_666_HOST ?? '0.0.0.0';

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.webmanifest': 'application/manifest+json',
};

// Seuls l'index et les fichiers sous src/ ou dist/ sont servis : jamais les tests, outils,
// ni rien au-dessus du dossier du jeu.
const SERVED = /^\/(?:index\.html|(?:src|dist)\/[a-zA-Z0-9_\-/]+\.(?:mjs|js|css|json|svg|png|html|webmanifest))$/;

function extOf(path) {
  const dot = path.lastIndexOf('.');
  return dot >= 0 ? path.slice(dot) : '';
}

function routeFor(method, pathname) {
  if (method !== 'GET' && method !== 'HEAD') return { status: 405 };
  const p = pathname === '/' ? '/index.html' : pathname;
  if (!SERVED.test(p) || p.includes('..')) return { status: 404 };
  const abs = normalize(join(__dirname, p));
  if (!abs.startsWith(__dirname + sep)) return { status: 404 };
  return { status: 200, abs, type: MIME[extOf(p)] ?? 'application/octet-stream' };
}

function lanAddresses() {
  const out = [];
  for (const list of Object.values(networkInterfaces())) {
    for (const a of list ?? []) {
      if (a.family === 'IPv4' && !a.internal) out.push(a.address);
    }
  }
  return out;
}

const server = createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', 'http://localhost');
  const route = routeFor(req.method ?? 'GET', url.pathname);
  if (route.status !== 200) {
    res.writeHead(route.status, { 'content-type': 'text/plain; charset=utf-8' });
    res.end(route.status === 405 ? 'méthode non autorisée' : 'introuvable');
    return;
  }
  try {
    const body = await readFile(route.abs);
    res.writeHead(200, { 'content-type': route.type, 'cache-control': 'no-store' });
    res.end(req.method === 'HEAD' ? undefined : body);
  } catch {
    res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
    res.end('introuvable');
  }
});

server.listen(PORT, HOST, () => {
  console.log(`Dungeon 666 — interface jouable sur http://localhost:${PORT}/`);
  for (const ip of lanAddresses()) console.log(`  depuis un téléphone (même Wi-Fi) : http://${ip}:${PORT}/`);
});
