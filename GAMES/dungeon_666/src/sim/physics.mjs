// Déplacement d'un cercle dans la salle : murs extérieurs + obstacles rectangulaires.
// Sous-pas automatiques pour les objets rapides (dash, charge) : jamais de traversée de mur.

import { pushCircleOutOfRect } from '../core/math.mjs';

const scratch = { x: 0, y: 0, nx: 0, ny: 0 };
const result = { hitWall: false, nx: 0, ny: 0 };

/** Bornes jouables (intérieur des murs). */
export function roomBounds(room) {
  return { x0: room.pad, y0: room.pad, x1: room.w - room.pad, y1: room.h - room.pad };
}

function resolve(room, ent) {
  let hit = false;
  const x0 = room.pad + ent.r;
  const y0 = room.pad + ent.r;
  const x1 = room.w - room.pad - ent.r;
  const y1 = room.h - room.pad - ent.r;
  if (ent.x < x0) { ent.x = x0; result.nx = 1; result.ny = 0; hit = true; }
  if (ent.x > x1) { ent.x = x1; result.nx = -1; result.ny = 0; hit = true; }
  if (ent.y < y0) { ent.y = y0; result.ny = 1; result.nx = 0; hit = true; }
  if (ent.y > y1) { ent.y = y1; result.ny = -1; result.nx = 0; hit = true; }
  for (const o of room.obstacles) {
    if (pushCircleOutOfRect(scratch, ent.x, ent.y, ent.r, o.x0, o.y0, o.x1, o.y1)) {
      ent.x = scratch.x;
      ent.y = scratch.y;
      result.nx = scratch.nx;
      result.ny = scratch.ny;
      hit = true;
    }
  }
  return hit;
}

/**
 * Déplace `ent` ({x, y, r}) de (dx, dy) avec collisions. Rend un objet PARTAGÉ (ne pas le
 * conserver) : {hitWall, nx, ny} — la normale du dernier contact.
 */
export function moveCircle(room, ent, dx, dy) {
  result.hitWall = false;
  result.nx = 0;
  result.ny = 0;
  const distance = Math.sqrt(dx * dx + dy * dy);
  const steps = Math.max(1, Math.ceil(distance / Math.max(4, ent.r * 0.75)));
  const sx = dx / steps;
  const sy = dy / steps;
  for (let i = 0; i < steps; i++) {
    ent.x += sx;
    ent.y += sy;
    if (resolve(room, ent)) result.hitWall = true;
  }
  return result;
}

/** Vrai si le point est dans un obstacle ou hors des murs (avec marge `r`). */
export function pointBlocked(room, x, y, r) {
  if (x < room.pad + r || x > room.w - room.pad - r || y < room.pad + r || y > room.h - room.pad - r) return true;
  for (const o of room.obstacles) {
    if (x > o.x0 - r && x < o.x1 + r && y > o.y0 - r && y < o.y1 + r) return true;
  }
  return false;
}

/** Ligne de vue entre deux points (les obstacles bloquent). Échantillonnage, suffisant ici. */
export function lineOfSight(room, ax, ay, bx, by) {
  const dx = bx - ax;
  const dy = by - ay;
  const d = Math.sqrt(dx * dx + dy * dy);
  const steps = Math.ceil(d / 16);
  for (let i = 1; i < steps; i++) {
    const t = i / steps;
    const x = ax + dx * t;
    const y = ay + dy * t;
    for (const o of room.obstacles) {
      if (x > o.x0 && x < o.x1 && y > o.y0 && y < o.y1) return false;
    }
  }
  return true;
}
