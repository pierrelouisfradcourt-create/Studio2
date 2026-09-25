// Géométrie de l'écran — PURE. Partagée par render.mjs (dessin) et main.mjs (clics → cases),
// sans qu'input.mjs dépende du rendu (architecture_contract).

export const CANVAS_W = 960;
export const CANVAS_H = 720;

export const BOARD = Object.freeze({ x: 24, y: 56, cell: 62, cols: 7, rows: 8 });
export const HAND = Object.freeze({ x: 24, y: 582, w: 118, h: 124, gap: 6, max: 7 });
export const PANEL = Object.freeze({ x: 480, y: 56, w: 456, h: 496 });

export function cellRect(x, y) {
  return { x: BOARD.x + x * BOARD.cell, y: BOARD.y + y * BOARD.cell, w: BOARD.cell, h: BOARD.cell };
}

export function cellCenter(x, y) {
  const r = cellRect(x, y);
  return { x: r.x + r.w / 2, y: r.y + r.h / 2 };
}

/** Case du plateau sous un point canvas, ou null. */
export function cellAt(px, py) {
  const x = Math.floor((px - BOARD.x) / BOARD.cell);
  const y = Math.floor((py - BOARD.y) / BOARD.cell);
  if (px < BOARD.x || py < BOARD.y || x < 0 || y < 0 || x >= BOARD.cols || y >= BOARD.rows) return null;
  return { x, y };
}

export function handRect(index) {
  return { x: HAND.x + index * (HAND.w + HAND.gap), y: HAND.y, w: HAND.w, h: HAND.h };
}

/** Index de carte en main sous un point canvas, ou null. */
export function handIndexAt(px, py) {
  if (py < HAND.y || py >= HAND.y + HAND.h) return null;
  for (let i = 0; i < HAND.max; i++) {
    const r = handRect(i);
    if (px >= r.x && px < r.x + r.w) return i;
  }
  return null;
}
