// sys-reachability — BFS d'atteignabilité sur grille, PUR et déterministe.
// Réécriture propre inspirée du pattern cité pat-full-reachability (SPD, GPL — concept only).
// Aucun code SPD repris. Licence : MIT (interne).
//
// Représentation grille : tableau de lignes de cellules ; une cellule est "bloquée" si
// isBlocked(cell) est vrai. Coordonnées {x: colonne, y: ligne}. Voisinage 4-connexe.

/**
 * Ensemble des cases atteignables depuis `start` en évitant les cases bloquées.
 * @param {Array<Array<any>>} grid
 * @param {{x:number,y:number}} start
 * @param {(cell:any)=>boolean} isBlocked
 * @returns {Set<string>} clés "x,y" atteignables (start inclus s'il est libre)
 */
export function reachableCells(grid, start, isBlocked) {
  const h = grid.length;
  const w = h > 0 ? grid[0].length : 0;
  const key = (x, y) => `${x},${y}`;
  const inBounds = (x, y) => x >= 0 && y >= 0 && x < w && y < h;
  const seen = new Set();
  if (!inBounds(start.x, start.y) || isBlocked(grid[start.y][start.x])) return seen;
  // File FIFO déterministe (ordre d'insertion), voisins dans un ordre fixe.
  const queue = [start];
  seen.add(key(start.x, start.y));
  const NEIGHBORS = [[0, -1], [1, 0], [0, 1], [-1, 0]];
  while (queue.length > 0) {
    const { x, y } = queue.shift();
    for (const [dx, dy] of NEIGHBORS) {
      const nx = x + dx, ny = y + dy;
      if (!inBounds(nx, ny)) continue;
      const k = key(nx, ny);
      if (seen.has(k) || isBlocked(grid[ny][nx])) continue;
      seen.add(k);
      queue.push({ x: nx, y: ny });
    }
  }
  return seen;
}

/**
 * Le niveau est-il atteignable ? Toutes les cases `goals` requises sont-elles joignables ?
 * @returns {{ok:boolean, unreachable:Array<{x:number,y:number}>}}
 */
export function isLevelReachable(grid, start, goals, isBlocked) {
  const reach = reachableCells(grid, start, isBlocked);
  const unreachable = goals.filter((g) => !reach.has(`${g.x},${g.y}`));
  return { ok: unreachable.length === 0, unreachable };
}
