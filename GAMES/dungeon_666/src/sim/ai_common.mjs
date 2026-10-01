// Briques d'IA partagées par tous les archétypes d'ennemis (module feuille : n'importe pas
// enemies.mjs, pour que chaque archétype vive dans son propre fichier sans import circulaire).

import { rand } from '../core/rng.mjs';
import { emit } from './state.mjs';
import { lineOfSight } from './physics.mjs';
import { navDirection } from './nav.mjs';
import { queueSpawn, findSpawnPoint } from './spawns.mjs';

// Archétypes qui prennent un JETON D'ATTAQUE de mêlée (au plus combat.maxAttackers à la fois).
export const MELEE_KINDS = new Set(['imp', 'brute', 'charger']);
// Archétypes qui prennent un jeton de TIR (au plus combat.maxShooters à la fois).
export const SHOOTER_KINDS = new Set(['archer']);

export function speedOf(game, e, def) {
  let s = def.speed;
  if (e.eliteMod === 'rapide') s *= game.tuning.elite.mods.rapide.speedMult;
  if (e.chill > 0) s *= e.chillMult;
  return s;
}

export function windupOf(game, e, base) {
  return e.eliteMod === 'rapide' ? base * game.tuning.elite.mods.rapide.windupMult : base;
}

export function activeAttackers(game) {
  let n = 0;
  for (const o of game.enemies) {
    if (!o.dead && MELEE_KINDS.has(o.kind) && (o.state === 'windup' || o.state === 'strike' || o.state === 'charge')) n++;
  }
  return n;
}

export function activeShooters(game) {
  let n = 0;
  for (const o of game.enemies) if (!o.dead && SHOOTER_KINDS.has(o.kind) && o.state === 'windup') n++;
  return n;
}

export function setState(e, s) {
  e.state = s;
  e.stateTime = 0;
}

export function toPlayer(game, e) {
  const p = game.player;
  const dx = p.x - e.x;
  const dy = p.y - e.y;
  const d = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy));
  return { dx: dx / d, dy: dy / d, d };
}

const navOut = { x: 0, y: 0 };

/** Se dirige vers (x, y) ; sans ligne de vue, suit le champ de navigation (contourne). */
export function steer(game, e, x, y, speed) {
  const dx = x - e.x;
  const dy = y - e.y;
  const d = Math.sqrt(dx * dx + dy * dy);
  if (d < 4) return;
  if (!lineOfSight(game.room, e.x, e.y, x, y) && navDirection(game, e.x, e.y, navOut)) {
    e.vx = navOut.x * speed;
    e.vy = navOut.y * speed;
    return;
  }
  e.vx = (dx / d) * speed;
  e.vy = (dy / d) * speed;
}

/** Fait suivre la direction visée jusqu'au verrouillage, puis la fige (équité). */
export function trackUntilLock(game, e, lockFraction, windup) {
  if (e.stateTime < windup * lockFraction) {
    const tp = toPlayer(game, e);
    e.dirX = tp.dx;
    e.dirY = tp.dy;
  }
}

/** Nombre d'ennemis vivants d'un archétype (plafonds d'invocation, etc.). */
export function countAlive(game, kind) {
  let n = 0;
  for (const o of game.enemies) if (!o.dead && o.kind === kind) n++;
  return n;
}

// ---------------------------------------------------------------- tireurs à distance

/**
 * Garde ses distances (archétypes à distance : zone, invocateur) : fuit sous `def.fleeDist`,
 * se rapproche au-delà de `def.preferredDist + def.approachSlack` ou sans ligne de vue, sinon
 * tourne autour du héros (`def.strafeMult` de la vitesse ; change parfois de sens, avec la
 * probabilité `def.strafeFlip` par image). Le comportement de l'archer, mis en données.
 */
export function keepDistance(game, e, def, tp, sees, speed) {
  if (tp.d < def.fleeDist) {
    e.vx = -tp.dx * speed;
    e.vy = -tp.dy * speed;
  } else if (tp.d > def.preferredDist + def.approachSlack || !sees) {
    steer(game, e, game.player.x, game.player.y, speed);
  } else {
    e.vx = -tp.dy * speed * def.strafeMult * e.strafe;
    e.vy = tp.dx * speed * def.strafeMult * e.strafe;
    if (rand(game.rng.ai) < def.strafeFlip) e.strafe = -e.strafe;
  }
}

// ---------------------------------------------------------------- invocations

/** Invocations en cours dans la salle : vivantes (hors boss) + cercles d'invocation en attente. */
export function summonedCount(game) {
  let n = 0;
  for (const o of game.enemies) if (!o.dead && o.summoned && !o.boss) n++;
  for (const s of game.spawns) if (s.summoned) n++;
  return n;
}

/**
 * Plafond d'invocations VIVANTES de la salle : somme des plafonds des invocateurs vivants
 * (archétype : tuning.enemies[kind].maxMinions ; élite : tuning.elite.mods[mod].maxMinions).
 * Un invocateur mort ne compte plus : ses invocations restent, mais plus rien ne s'y ajoute.
 */
export function summonCap(game) {
  const t = game.tuning;
  let cap = 0;
  for (const o of game.enemies) {
    if (o.dead || o.boss) continue;
    cap += t.enemies[o.kind]?.maxMinions ?? 0;
    if (o.eliteMod) cap += t.elite.mods[o.eliteMod]?.maxMinions ?? 0;
  }
  return cap;
}

/** Places libres sous le plafond d'invocations de la salle. */
export function summonRoom(game) {
  return Math.max(0, summonCap(game) - summonedCount(game));
}

/**
 * Ouvre jusqu'à `count` cercles d'invocation (queueSpawn : visibles `room.spawnWarn` s avant
 * l'apparition, jamais sous les pieds du héros) autour de `e`. Rend le nombre de cercles ouverts.
 */
export function summonAround(game, e, kind, count, minR, maxR, minPlayerDist) {
  const r = game.tuning.enemies[kind].radius;
  let n = 0;
  for (let i = 0; i < count; i++) {
    const pt = findSpawnPoint(game, r, minPlayerDist, { x: e.x, y: e.y, minR: e.r + minR, maxR: e.r + maxR });
    if (!pt) continue;
    queueSpawn(game, kind, pt.x, pt.y, { summoned: true });
    n++;
  }
  return n;
}

export { emit };
