// Gardien « Cerbère, le Chien des trois gueules » (modèle `cerbere`, section 2 puis en rotation).
// Bête RAPIDE qui ne laisse pas respirer : au repos elle RÔDE en cercle autour du héros au lieu de
// marcher sur lui, et attaque par séries de trois (trois têtes). Patterns, tous télégraphiés :
//   bond      — bonds annoncés par le CERCLE D'ATTERRISSAGE posé sous le héros (1 / 2 / 3 bonds
//               selon la phase) ; dès la phase 2 (bond.shockFromPhase), le dernier atterrissage
//               libère une onde (anneau) : rester dans le cercle qui vient de frapper, ou caler
//               les i-frames d'un dash sur l'onde. Après la série, il est ESSOUFFLÉ : immobile,
//               point faible exposé — la fenêtre de punition.
//   souffle   — les trois têtes crachent l'une après l'autre trois jets de flammes en éventail
//               (bandes qui partent de son centre) ; son DOS est sûr. Deux salves, ordre inversé,
//               dès la phase 2.
//   morsures  — trois ruées enchaînées, chacune re-visée et annoncée par un cône ; une ruée ne
//               mord QUE dans son cône dessiné (corps du héros compris). La dernière l'expose.
//   hurlement — (phase 3, frénésie) un cercle de flammes se referme autour du héros, avec une
//               brèche, puis Cerbère bondit en son centre : sortir par la brèche, ou dasher.

import * as TRIG from '../core/trig.mjs'; // sinus, cosinus… déterministes : jamais Math.sin & co dans la simulation
import { rand } from '../core/rng.mjs';
import { dist2, clamp, inSector, TAU } from '../core/math.mjs';
import { emit, newId } from './state.mjs';
import { damagePlayer } from './combat.mjs';
import { toPlayer, toRest, setSub, holdStill, bossHazard, exposedRecovery, roomPoint } from './boss_common.mjs';

const DEG = Math.PI / 180;
const LEAP_STATES = new Set(['bond', 'hurlement']);

/** Cri d'attaque : le son porte le timbre du Gardien (recipes.mjs, ENEMY_ATTACK.cerbere). */
function bark(game, e) {
  emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: 'cerbere' });
}

// ---------------------------------------------------------------- bond (brique partagée)

/**
 * Prépare un bond vers (tx, ty) : le cercle d'atterrissage apparaît AUSSITÔT (télégraphe de
 * `delay` s) ; le chien s'accroupit, puis s'envole pendant les `air` dernières secondes et
 * retombe à l'instant où le cercle frappe. En l'air, aucun dégât de contact.
 */
function startLeap(game, e, b, tx, ty, delay, shock) {
  const pt = roomPoint(game, tx, ty, e.r);
  e.leap = { x0: e.x, y0: e.y, x1: pt.x, y1: pt.y, t: 0, delay };
  bossHazard(game, e, { shape: 'circle', x: pt.x, y: pt.y, r: b.radius, delay, damage: b.damage, kind: 'cerbereLand' });
  if (shock) {
    bossHazard(game, e, {
      shape: 'ring', x: pt.x, y: pt.y, r: b.radius + b.shockWidth, inner: b.radius,
      delay: delay + b.shockDelay, damage: b.shockDamage, kind: 'cerbereShock',
    });
  }
}

/** Fait avancer le bond en cours ; rend true au pas de l'atterrissage. */
function stepLeap(game, e, b, dt) {
  const L = e.leap;
  holdStill(e);
  L.t += dt;
  const takeoff = L.delay - b.air;
  if (L.t < takeoff) return false;
  if (L.t < L.delay) {
    const k = (L.t - takeoff) / b.air;
    e.airborne = true;
    e.leapK = k; // hauteur du saut (dessin)
    e.x = L.x0 + (L.x1 - L.x0) * k;
    e.y = L.y0 + (L.y1 - L.y0) * k;
    return false;
  }
  e.x = L.x1;
  e.y = L.y1;
  e.airborne = false;
  e.leapK = 0;
  e.leap = null;
  bark(game, e);
  return true;
}

export function bond(game, e, d, dt) {
  const b = d.bond;
  const leaps = b.leapsByPhase[e.phase - 1];
  if (e.sub === 'recover' || e.patternStep >= leaps) {
    exposedRecovery(game, e, b.recover, b.exposedMult, dt);
    return;
  }
  if (!e.leap) {
    // Petite pause entre deux bonds d'une même série (le cercle suivant naît à l'atterrissage).
    e.subT += dt;
    holdStill(e);
    if (e.patternStep > 0 && e.subT < b.interval) return;
    const p = game.player;
    const last = e.patternStep === leaps - 1;
    startLeap(game, e, b, p.x, p.y, b.windup, last && e.phase >= b.shockFromPhase);
  }
  if (stepLeap(game, e, b, dt)) {
    e.patternStep++;
    e.subT = 0;
  }
}

// ---------------------------------------------------------------- souffle

function volley(game, e, s, index) {
  const tp = toPlayer(game, e);
  const aim = TRIG.atan2(tp.dy, tp.dx);
  // Sens de la salve (gauche -> droite ou l'inverse) : tiré pour la 1re, alterné ensuite.
  if (index === 0) e.breathDir = rand(game.rng.ai) < 0.5 ? 1 : -1;
  else e.breathDir = -e.breathDir;
  const n = s.jets;
  for (let i = 0; i < n; i++) {
    const rank = e.breathDir > 0 ? i : n - 1 - i;
    const a = aim + (i - (n - 1) / 2) * s.spreadDeg * DEG;
    bossHazard(game, e, {
      shape: 'line', x: e.x, y: e.y, angle: a, length: s.length, width: s.width,
      delay: s.windup + rank * s.step, damage: s.damage, kind: 'cerbereFlame',
    });
  }
  bark(game, e);
}

export function souffle(game, e, d) {
  const s = d.souffle;
  holdStill(e);
  const volleys = s.volleysByPhase[e.phase - 1];
  const length = s.windup + (s.jets - 1) * s.step; // dernier jet d'une salve
  const period = length + s.volleyGap;
  if (e.patternStep < volleys && e.stateTime >= e.patternStep * period) {
    volley(game, e, s, e.patternStep);
    e.patternStep++;
  }
  if (e.stateTime >= (volleys - 1) * period + length) toRest(game, e);
}

// ---------------------------------------------------------------- morsures

/** Portée du cône dessiné : la course de la ruée + le corps + la marge (morsures.telePad). */
function biteRange(e, m) {
  return m.strikeSpeed * m.strikeTime + e.r + m.telePad;
}

export function morsures(game, e, d, dt, speed) {
  const m = d.morsures;
  const p = game.player;
  if (e.patternStep >= m.bites) {
    // Dernière morsure : la gueule reste plantée, le flanc est exposé.
    exposedRecovery(game, e, m.finalRecover, m.exposedMult, dt);
    return;
  }
  if (!e.sub) setSub(e, 'approach');
  e.subT += dt;
  switch (e.sub) {
    case 'approach': {
      // Trop loin pour mordre : il fonce (aucun dégât de contact), au plus `approachMax` s.
      const tp = toPlayer(game, e);
      if (tp.d <= biteRange(e, m) * m.engageFrac || e.subT >= m.approachMax) {
        setSub(e, 'windup');
        break;
      }
      e.vx = tp.dx * speed * m.approachMult;
      e.vy = tp.dy * speed * m.approachMult;
      break;
    }
    case 'windup': {
      holdStill(e);
      // La gueule suit le héros, puis se fige (lockAt) : la ruée part là où le cône le montre.
      if (e.subT < m.windup * m.lockAt) {
        const tp = toPlayer(game, e);
        e.dirX = tp.dx;
        e.dirY = tp.dy;
      }
      e.tele = { shape: 'cone', angle: TRIG.atan2(e.dirY, e.dirX), range: biteRange(e, m), arc: m.arcDeg * DEG, progress: e.subT / m.windup };
      if (e.subT >= m.windup) {
        e.tele = null;
        e.hitPlayer = false;
        e.atkId = newId(game);
        // Origine du cône dessiné : la ruée ne mordra que dedans.
        e.biteX = e.x;
        e.biteY = e.y;
        setSub(e, 'strike');
        bark(game, e);
      }
      break;
    }
    case 'strike': {
      e.vx = e.dirX * m.strikeSpeed;
      e.vy = e.dirY * m.strikeSpeed;
      // Contact de la gueule (morsures.hitPad) ET corps du héros dans le cône annoncé : la ruée
      // ne déborde jamais du télégraphe (près de l'apex, le contact seul dépasserait du cône).
      const inCone = inSector(p.x, p.y, e.biteX, e.biteY, biteRange(e, m), TRIG.atan2(e.dirY, e.dirX), m.arcDeg * DEG, p.r);
      if (!e.hitPlayer && inCone && dist2(e.x, e.y, p.x, p.y) < (e.r + p.r + m.hitPad) ** 2) {
        e.hitPlayer = true;
        damagePlayer(game, m.damage * e.dmgScale, { kind: 'cerbereBite', id: e.atkId, x: e.x, y: e.y });
      }
      if (e.subT >= m.strikeTime) {
        e.patternStep++;
        setSub(e, 'gap');
      }
      break;
    }
    default: // 'gap' : souffle court entre deux morsures
      holdStill(e);
      if (e.subT >= m.recover) setSub(e, 'windup');
  }
}

// ---------------------------------------------------------------- hurlement (phase 3)

export function hurlement(game, e, d, dt) {
  const h = d.hurlement;
  const b = d.bond;
  if (e.sub === 'recover' || (!e.leap && e.patternStep > 0)) {
    exposedRecovery(game, e, b.recover, b.exposedMult, dt);
    return;
  }
  if (!e.leap) {
    const p = game.player;
    const room = game.room;
    const c = roomPoint(game, p.x, p.y, e.r);
    // Couronne de flammes autour du héros, avec une brèche de `gaps` flammes à un angle tiré.
    const a0 = rand(game.rng.ai) * TAU;
    for (let k = h.gaps; k < h.flames; k++) {
      const a = a0 + (k / h.flames) * TAU;
      const fx = clamp(c.x + TRIG.cos(a) * h.ringRadius, room.pad, room.w - room.pad);
      const fy = clamp(c.y + TRIG.sin(a) * h.ringRadius, room.pad, room.h - room.pad);
      bossHazard(game, e, { shape: 'circle', x: fx, y: fy, r: h.flameRadius, delay: h.delay, damage: h.damage, kind: 'cerbereFire' });
    }
    // ... et le chien bondit au centre, juste après.
    startLeap(game, e, b, c.x, c.y, h.leapDelay, false);
    e.patternStep = 1;
    bark(game, e);
  }
  if (stepLeap(game, e, b, dt)) exposedRecovery(game, e, b.recover, b.exposedMult, 0);
}

// ---------------------------------------------------------------- repos : il rôde

/** Au repos, Cerbère tourne autour du héros à distance (`prowl.dist`) au lieu de l'approcher. */
function prowl(game, e, d, dt, speed) {
  const pr = d.prowl;
  const p = game.player;
  const dx = e.x - p.x;
  const dy = e.y - p.y;
  const dd = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy));
  const ux = dx / dd;
  const uy = dy / dd;
  const radial = clamp((pr.dist - dd) / pr.dist, -1, 1) * pr.radialGain; // > 0 : trop près, il s'écarte
  const vx = -uy * e.strafe + ux * radial;
  const vy = ux * e.strafe + uy * radial;
  const l = Math.max(1e-6, Math.sqrt(vx * vx + vy * vy));
  e.vx = (vx / l) * speed;
  e.vy = (vy / l) * speed;
}

/** À chaque pas : un bond interrompu (transition de phase) ne laisse pas le chien « en l'air ». */
function tick(game, e) {
  if (!LEAP_STATES.has(e.state) && (e.leap || e.airborne)) {
    e.leap = null;
    e.airborne = false;
    e.leapK = 0;
  }
}

// Bonds, morsures et souffle d'emblée (le souffle double sa salve dès la phase 2) ; la frénésie
// (hurlement) s'ajoute en phase 3.
export const CERBERE = {
  byPhase: { 1: ['bond', 'morsures', 'souffle'], 2: ['bond', 'morsures', 'souffle'], 3: ['bond', 'morsures', 'souffle', 'hurlement'] },
  patterns: { bond, souffle, morsures, hurlement },
  rest: prowl,
  tick,
};
