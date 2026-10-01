// Briques communes des kits (armes à distance, compétences, gadgets, Supers autres que le kit
// d'origine) : registre des tirs et zones du héros, dégâts de zone, point de lancer, traction.
//
// Les tirs et zones du héros vivent DANS LA SALLE (game.room.kitFx) : un nouvel étage construit
// une nouvelle salle, et efface donc d'office tout ce que le héros y avait posé. Données pures
// (structuredClone / JSON) ; le code qui les joue est choisi par `kind` (kit_shots, kit_zones).
// Aucune dépendance vers player.mjs (pas d'import circulaire).

import * as TRIG from '../core/trig.mjs'; // sinus, cosinus… déterministes : jamais Math.sin & co dans la simulation
import { dist2, inSector } from '../core/math.mjs';
import { DT } from './config.mjs';
import { damageEnemy } from './combat.mjs';
import { pointBlocked } from './physics.mjs';
import { emit } from './state.mjs';

const THROW_STEP = 8; // u : pas de recul d'un point de lancer tombé dans un mur ou un obstacle
const KNOCK_AXIS = 0.7; // recul d'un secteur : 70 % dans l'axe du coup, 30 % vers l'extérieur

/** Tirs et zones du héros de la salle courante (créés à la demande). */
export function kitStore(game) {
  const room = game.room;
  if (!room.kitFx) room.kitFx = { shots: [], zones: [] };
  return room.kitFx;
}

/** Ennemi vivant et ciblable d'après son id (0 = aucun). */
export function liveEnemy(game, id) {
  if (!id) return null;
  const e = game.enemies.find((o) => o.id === id);
  return e && !e.dead && !(e.spawnT > 0) ? e : null;
}

/**
 * Dégâts à tous les ennemis d'un cercle (recul dirigé depuis le centre). `src` : comme
 * damageEnemy, sans direction. Rend le nombre d'ennemis touchés.
 */
export function hitCircle(game, x, y, r, src) {
  let n = 0;
  for (const e of game.enemies) {
    if (e.dead || e.spawnT > 0) continue;
    const rr = r + e.r;
    const d2 = dist2(x, y, e.x, e.y);
    if (d2 >= rr * rr) continue;
    const l = Math.max(1e-6, Math.sqrt(d2));
    damageEnemy(game, e, { ...src, dirX: (e.x - x) / l, dirY: (e.y - y) / l });
    n++;
  }
  return n;
}

/**
 * Dégâts à tous les ennemis d'un secteur (comme un coup de mêlée) ; les projectiles ennemis
 * balayés sont détruits (parade). `arc` en radians. Rend le nombre d'ennemis touchés.
 */
export function hitSector(game, x, y, range, angle, arc, src) {
  const dirX = TRIG.cos(angle);
  const dirY = TRIG.sin(angle);
  let n = 0;
  for (const e of game.enemies) {
    if (e.dead || e.spawnT > 0) continue;
    if (!inSector(e.x, e.y, x, y, range, angle, arc, e.r)) continue;
    const dx = e.x - x;
    const dy = e.y - y;
    const l = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy));
    const kx = dirX * KNOCK_AXIS + (dx / l) * (1 - KNOCK_AXIS);
    const ky = dirY * KNOCK_AXIS + (dy / l) * (1 - KNOCK_AXIS);
    const kl = Math.max(1e-6, Math.sqrt(kx * kx + ky * ky));
    damageEnemy(game, e, { ...src, dirX: kx / kl, dirY: ky / kl });
    n++;
  }
  for (const pr of game.projectiles) {
    if (pr.owner !== 'enemy' || pr.dead) continue;
    if (inSector(pr.x, pr.y, x, y, range, angle, arc, pr.r)) {
      pr.dead = true;
      game.telemetry.deflects++;
      emit(game, 'deflect', { x: pr.x, y: pr.y });
    }
  }
  return n;
}

/**
 * Point d'impact d'un objet LANCÉ (pot, bombe) dans la direction (dirX, dirY) : sur la cible
 * visée si elle est à portée, sinon à `defaultDist`. Le lancer passe au-dessus des obstacles,
 * mais l'objet ne retombe jamais dans un mur : on recule le long du lancer. Écrit dans `out`.
 */
export function throwPoint(game, dirX, dirY, targetId, maxRange, defaultDist, out) {
  const p = game.player;
  let d = defaultDist;
  const e = liveEnemy(game, targetId);
  if (e) d = Math.min(maxRange, Math.sqrt(dist2(p.x, p.y, e.x, e.y)));
  while (d > 0 && pointBlocked(game.room, p.x + dirX * d, p.y + dirY * d, 0)) d -= THROW_STEP;
  d = Math.max(0, d);
  out.x = p.x + dirX * d;
  out.y = p.y + dirY * d;
  return out;
}

/**
 * Tire un ennemi vers (x, y) jusqu'à `stopDist` de ce point (centre à centre), par son élan
 * (kvx, kvy) : la friction des ennemis l'arrête pile à l'arrivée. Les ennemis plus lourds que
 * `pullMass` viennent moins loin ; un blindé résiste comme au recul ; un Gardien ne bouge pas.
 */
export function pullToward(game, e, x, y, stopDist, pullMass) {
  if (e.dead || e.boss) return 0;
  const t = game.tuning;
  const dx = x - e.x;
  const dy = y - e.y;
  const d = Math.sqrt(dx * dx + dy * dy);
  const travel = d - stopDist;
  if (travel <= 0 || d < 1e-6) return 0;
  // Somme géométrique de l'intégration (enemies.mjs) : déplacement total = v0 × DT / (1 − k).
  const k = TRIG.exp(-t.combat.enemyFriction * DT);
  let v0 = (travel * (1 - k)) / DT;
  v0 *= Math.min(1, pullMass / Math.max(1e-6, e.mass));
  if (e.eliteMod === 'blinde') v0 *= t.elite.mods.blinde.knockbackMult;
  e.kvx = (dx / d) * v0;
  e.kvy = (dy / d) * v0;
  return v0;
}
