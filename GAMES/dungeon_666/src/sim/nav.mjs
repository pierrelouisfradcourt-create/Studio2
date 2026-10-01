// Navigation : champ de distance (BFS) vers le héros sur une grille de la salle, recalculé
// quelques fois par seconde. Un ennemi sans ligne de vue suit la pente du champ et
// contourne les piliers au lieu de pousser contre eux. Déterministe, sans allocation
// par image (tableaux typés réutilisés).

const CELL = 40; // u — taille d'une case de navigation
const INFLATE = 18; // u — marge autour des obstacles (rayon moyen d'un ennemi)
const REFRESH_TICKS = 15; // le champ est recalculé 4 fois par seconde
const UNREACHED = 0x7fff;
const NEIGHBORS = [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]];

export function buildNav(room) {
  const cols = Math.ceil(room.w / CELL);
  const rows = Math.ceil(room.h / CELL);
  const blocked = new Uint8Array(cols * rows);
  for (let cy = 0; cy < rows; cy++) {
    for (let cx = 0; cx < cols; cx++) {
      const x = (cx + 0.5) * CELL;
      const y = (cy + 0.5) * CELL;
      let b = x < room.pad + INFLATE || x > room.w - room.pad - INFLATE || y < room.pad + INFLATE || y > room.h - room.pad - INFLATE;
      for (const o of room.obstacles) {
        if (x > o.x0 - INFLATE && x < o.x1 + INFLATE && y > o.y0 - INFLATE && y < o.y1 + INFLATE) b = true;
      }
      blocked[cy * cols + cx] = b ? 1 : 0;
    }
  }
  return { cols, rows, blocked, dist: new Int16Array(cols * rows).fill(UNREACHED), queue: new Int32Array(cols * rows), lastTick: -1e9 };
}

function cellOf(nav, x, y) {
  const cx = Math.min(nav.cols - 1, Math.max(0, Math.floor(x / CELL)));
  const cy = Math.min(nav.rows - 1, Math.max(0, Math.floor(y / CELL)));
  return cy * nav.cols + cx;
}

/** Recalcule le champ de distance depuis la case du héros (BFS 8-connexe). */
export function updateNav(game) {
  const nav = game.room.nav;
  if (!nav || game.tick - nav.lastTick < REFRESH_TICKS) return;
  nav.lastTick = game.tick;
  const { cols, rows, blocked, dist, queue } = nav;
  dist.fill(UNREACHED);
  const start = cellOf(nav, game.player.x, game.player.y);
  let head = 0;
  let tail = 0;
  dist[start] = 0;
  queue[tail++] = start;
  while (head < tail) {
    const c = queue[head++];
    const cx = c % cols;
    const cy = (c - cx) / cols;
    for (const [dx, dy] of NEIGHBORS) {
      const nx = cx + dx;
      const ny = cy + dy;
      if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) continue;
      const n = ny * cols + nx;
      if (blocked[n] || dist[n] !== UNREACHED) continue;
      // Pas de coupe de coin entre deux cases bloquées.
      if (dx !== 0 && dy !== 0 && (blocked[cy * cols + nx] || blocked[ny * cols + cx])) continue;
      dist[n] = dist[c] + 1;
      queue[tail++] = n;
    }
  }
}

/**
 * Direction (unitaire, écrite dans out) vers la case voisine la plus proche du héros.
 * Rend false si aucune pente utilisable (on garde alors la poursuite directe).
 */
export function navDirection(game, x, y, out) {
  const nav = game.room.nav;
  if (!nav) return false;
  const { cols, rows, dist, blocked } = nav;
  const c = cellOf(nav, x, y);
  const cx = c % cols;
  const cy = (c - cx) / cols;
  let best = dist[c];
  let bx = -1;
  let by = -1;
  for (const [dx, dy] of NEIGHBORS) {
    const nx = cx + dx;
    const ny = cy + dy;
    if (nx < 0 || ny < 0 || nx >= cols || ny >= rows) continue;
    const n = ny * cols + nx;
    if (blocked[n] || dist[n] >= best) continue;
    if (dx !== 0 && dy !== 0 && (blocked[cy * cols + nx] || blocked[ny * cols + cx])) continue;
    best = dist[n];
    bx = nx;
    by = ny;
  }
  if (bx < 0) return false;
  const tx = (bx + 0.5) * CELL - x;
  const ty = (by + 0.5) * CELL - y;
  const l = Math.sqrt(tx * tx + ty * ty) || 1;
  out.x = tx / l;
  out.y = ty / l;
  return true;
}
