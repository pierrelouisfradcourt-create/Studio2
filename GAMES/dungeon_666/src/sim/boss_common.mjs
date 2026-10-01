// Briques communes à tous les Gardiens (module feuille, sans import de boss.mjs) : états,
// visée, repos. Chaque modèle de Gardien vit dans son fichier src/sim/boss_<modèle>.mjs.

import { clamp } from '../core/math.mjs';
import { spawnHazard } from './combat.mjs';
import { pointBlocked } from './physics.mjs';

export function bossDef(game, e) {
  return game.tuning.boss[e.kind];
}

/** Les télégraphes d'un Gardien ne raccourcissent JAMAIS (équité, spec §4.1). */
export function wmult() {
  return 1;
}

export function toPlayer(game, e) {
  const p = game.player;
  const dx = p.x - e.x;
  const dy = p.y - e.y;
  const d = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy));
  return { dx: dx / d, dy: dy / d, d };
}

export function setState(e, s) {
  e.state = s;
  e.stateTime = 0;
  e.patternStep = 0;
  e.patternT = 0;
  // Sous-étape d'un pattern (modèles ajoutés) : remise à zéro à chaque changement d'état, y
  // compris quand une transition de phase interrompt un pattern.
  e.sub = null;
  e.subT = 0;
}

/** Fin de pattern : l'alerte disparaît, le Gardien souffle (fenêtre de punition). */
export function toRest(game, e) {
  e.tele = null;
  setState(e, 'rest');
}

// ---------------------------------------------------------------- briques des modèles ajoutés

/** Passe à la sous-étape `name` d'un pattern (chronomètre e.subT remis à zéro). */
export function setSub(e, name) {
  e.sub = name;
  e.subT = 0;
}

/** Le Gardien reste sur place ce pas-ci (il arme, frappe ou récupère). */
export function holdStill(e) {
  e.vx = 0;
  e.vy = 0;
}

/**
 * Zone de danger d'un Gardien : dégâts mis à l'échelle de l'étage, et rattachée au Gardien
 * (sourceId) — s'il meurt pendant le télégraphe, l'attaque est annulée.
 */
export function bossHazard(game, e, h) {
  return spawnHazard(game, { sourceId: e.id, hitsPlayer: true, hitsEnemies: false, ...h, damage: h.damage * e.dmgScale });
}

/** Point faible exposé : dégâts reçus majorés de `mult` pendant `duration` s (statut e.vuln). */
export function expose(e, duration, mult) {
  e.vuln = Math.max(e.vuln, duration);
  e.vulnMult = Math.max(e.vulnMult, mult);
}

/**
 * Récupération immobile et exposée qui clôt un pattern (la fenêtre de punition), puis repos.
 * À appeler à chaque pas tant que la sous-étape est 'recover'.
 */
export function exposedRecovery(game, e, duration, mult, dt) {
  holdStill(e);
  if (e.sub !== 'recover') {
    setSub(e, 'recover');
    expose(e, duration, mult);
  }
  e.subT += dt;
  if (e.subT >= duration) toRest(game, e);
}

const ROOM_POINT_STEPS = 16; // pas de recherche vers le centre (résolution, pas un réglage de jeu)

/** Point jouable le plus proche de (x, y) pour un corps de rayon r (murs ; obstacles évités). */
export function roomPoint(game, x, y, r) {
  const room = game.room;
  const px = clamp(x, room.pad + r, room.w - room.pad - r);
  const py = clamp(y, room.pad + r, room.h - room.pad - r);
  if (!pointBlocked(room, px, py, r)) return { x: px, y: py };
  // Sur un obstacle : on recule vers le centre de la salle jusqu'à trouver de la place.
  const cx = room.w / 2;
  const cy = room.h / 2;
  for (let k = 1; k <= ROOM_POINT_STEPS; k++) {
    const f = k / ROOM_POINT_STEPS;
    const qx = px + (cx - px) * f;
    const qy = py + (cy - py) * f;
    if (!pointBlocked(room, qx, qy, r)) return { x: qx, y: qy };
  }
  return { x: cx, y: cy };
}

/** Serviteurs invoqués encore en jeu (vivants ou en cours d'apparition). */
export function summonedAlive(game) {
  let n = 0;
  for (const o of game.enemies) if (!o.dead && o.summoned) n++;
  for (const s of game.spawns) if (s.summoned) n++;
  return n;
}
