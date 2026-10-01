// Gardien « Minos, le Juge des damnés » (modèle `minos`, section 3 puis en rotation).
// Contrôle de l'ARÈNE : il ne poursuit jamais. Il siège (dérive lente vers son trône) et rend
// l'espace dangereux par motifs géométriques. Patterns, tous télégraphiés :
//   sentence — bandes parallèles qui BALAIENT l'arène l'une après l'autre ; chacune a une brèche.
//              Phase 1 : brèches alignées (un couloir) ; phase 2 : une brèche par bande ;
//              phase 3 : un second balayage perpendiculaire. Contre-jeu : la brèche de sa bande,
//              une bande qui vient de frapper, ou un dash à travers (bande < portée du dash).
//   jugement — dalles en damier autour du héros, en deux (phase 3 : trois) temps ; la dalle du
//              héros frappe toujours la première : passer sur une dalle voisine, puis revenir.
//   fouet    — sa queue balaie 360° autour de lui SAUF une brèche (jamais du côté du héros) ;
//              phase 2+ : second coup, brèche ailleurs. Après le fouet, il se découvre.
//   sceau    — (phase 2+) il se dissout et se matérialise sur le héros : la sentence tombe en
//              COURONNE autour du point d'arrivée — rester au centre (contre lui) ou fuir loin.
//              Phase 3 : le fouet suit aussitôt.

import * as TRIG from '../core/trig.mjs'; // sinus, cosinus… déterministes : jamais Math.sin & co dans la simulation
import { rand, randRange } from '../core/rng.mjs';
import { clamp, inSector, TAU } from '../core/math.mjs';
import { emit, newId } from './state.mjs';
import { damagePlayer } from './combat.mjs';
import { toPlayer, setState, toRest, setSub, holdStill, bossHazard, exposedRecovery, roomPoint } from './boss_common.mjs';

const DEG = Math.PI / 180;

/** Coup de marteau du Juge : le son porte son timbre (recipes.mjs, ENEMY_ATTACK.minos). */
function gavel(game, e) {
  emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: 'minos' });
}

/** Il incante : alerte INOFFENSIVE autour de lui (le danger, lui, est dessiné au sol en rouge). */
function chant(e, d, progress) {
  e.tele = { shape: 'circle', r: e.r + d.chantPad, progress: clamp(progress, 0, 1), harmless: true };
}

// ---------------------------------------------------------------- sentence

/** Brèche tirée à portée de marche du héros (sur l'axe des bandes), bornée à la salle. */
function breachAt(game, s, ref, along) {
  const lo = game.room.pad + s.breach / 2;
  const hi = along - game.room.pad - s.breach / 2;
  return clamp(ref + randRange(game.rng.ai, -s.breachReach, s.breachReach), lo, hi);
}

/**
 * Un balayage : `n` bandes jointives perpendiculaires à l'axe, qui frappent dans l'ordre
 * (pas `step`) ; chaque bande = deux segments de part et d'autre de sa brèche.
 * horizontal : bandes horizontales (balayage haut <-> bas). Rend la durée jusqu'au dernier coup.
 */
function sweep(game, e, s, horizontal, forward, sharedBreach) {
  const room = game.room;
  const p = game.player;
  const n = horizontal ? s.bandsH : s.bandsV;
  const span = (horizontal ? room.h : room.w) - 2 * room.pad;
  const along = horizontal ? room.w : room.h;
  const band = span / n;
  const ref = horizontal ? p.x : p.y;
  const shared = breachAt(game, s, ref, along);
  for (let i = 0; i < n; i++) {
    const rank = forward ? i : n - 1 - i;
    const c = room.pad + (i + 0.5) * band;
    const b = sharedBreach ? shared : breachAt(game, s, ref, along);
    const delay = s.delay + rank * s.step;
    for (const [a0, a1] of [[room.pad, b - s.breach / 2], [b + s.breach / 2, along - room.pad]]) {
      if (a1 - a0 <= 0) continue;
      const h = horizontal
        ? { x: a0, y: c, angle: 0 }
        : { x: c, y: a0, angle: Math.PI / 2 };
      bossHazard(game, e, { shape: 'line', ...h, length: a1 - a0, width: band, delay, damage: s.damage, kind: 'minosSentence' });
    }
  }
  gavel(game, e);
  return s.delay + (n - 1) * s.step;
}

export function sentence(game, e, d, dt) {
  const s = d.sentence;
  holdStill(e);
  const sweeps = e.phase >= s.crossFromPhase ? 2 : 1;
  if (!e.sub) {
    e.sweepH = rand(game.rng.ai) < 0.5;
    e.sweepEnd = sweep(game, e, s, e.sweepH, rand(game.rng.ai) < 0.5, e.phase < s.ownBreachFromPhase);
    e.patternStep = 1;
    setSub(e, 'sweep');
  }
  e.subT += dt;
  chant(e, d, e.subT / e.sweepEnd);
  if (e.subT < e.sweepEnd) return;
  if (e.patternStep < sweeps) {
    // Phase 3 : la croix — le second balayage, perpendiculaire, naît quand le premier s'achève.
    if (e.subT < e.sweepEnd + s.crossGap) return;
    e.sweepH = !e.sweepH;
    e.sweepEnd = sweep(game, e, s, e.sweepH, rand(game.rng.ai) < 0.5, false);
    e.patternStep++;
    e.subT = 0;
    return;
  }
  toRest(game, e);
}

// ---------------------------------------------------------------- jugement

/** Une vague de dalles : les cases de parité `parity` (0 = celle du héros) autour de lui. */
function tileWave(game, e, j, parity) {
  const room = game.room;
  const s = j.spacing;
  const cols = Math.floor((room.w - 2 * room.pad) / s);
  const rows = Math.floor((room.h - 2 * room.pad) / s);
  const ox = (room.w - cols * s) / 2;
  const oy = (room.h - rows * s) / 2;
  const r = s * j.radiusMult;
  for (let i = Math.max(0, e.tileI - j.reach); i <= Math.min(cols - 1, e.tileI + j.reach); i++) {
    for (let k = Math.max(0, e.tileJ - j.reach); k <= Math.min(rows - 1, e.tileJ + j.reach); k++) {
      if ((i + k + e.tileI + e.tileJ) % 2 !== parity) continue;
      bossHazard(game, e, { shape: 'circle', x: ox + (i + 0.5) * s, y: oy + (k + 0.5) * s, r, delay: j.delay, damage: j.damage, kind: 'minosTile' });
    }
  }
  gavel(game, e);
}

export function jugement(game, e, d, dt) {
  const j = d.jugement;
  holdStill(e);
  const waves = j.wavesByPhase[e.phase - 1];
  if (!e.sub) {
    // Le damier est calé sur la case du héros AU DÉBUT : sa case frappe en premier.
    const room = game.room;
    const cols = Math.floor((room.w - 2 * room.pad) / j.spacing);
    const rows = Math.floor((room.h - 2 * room.pad) / j.spacing);
    const p = game.player;
    e.tileI = clamp(Math.floor((p.x - (room.w - cols * j.spacing) / 2) / j.spacing), 0, cols - 1);
    e.tileJ = clamp(Math.floor((p.y - (room.h - rows * j.spacing) / 2) / j.spacing), 0, rows - 1);
    setSub(e, 'tiles');
  }
  e.subT += dt;
  // Vague w posée à w × gap : au plus deux vagues visibles, chacune télégraphiée `delay` s.
  while (e.patternStep < waves && e.subT >= e.patternStep * j.gap) {
    tileWave(game, e, j, e.patternStep % 2);
    e.patternStep++;
  }
  const end = (waves - 1) * j.gap + j.delay;
  chant(e, d, e.subT / end);
  if (e.subT >= end) toRest(game, e);
}

// ---------------------------------------------------------------- fouet

export function fouet(game, e, d, dt) {
  const f = d.fouet;
  const p = game.player;
  holdStill(e);
  const whips = e.phase >= f.doubleFromPhase ? 2 : 1;
  if (e.sub === 'recover' || e.patternStep >= whips) {
    exposedRecovery(game, e, f.recover, f.exposedMult, dt);
    return;
  }
  const windup = e.patternStep === 0 ? f.windup : f.secondWindup;
  if (e.sub !== 'whip') {
    // Brèche à au moins `minOffsetDeg` du côté du héros : il faut toujours bouger.
    const tp = toPlayer(game, e);
    const side = rand(game.rng.ai) < 0.5 ? -1 : 1;
    const min = f.minOffsetDeg * DEG;
    e.breachAngle = TRIG.atan2(tp.dy, tp.dx) + side * (min + rand(game.rng.ai) * (Math.PI - min));
    setSub(e, 'whip');
  }
  e.subT += dt;
  const arc = TAU - f.breachDeg * DEG;
  const angle = e.breachAngle + Math.PI;
  // Cône « de zone » (area) : le corps ne bouge pas, tout le secteur frappe d'un coup.
  e.tele = { shape: 'cone', area: true, angle, range: f.range, arc, progress: e.subT / windup };
  if (e.subT < windup) return;
  e.tele = null;
  gavel(game, e);
  if (inSector(p.x, p.y, e.x, e.y, f.range, angle, arc, p.r)) {
    damagePlayer(game, f.damage * e.dmgScale, { kind: 'minosWhip', id: newId(game), x: e.x, y: e.y });
  }
  e.patternStep++;
  setSub(e, 'next');
}

// ---------------------------------------------------------------- sceau (téléportation)

export function sceau(game, e, d, dt) {
  const s = d.sceau;
  holdStill(e);
  if (!e.sub) {
    const p = game.player;
    const pt = roomPoint(game, p.x, p.y, e.r);
    e.sealX = pt.x;
    e.sealY = pt.y;
    bossHazard(game, e, { shape: 'ring', x: pt.x, y: pt.y, r: s.outer, inner: s.inner, delay: s.delay, damage: s.damage, kind: 'minosSeal' });
    e.hidden = true; // dissous : intouchable, dessiné en filigrane (art_bosses.mjs)
    setSub(e, 'vanish');
    gavel(game, e);
  }
  e.subT += dt;
  if (e.subT < s.delay) {
    e.invuln = Math.max(e.invuln, s.delay - e.subT);
    return;
  }
  e.x = e.sealX;
  e.y = e.sealY;
  e.hidden = false;
  e.invuln = 0;
  gavel(game, e);
  if (e.phase >= s.whipFromPhase) {
    // Phase 3 : à peine matérialisé, il fouette (son propre télégraphe, jamais raccourci).
    e.pattern = 'fouet';
    setState(e, 'fouet');
    return;
  }
  toRest(game, e);
}

// ---------------------------------------------------------------- repos : il siège

/** Au repos, Minos regagne lentement son trône ; il ne court jamais après le héros. */
function sit(game, e, d, dt, speed) {
  const room = game.room;
  const tx = room.w * d.throne.fx;
  const ty = room.h * d.throne.fy;
  const dx = tx - e.x;
  const dy = ty - e.y;
  const l = Math.sqrt(dx * dx + dy * dy);
  if (l < d.throne.settle) return;
  e.vx = (dx / l) * speed;
  e.vy = (dy / l) * speed;
}

/** À chaque pas : un sceau interrompu ne laisse jamais Minos invisible. */
function tick(game, e) {
  if (e.hidden && e.state !== 'sceau') e.hidden = false;
}

// Sentence, fouet et jugement d'emblée ; le sceau en phase 2 ; tout s'enchaîne en phase 3.
export const MINOS = {
  byPhase: { 1: ['sentence', 'fouet', 'jugement'], 2: ['sentence', 'fouet', 'jugement', 'sceau'], 3: ['sentence', 'fouet', 'jugement', 'sceau'] },
  patterns: { sentence, jugement, fouet, sceau },
  rest: sit,
  tick,
};
