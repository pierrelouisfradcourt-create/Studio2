// Visée assistée — décisive sur mobile : un tap sur « attaque » vise l'ennemi le plus
// pertinent (proche ET dans la direction où l'on se déplace). La visée manuelle (souris,
// joystick d'attaque glissé) l'emporte toujours.

import { DEG } from './config.mjs';
import { lineOfSight } from './physics.mjs';

const STICKY_TIME = 0.4; // s : la cible précédente reste privilégiée (pas de saut de cible)
const STICKY_BONUS = 60; // u retirés au score de la cible précédente
const THREAT_BONUS = 40; // u retirés à un ennemi qui prépare une attaque
const ELITE_BONUS = 25;

const out = { x: 0, y: -1, targetId: 0, targetDist: 0 };

/**
 * Rend un objet PARTAGÉ {x, y, targetId, targetDist} : direction unitaire de visée.
 * `manualX/manualY` : visée explicite (0, 0 = aucune).
 */
export function computeAim(game, manualX, manualY) {
  const p = game.player;
  const a = game.tuning.autoAim;
  out.targetId = 0;
  out.targetDist = 0;
  const ml = Math.sqrt(manualX * manualX + manualY * manualY);
  if (ml > 0.15) {
    out.x = manualX / ml;
    out.y = manualY / ml;
    return out;
  }
  // Direction de préférence : le mouvement en cours, sinon l'orientation.
  let px = p.moveX;
  let py = p.moveY;
  const pl = Math.sqrt(px * px + py * py);
  if (pl > 0.2) {
    px /= pl;
    py /= pl;
  } else {
    px = Math.cos(p.facing);
    py = Math.sin(p.facing);
  }
  const cosCone = Math.cos((a.coneDeg / 2) * DEG);
  let best = null;
  let bestScore = Infinity;
  let bestD = 0;
  const sticky = game.time - (p.lastTargetAt ?? -99) < STICKY_TIME ? p.lastTargetId : 0;
  for (const e of game.enemies) {
    if (e.dead || e.spawnT > 0) continue;
    const dx = e.x - p.x;
    const dy = e.y - p.y;
    const d = Math.sqrt(dx * dx + dy * dy);
    const reach = a.range + e.r;
    if (d > reach) continue;
    // Jamais à travers un pilier : on ne vise que ce qu'on peut atteindre.
    if (!lineOfSight(game.room, p.x, p.y, e.x, e.y)) continue;
    const c = d > 1e-6 ? (dx * px + dy * py) / d : 1;
    // Hors du cône préféré : pénalité, mais pas exclusion (on vise quand même si seul).
    const anglePenalty = 1 + a.movePreference * (1 - c) + (c < cosCone ? 0.6 : 0);
    let score = (d - e.r) * anglePenalty;
    if (e.id === sticky) score -= STICKY_BONUS;
    if (e.state === 'windup') score -= THREAT_BONUS;
    if (e.eliteMod) score -= ELITE_BONUS;
    if (score < bestScore) {
      bestScore = score;
      best = e;
      bestD = d;
    }
  }
  if (best) {
    const dx = best.x - p.x;
    const dy = best.y - p.y;
    const d = Math.max(1e-6, bestD);
    out.x = dx / d;
    out.y = dy / d;
    out.targetId = best.id;
    out.targetDist = bestD;
    return out;
  }
  out.x = px;
  out.y = py;
  return out;
}
