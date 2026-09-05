// server.mjs -- static file server for the Survival Arena UI. No game logic here.
// Usage: node server.mjs   (respects ARENA_PORT env var, defaults to 5183)

import http from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.ARENA_PORT) || 5183;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
};

const ALLOWED = new Set(['/index.html', '/game.mjs', '/render.mjs', '/input.mjs']);

const server = http.createServer(async (req, res) => {
  try {
    let reqPath = req.url === '/' ? '/index.html' : req.url.split('?')[0];

    if (!ALLOWED.has(reqPath)) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Not found');
      return;
    }

    const filePath = path.join(__dirname, reqPath);
    const ext = path.extname(filePath);
    const body = await readFile(filePath);

    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(body);
  } catch (err) {
    res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Erreur serveur: ' + err.message);
  }
});

server.listen(PORT, () => {
  console.log(`Survival Arena -- interface jouable sur http://localhost:${PORT}`);
});
