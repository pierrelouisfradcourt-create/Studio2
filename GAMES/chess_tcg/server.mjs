#!/usr/bin/env node
// Serveur statique minimal — sert index.html, les modules du jeu et la brique KB réutilisée
// (`/knowledge_base/systems/combat/damage_floor.mjs`, importée par engine.mjs). Sans dépendance.

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join, normalize, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');
const PORT = parseInt(process.env.CHESS_TCG_PORT || '4515', 10);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
};

function typeFor(path) {
  const dot = path.lastIndexOf('.');
  const ext = dot >= 0 ? path.slice(dot) : '';
  return MIME[ext] || 'application/octet-stream';
}

const ALLOWED_FILE = /^\/[a-zA-Z0-9_-]+\.(mjs|js|css)$/;
const ALLOWED_KB = /^\/knowledge_base\/systems\/[a-zA-Z0-9_-]+\/[a-zA-Z0-9_-]+\.mjs$/;

function routeFor(method, pathname) {
  if (method !== 'GET') return { status: 405, error: 'method not allowed' };
  if (pathname === '/' || pathname === '/index.html') {
    return { status: 200, root: __dirname, relPath: 'index.html', type: MIME['.html'] };
  }
  if (ALLOWED_FILE.test(pathname)) {
    return { status: 200, root: __dirname, relPath: pathname.slice(1), type: typeFor(pathname) };
  }
  if (ALLOWED_KB.test(pathname)) {
    return { status: 200, root: REPO_ROOT, relPath: pathname.slice(1), type: typeFor(pathname) };
  }
  return { status: 404, error: 'not found' };
}

async function serveFile(res, root, relPath, type) {
  try {
    const safe = normalize(relPath).replace(/^([.][.][/\\])+/, '');
    const buf = await readFile(join(root, safe));
    res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store' });
    res.end(buf);
  } catch {
    res.writeHead(404, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ error: 'file not found' }));
  }
}

function handleRequest(req, res) {
  return (async () => {
    try {
      const url = new URL(req.url, 'http://localhost');
      const route = routeFor(req.method, url.pathname);
      if (route.status !== 200) {
        res.writeHead(route.status, { 'Content-Type': 'application/json; charset=utf-8' });
        return res.end(JSON.stringify({ error: route.error }));
      }
      return serveFile(res, route.root, route.relPath, route.type);
    } catch (err) {
      res.writeHead(500, { 'Content-Type': 'application/json; charset=utf-8' });
      res.end(JSON.stringify({ error: 'server error', message: err.message }));
    }
  })();
}

function startServer() {
  const server = createServer(handleRequest);
  server.listen(PORT, () => {
    console.log(`interface jouable: http://localhost:${PORT}`);
  });
  process.on('SIGTERM', () => {
    server.close(() => {
      console.log('serveur arrêté');
      process.exit(0);
    });
  });
  return server;
}

if (import.meta.url === pathToFileURL(process.argv[1] || '').href) {
  startServer();
}

export { startServer, routeFor, typeFor };
