// server.mjs — UI only: tiny static file server for index.html + the game modules.
// No game rules here. Port via RUNNER_PORT (default 8080).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.RUNNER_PORT) || 8080;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
};

function safeJoin(root, urlPath) {
  const decoded = decodeURIComponent(urlPath.split('?')[0]);
  const resolved = path.normalize(path.join(root, decoded));
  if (!resolved.startsWith(path.normalize(root))) return null; // path traversal guard
  return resolved;
}

const server = http.createServer((req, res) => {
  try {
    let reqPath = req.url === '/' ? '/index.html' : req.url;
    const filePath = safeJoin(dir, reqPath);
    if (!filePath) {
      res.writeHead(400).end('Bad request');
      return;
    }
    fs.readFile(filePath, (err, data) => {
      if (err) {
        res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Not found');
        return;
      }
      const ext = path.extname(filePath);
      res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
      res.end(data);
    });
  } catch (e) {
    res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' }).end('Internal error');
  }
});

server.on('error', (err) => {
  console.error(`server.mjs: failed to start on port ${PORT}: ${err.message}`);
  process.exit(1);
});

server.listen(PORT, () => {
  console.log(`interface jouable: http://localhost:${PORT}/`);
});
