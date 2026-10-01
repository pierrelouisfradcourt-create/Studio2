// SUPERS autres que la Colère, joués selon `kind`. player.mjs garde l'état 'super' (le héros
// y est invulnérable : combat.mjs), la durée, la locomotion et la fin ; ce module ne fait que
// le « tic » propre au Super :
//   sentence — Sentence (Bourreau) : exécutions auto-visées à des instants fixes du Super
//   nuee     — Nuée de traits (Chasseresse) : un trait toutes les `interval` s sur les ennemis
//              les plus proches, en rotation
// Les dégâts portent la source 'super' (ils ne rechargent pas la jauge ; « Gloire charnelle »
// s'y applique).

import * as TRIG from '../core/trig.mjs'; // sinus, cosinus… déterministes : jamais Math.sin & co dans la simulation
import { DEG } from './config.mjs';
import { emit } from './state.mjs';
import { computeAim } from './aim.mjs';
import { lineOfSight } from './physics.mjs';
import { dist2 } from '../core/math.mjs';
import { hitSector } from './kit_common.mjs';
import { spawnShot } from './kit_shots.mjs';

export function startKitSuper(game) {
  const p = game.player;
  p.superClock = 0;
  p.superStep = 0;
  p.superShotT = 0;
  p.superRot = 0;
}

export function tickKitSuper(game, dt, s) {
  const p = game.player;
  p.superClock += dt;
  if (s.kind === 'sentence') sentence(game, s);
  else if (s.kind === 'nuee') nuee(game, dt, s);
}

function sentence(game, s) {
  const p = game.player;
  while (p.superStep < s.strikes.length && p.superClock >= s.strikes[p.superStep].at) {
    const st = s.strikes[p.superStep];
    p.superStep++;
    const aim = computeAim(game, p.manualAimX, p.manualAimY, s.aimRange);
    const angle = TRIG.atan2(aim.y, aim.x);
    p.facing = angle;
    hitSector(game, p.x, p.y, st.range, angle, st.arc * DEG, {
      kind: 'super', amount: st.damage, knockback: st.knockback, stun: st.stun ?? 0, hitstop: st.hitstop, canCrit: true, shake: st.shake,
    });
    emit(game, 'superTick', { x: p.x, y: p.y, r: st.range, super: 'sentence', angle, arc: st.arc * DEG, step: p.superStep });
  }
}

/** Les `n` ennemis visibles les plus proches à portée, du plus proche au plus lointain. */
function nearestTargets(game, range, n) {
  const p = game.player;
  const list = [];
  for (const e of game.enemies) {
    if (e.dead || e.spawnT > 0) continue;
    const d2 = dist2(p.x, p.y, e.x, e.y);
    const reach = range + e.r;
    if (d2 > reach * reach) continue;
    if (!lineOfSight(game.room, p.x, p.y, e.x, e.y)) continue;
    list.push({ e, d2 });
  }
  list.sort((a, b) => a.d2 - b.d2 || a.e.id - b.e.id);
  return list.slice(0, n);
}

function nuee(game, dt, s) {
  const p = game.player;
  p.superShotT -= dt;
  if (p.superShotT > 0) return;
  p.superShotT += s.interval;
  const targets = nearestTargets(game, s.range, s.targets);
  if (targets.length === 0) return;
  const e = targets[p.superRot % targets.length].e;
  p.superRot++;
  const dx = e.x - p.x;
  const dy = e.y - p.y;
  const l = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy));
  spawnShot(game, {
    kind: 'star', x: p.x, y: p.y, vx: (dx / l) * s.speed, vy: (dy / l) * s.speed, r: s.shotRadius, range: s.range,
    pierce: s.pierce, damage: s.damage, source: 'super', knockback: s.knockback, hitstop: s.hitstop, heavy: false,
  });
  emit(game, 'superTick', { x: p.x, y: p.y, r: s.shotRadius, super: 'nuee', angle: TRIG.atan2(dy, dx) });
}
