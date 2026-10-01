// Utilitaires géométriques SANS allocation dans les chemins chauds : les fonctions
// travaillent sur des nombres, ou écrivent dans un objet `out` fourni par l'appelant.

export const TAU = Math.PI * 2;
const EPS = 1e-9;

export function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

export function lerp(a, b, t) {
  return a + (b - a) * t;
}

export function len(x, y) {
  return Math.sqrt(x * x + y * y);
}

export function dist(ax, ay, bx, by) {
  const dx = bx - ax;
  const dy = by - ay;
  return Math.sqrt(dx * dx + dy * dy);
}

export function dist2(ax, ay, bx, by) {
  const dx = bx - ax;
  const dy = by - ay;
  return dx * dx + dy * dy;
}

/** Normalise (x, y) dans out ; vecteur nul -> (0, 0). Rend la longueur d'origine. */
export function normalizeInto(out, x, y) {
  const l = Math.sqrt(x * x + y * y);
  if (l < EPS) {
    out.x = 0;
    out.y = 0;
    return 0;
  }
  out.x = x / l;
  out.y = y / l;
  return l;
}

/** Rapproche v de target d'au plus maxDelta. */
export function approach(v, target, maxDelta) {
  if (v < target) return Math.min(v + maxDelta, target);
  return Math.max(v - maxDelta, target);
}

/** Différence d'angle signée dans (-PI, PI]. */
export function angleDiff(a, b) {
  let d = (b - a) % TAU;
  if (d > Math.PI) d -= TAU;
  if (d <= -Math.PI) d += TAU;
  return d;
}

/** Vrai si le point (px, py) est dans le secteur circulaire centré en (cx, cy), de rayon r
 *  (agrandi de `pad`, typiquement le rayon de la cible), orienté `dir`, d'ouverture totale `arc`. */
export function inSector(px, py, cx, cy, r, dir, arc, pad = 0) {
  const dx = px - cx;
  const dy = py - cy;
  const d = Math.sqrt(dx * dx + dy * dy);
  if (d > r + pad) return false;
  if (d <= pad) return true; // cible qui chevauche l'origine : toujours touchée
  const half = arc / 2;
  if (half >= Math.PI) return true;
  const diff = Math.abs(angleDiff(dir, Math.atan2(dy, dx)));
  // Tolérance angulaire liée au rayon de la cible : un gros ennemi au bord de l'arc est touché.
  const slack = Math.asin(clamp(pad / d, 0, 1));
  return diff <= half + slack;
}

export function circlesOverlap(ax, ay, ar, bx, by, br) {
  const r = ar + br;
  return dist2(ax, ay, bx, by) < r * r;
}

/** Distance au carré d'un point à un segment [a, b]. */
export function pointSegDist2(px, py, ax, ay, bx, by) {
  const abx = bx - ax;
  const aby = by - ay;
  const l2 = abx * abx + aby * aby;
  let t = l2 > EPS ? ((px - ax) * abx + (py - ay) * aby) / l2 : 0;
  t = clamp(t, 0, 1);
  const qx = ax + abx * t;
  const qy = ay + aby * t;
  return dist2(px, py, qx, qy);
}

/** Point de l'AABB [x0,y0,x1,y1] le plus proche de (px, py), écrit dans out. */
export function closestOnRect(out, px, py, x0, y0, x1, y1) {
  out.x = clamp(px, x0, x1);
  out.y = clamp(py, y0, y1);
  return out;
}

/** Repousse un cercle hors d'un AABB. Rend true s'il y avait chevauchement ; out = nouvelle
 *  position du centre, nx/ny = normale de sortie. */
export function pushCircleOutOfRect(out, cx, cy, r, x0, y0, x1, y1) {
  const qx = clamp(cx, x0, x1);
  const qy = clamp(cy, y0, y1);
  const dx = cx - qx;
  const dy = cy - qy;
  const d2 = dx * dx + dy * dy;
  if (d2 >= r * r) return false;
  if (d2 > EPS) {
    const d = Math.sqrt(d2);
    out.nx = dx / d;
    out.ny = dy / d;
    out.x = qx + out.nx * r;
    out.y = qy + out.ny * r;
    return true;
  }
  // Centre à l'intérieur du rectangle : sortie par le bord le plus proche.
  const left = cx - x0;
  const right = x1 - cx;
  const top = cy - y0;
  const bottom = y1 - cy;
  const m = Math.min(left, right, top, bottom);
  out.nx = 0;
  out.ny = 0;
  out.x = cx;
  out.y = cy;
  if (m === left) { out.nx = -1; out.x = x0 - r; }
  else if (m === right) { out.nx = 1; out.x = x1 + r; }
  else if (m === top) { out.ny = -1; out.y = y0 - r; }
  else { out.ny = 1; out.y = y1 + r; }
  return true;
}

/** Repousse un cercle hors d'un autre cercle (obstacle fixe). */
export function pushCircleOutOfCircle(out, cx, cy, r, ox, oy, or) {
  const dx = cx - ox;
  const dy = cy - oy;
  const rr = r + or;
  const d2 = dx * dx + dy * dy;
  if (d2 >= rr * rr) return false;
  const d = Math.sqrt(d2);
  if (d < EPS) {
    out.nx = 1;
    out.ny = 0;
  } else {
    out.nx = dx / d;
    out.ny = dy / d;
  }
  out.x = ox + out.nx * rr;
  out.y = oy + out.ny * rr;
  return true;
}

/** Courbes d'interpolation usuelles pour le juice. */
export function easeOutCubic(t) {
  const u = 1 - t;
  return 1 - u * u * u;
}

export function easeInQuad(t) {
  return t * t;
}
