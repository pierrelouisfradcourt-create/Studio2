#!/usr/bin/env node
// Minimal static server for v2_breakout_slice game
// Serves index.html + .mjs modules, no dependencies

import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join, normalize } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PORT = parseInt(process.env.V2_BREAKOUT_SLICE_PORT || '4505', 10);

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

function routeFor(method, pathname) {
  if (method !== 'GET') {
    return { status: 405, error: 'method not allowed' };
  }
  if (pathname === '/' || pathname === '/index.html') {
    return { status: 200, relPath: 'index.html', type: MIME['.html'] };
  }
  if (ALLOWED_FILE.test(pathname)) {
    return { status: 200, relPath: pathname.slice(1), type: typeFor(pathname) };
  }
  return { status: 404, error: 'not found' };
}

async function serveFile(res, relPath, type) {
  try {
    const safe = normalize(relPath).replace(/^([.][.][/\\])+/, '');
    const buf = await readFile(join(__dirname, safe));
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
      if (route.status === 405 || route.status === 404) {
        res.writeHead(route.status, { 'Content-Type': 'application/json; charset=utf-8' });
        return res.end(JSON.stringify({ error: route.error }));
      }
      return serveFile(res, route.relPath, route.type);
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
