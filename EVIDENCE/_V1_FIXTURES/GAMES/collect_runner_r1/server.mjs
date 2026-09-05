// server.mjs — minimal static file server for Collect Runner. UI plumbing
// only: no game rules live here. Serves index.html, game.mjs, render.mjs,
// input.mjs from this directory. Port configurable via RUNNER_PORT env var.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
};

const port = Number.parseInt(process.env.RUNNER_PORT, 10) || 4321;

const server = http.createServer((req, res) => {
  try {
    let reqPath = decodeURIComponent(new URL(req.url, `http://localhost:${port}`).pathname);
    if (reqPath === '/') reqPath = '/index.html';

    // Guard against path traversal — never serve outside this directory.
    const resolved = path.normalize(path.join(__dirname, reqPath));
    if (!resolved.startsWith(__dirname)) {
      res.writeHead(403, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Forbidden');
      return;
    }

    fs.readFile(resolved, (err, data) => {
      if (err) {
        res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
        res.end('Not found');
        return;
      }
      const ext = path.extname(resolved);
      res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
      res.end(data);
    });
  } catch (err) {
    console.error('[collect-runner server] request error', err);
    res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('Internal server error');
  }
});

server.on('error', (err) => {
  console.error('[collect-runner server] failed to start:', err.message);
  process.exit(1);
});

server.listen(port, () => {
  console.log(`interface jouable: http://localhost:${port}/`);
});
