// Gardien « Éphialte, le Colosse enchaîné » (modèle `colosse`, section 4 — fin du 1er Cercle —
// puis en rotation). Géant LENT et massif : chaque coup est énorme mais lisible de loin ; il
// RÉTRÉCIT l'arène (braises persistantes) et se protège derrière ses geôliers. Patterns :
//   poing    — coups de poing en ligne (1 / 2 / 3 selon la phase), chacun visé là où se tient le
//              héros ; après le dernier, le bras reste coincé : POINT FAIBLE exposé (dégâts majorés).
//   seisme   — ondes concentriques (un cercle puis des anneaux) qui partent de lui l'une après
//              l'autre : entrer dans l'onde déjà passée (vers lui !) ou dasher à travers.
//   eboulis  — rochers télégraphiés autour du héros (l'un tombe sur lui) ; dès la phase 2, chaque
//              rocher laisse une BRAISE qui pulse (cercle rejoué, durée bornée) : l'arène rétrécit.
//   geoliers — (phase 2+, UNE fois par phase : geoliers.callsPerPhase) il appelle ses geôliers
//              (archers) ; tant qu'ils vivent, ses chaînes le rendent INVULNÉRABLE (bouclier
//              visible, borné dans le temps) : les adds d'abord.
// Changement de phase : les braises s'éteignent avec les autres zones (crochet onPhase).

import { rand } from '../core/rng.mjs';
import { clamp, TAU } from '../core/math.mjs';
import { emit } from './state.mjs';
import { queueSpawn, findSpawnPoint } from './spawns.mjs';
import { toPlayer, toRest, setSub, holdStill, bossHazard, exposedRecovery, summonedAlive } from './boss_common.mjs';

/** Grondement d'effort : le son porte le timbre du Gardien (recipes.mjs, ENEMY_ATTACK.colosse). */
function grunt(game, e) {
  emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: 'colosse' });
}

// ---------------------------------------------------------------- poing

export function poing(game, e, d, dt) {
  const f = d.poing;
  holdStill(e);
  const fists = f.fistsByPhase[e.phase - 1];
  if (e.sub === 'recover') {
    exposedRecovery(game, e, f.stuck, f.exposedMult, dt);
    return;
  }
  e.subT += dt;
  // Poing k posé à k × fistGap, visé sur le héros À CET INSTANT, télégraphié `windup` s.
  while (e.patternStep < fists && e.subT >= e.patternStep * f.fistGap) {
    const tp = toPlayer(game, e);
    bossHazard(game, e, {
      shape: 'line', x: e.x, y: e.y, angle: Math.atan2(tp.dy, tp.dx), length: e.r + f.length, width: f.width,
      delay: f.windup, damage: f.damage, kind: 'colosseFist',
    });
    e.patternStep++;
    grunt(game, e);
  }
  // Le dernier poing frappe : le bras reste coincé dans le sol.
  if (e.subT >= (fists - 1) * f.fistGap + f.windup) exposedRecovery(game, e, f.stuck, f.exposedMult, 0);
}

// ---------------------------------------------------------------- séisme

export function seisme(game, e, d, dt) {
  const q = d.seisme;
  holdStill(e);
  const rings = q.ringsByPhase[e.phase - 1];
  if (!e.sub) {
    for (let k = 0; k < rings; k++) {
      const delay = q.delay + k * q.step;
      if (k === 0) bossHazard(game, e, { shape: 'circle', x: e.x, y: e.y, r: q.band, delay, damage: q.damage, kind: 'colosseQuake' });
      else bossHazard(game, e, { shape: 'ring', x: e.x, y: e.y, r: (k + 1) * q.band, inner: k * q.band, delay, damage: q.damage, kind: 'colosseQuake' });
    }
    setSub(e, 'quake');
    grunt(game, e);
  }
  e.subT += dt;
  if (e.subT >= q.delay + (rings - 1) * q.step) toRest(game, e);
}

// ---------------------------------------------------------------- éboulis

export function eboulis(game, e, d, dt) {
  const b = d.eboulis;
  holdStill(e);
  if (!e.sub) {
    const room = game.room;
    const p = game.player;
    const rocks = b.rocksByPhase[e.phase - 1];
    let last = 0;
    for (let k = 0; k < rocks; k++) {
      // Le premier tombe sur le héros ; les autres autour de lui (tirage uniforme dans le disque).
      const a = rand(game.rng.ai) * TAU;
      const rr = k === 0 ? 0 : b.spread * Math.sqrt(rand(game.rng.ai));
      const x = clamp(p.x + Math.cos(a) * rr, room.pad + b.radius / 2, room.w - room.pad - b.radius / 2);
      const y = clamp(p.y + Math.sin(a) * rr, room.pad + b.radius / 2, room.h - room.pad - b.radius / 2);
      const delay = b.delayMin + rand(game.rng.ai) * (b.delayMax - b.delayMin);
      last = Math.max(last, delay);
      const rock = bossHazard(game, e, { shape: 'circle', x, y, r: b.radius, delay, damage: b.damage, kind: 'colosseRock' });
      if (e.phase >= b.poolFromPhase) addPool(e, b, rock);
    }
    e.rockEnd = last;
    setSub(e, 'fall');
    grunt(game, e);
  }
  e.subT += dt;
  if (e.subT >= e.rockEnd) toRest(game, e);
}

// ---------------------------------------------------------------- braises (zones persistantes)

/** Braise promise par un rocher : elle s'allume quand il tombe VRAIMENT, puis pulse poolLife s. */
function addPool(e, b, rock) {
  if (!e.pools) e.pools = [];
  e.pools.push({ x: rock.x, y: rock.y, rock, end: Infinity, h: null });
  // Au plus `poolMax` braises : la plus ancienne s'éteint (l'arène rétrécit, sans jamais se fermer).
  while (e.pools.length > b.poolMax) e.pools.shift();
}

/** Chaque braise active rejoue un cercle télégraphié de `poolPulse` s tant qu'elle brûle. */
function tickPools(game, e, b) {
  if (!e.pools || e.pools.length === 0) return;
  let w = 0;
  for (const pool of e.pools) {
    if (pool.rock) {
      // Rocher annulé (transition de phase) : pas de braise. Encore en l'air : on attend.
      if (!pool.rock.done) {
        e.pools[w++] = pool;
        continue;
      }
      if (pool.rock.t < pool.rock.delay) continue;
      pool.rock = null;
      pool.end = game.time + b.poolLife;
    }
    if (game.time >= pool.end) continue;
    e.pools[w++] = pool;
    if (!pool.h || pool.h.done) {
      pool.h = bossHazard(game, e, { shape: 'circle', x: pool.x, y: pool.y, r: b.poolRadius, delay: b.poolPulse, damage: b.poolDamage, kind: 'colosseEmber' });
    }
  }
  e.pools.length = w;
}

// ---------------------------------------------------------------- geôliers et bouclier

export function geoliers(game, e, d, dt) {
  const g = d.geoliers;
  holdStill(e);
  if (!e.sub) setSub(e, 'call');
  e.subT += dt;
  if (e.sub === 'call') {
    // Appel : alerte INOFFENSIVE (violette), comme toute invocation.
    e.tele = { shape: 'circle', r: e.r + g.telePad, progress: e.subT / g.windup, harmless: true };
    if (e.subT < g.windup) return;
    e.tele = null;
    const count = g.countByPhase[e.phase - 1];
    for (let i = 0; i < count; i++) {
      const pt = findSpawnPoint(game, 14, g.minPlayerDist, { x: e.x, y: e.y, minR: e.r + g.minR, maxR: e.r + g.maxR });
      if (pt) queueSpawn(game, g.kind, pt.x, pt.y, { summoned: true });
    }
    e.shieldT = g.shieldMax;
    e.shielded = true;
    if (!e.jailerCalls) e.jailerCalls = {};
    e.jailerCalls[e.phase] = (e.jailerCalls[e.phase] ?? 0) + 1;
    emit(game, 'bossSummon', { id: e.id, x: e.x, y: e.y });
    emit(game, 'bossShield', { id: e.id, x: e.x, y: e.y, up: true });
    setSub(e, 'done');
  }
  toRest(game, e);
}

/** Bouclier de chaînes : tenu tant qu'un serviteur vit (et au plus shieldMax s). */
function tickShield(game, e, g, dt) {
  if (!e.shielded) return;
  e.shieldT -= dt;
  if (e.shieldT > 0 && summonedAlive(game) > 0) {
    e.invuln = Math.max(e.invuln, g.shieldHold);
    return;
  }
  e.shielded = false;
  e.shieldT = 0;
  e.invuln = 0;
  emit(game, 'bossShield', { id: e.id, x: e.x, y: e.y, up: false });
}

function tick(game, e, d, dt) {
  tickShield(game, e, d.geoliers, dt);
  tickPools(game, e, d.eboulis);
}

/**
 * Geôliers : au plus `callsPerPhase` appels par phase (sans quoi le bouclier se recyclerait dès
 * la chute des archers et le Colosse deviendrait un sac à PV), et jamais tant que des serviteurs
 * vivent ou que le bouclier tient.
 */
function available(game, e, d, name) {
  if (name !== 'geoliers') return true;
  const g = d.geoliers;
  const calls = e.jailerCalls?.[e.phase] ?? 0;
  return g.countByPhase[e.phase - 1] > 0 && calls < g.callsPerPhase && !e.shielded && summonedAlive(game) === 0;
}

/** Changement de phase : les braises s'éteignent (les zones viennent d'être effacées par le moteur). */
function onPhase(game, e) {
  e.pools = [];
}

// Poing, séisme et éboulis d'emblée ; les geôliers (et les braises) à partir de la phase 2.
export const COLOSSE = {
  byPhase: { 1: ['poing', 'seisme', 'eboulis'], 2: ['poing', 'seisme', 'eboulis', 'geoliers'], 3: ['poing', 'seisme', 'eboulis', 'geoliers'] },
  patterns: { poing, seisme, eboulis, geoliers },
  tick,
  available,
  onPhase,
};
