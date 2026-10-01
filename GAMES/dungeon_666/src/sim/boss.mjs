// Boss de fin de section : « Charon, le Passeur » (premier Gardien, à l'entrée des Limbes).
// Patterns enchaînés, chacun télégraphié :
//   slam   — trois impacts circulaires successifs, posés là où se trouve le héros
//   charge — ligne télégraphiée puis ruée ; s'il percute un mur, il reste sonné (punition)
//   ring   — anneaux de projectiles avec des brèches : lire, se placer, dasher à travers
//   summon — (phase 2) invoque des diablotins via des cercles d'invocation
// Trois phases (66 % et 33 % de PV) : plus de patterns et moins de pauses, jamais de
// télégraphe raccourci. Chaque transition : invulnérable 1,5 s, projectiles effacés, renforts.

import { rand, randRange, pick } from '../core/rng.mjs';
import { dist2 } from '../core/math.mjs';
import { emit } from './state.mjs';
import { moveCircle } from './physics.mjs';
import { damagePlayer, spawnHazard, spawnPickup } from './combat.mjs';
import { spawnProjectile } from './projectiles.mjs';
import { queueSpawn, findSpawnPoint } from './spawns.mjs';

// Patterns disponibles par phase : la charge arrive en phase 2, les invocations en phase 3.
const PATTERNS = { 1: ['slam', 'ring'], 2: ['slam', 'ring', 'charge'], 3: ['slam', 'ring', 'charge', 'summon'] };

function def(game, e) {
  return game.tuning.boss[e.kind];
}

function wmult() {
  return 1; // les télégraphes du boss ne raccourcissent jamais (équité, spec §4.1)
}

function toPlayer(game, e) {
  const p = game.player;
  const dx = p.x - e.x;
  const dy = p.y - e.y;
  const d = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy));
  return { dx: dx / d, dy: dy / d, d };
}

function setState(e, s) {
  e.state = s;
  e.stateTime = 0;
  e.patternStep = 0;
  e.patternT = 0;
}

function nextPattern(game, e) {
  const list = PATTERNS[e.phase];
  let choice = pick(game.rng.ai, list);
  // Jamais deux fois de suite le même pattern.
  for (let i = 0; i < 4 && choice === e.pattern; i++) choice = pick(game.rng.ai, list);
  e.pattern = choice;
  e.secondCharge = false;
  setState(e, choice);
}

/** Changement de phase : invulnérable un instant, projectiles effacés, renforts, orbe de soin. */
function enterPhase(game, e, d) {
  e.phase++;
  e.tele = null;
  e.invuln = d.transition;
  for (const pr of game.projectiles) if (pr.owner === 'enemy') pr.dead = true;
  for (const h of game.hazards) if (h.hitsPlayer) h.done = true;
  for (const kind of d.reinforcements[e.phase] ?? []) {
    const pt = findSpawnPoint(game, 14, 180, { x: e.x, y: e.y, minR: e.r + 60, maxR: e.r + 260 });
    if (pt) queueSpawn(game, kind, pt.x, pt.y, { summoned: true });
  }
  spawnPickup(game, 'heal', e.x, e.y + e.r + 30, d.phaseHealOrb);
  emit(game, 'bossPhase', { id: e.id, x: e.x, y: e.y, phase: e.phase });
  setState(e, 'roar');
  e.restFor = d.transition;
}

export function updateBoss(game, e, dt) {
  const d = def(game, e);
  e.invuln = Math.max(0, (e.invuln ?? 0) - dt);
  const threshold = e.phase === 1 ? d.phase2At : e.phase === 2 ? d.phase3At : -1;
  if (threshold > 0 && e.hp <= e.maxHp * threshold) {
    enterPhase(game, e, d);
    return;
  }
  const speed = d.speed * d.speedMultByPhase[e.phase - 1];
  switch (e.state) {
    case 'roar':
      if (e.stateTime >= e.restFor) {
        e.restFor = undefined;
        nextPattern(game, e);
      }
      break;
    case 'chase':
    case 'rest': {
      if (e.restFor === undefined) e.restFor = randRange(game.rng.ai, d.restBetween[0], d.restBetween[1]) * d.restMultByPhase[e.phase - 1];
      const tp = toPlayer(game, e);
      if (tp.d > 160) {
        e.vx = tp.dx * speed;
        e.vy = tp.dy * speed;
      }
      if (e.stateTime >= e.restFor) {
        e.restFor = undefined;
        nextPattern(game, e);
      }
      break;
    }
    case 'slam':
      slam(game, e, d, dt, speed);
      break;
    case 'charge':
      charge(game, e, d, dt);
      break;
    case 'ring':
      ring(game, e, d, dt);
      break;
    case 'summon':
      summon(game, e, d);
      break;
    case 'stunned':
      break;
    default:
      setState(e, 'rest');
  }
}

function toRest(game, e) {
  e.tele = null;
  setState(e, 'rest');
}

function slam(game, e, d, dt, speed) {
  const s = d.slam;
  const p = game.player;
  e.patternT -= dt;
  const tp = toPlayer(game, e);
  e.vx = tp.dx * speed * 0.5;
  e.vy = tp.dy * speed * 0.5;
  if (e.patternStep < s.count && e.patternT <= 0) {
    spawnHazard(game, {
      shape: 'circle', x: p.x, y: p.y, r: s.radius, delay: s.windup * wmult(),
      damage: s.damage * e.dmgScale, kind: 'bossSlam', sourceId: 0,
    });
    e.patternStep++;
    e.patternT = s.interval * wmult();
  }
  if (e.patternStep >= s.count && e.stateTime >= s.interval * s.count + s.windup) toRest(game, e);
}

function charge(game, e, d, dt) {
  const c = d.charge;
  const p = game.player;
  const windup = e.secondCharge ? d.secondChargeWindup : c.windup * wmult();
  if (e.patternStep === 0) {
    if (e.stateTime < windup * 0.7) {
      const tp = toPlayer(game, e);
      e.dirX = tp.dx;
      e.dirY = tp.dy;
    }
    e.tele = { shape: 'line', angle: Math.atan2(e.dirY, e.dirX), length: c.speed * c.maxTime, width: c.width, progress: e.stateTime / windup };
    if (e.stateTime >= windup) {
      e.tele = null;
      e.patternStep = 1;
      e.patternT = 0;
      e.hitPlayer = false;
      e.atkId = game.nextId++;
      emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: 'boss' });
    }
    return;
  }
  e.patternT += dt;
  const res = moveCircle(game.room, e, e.dirX * c.speed * dt, e.dirY * c.speed * dt);
  if (!e.hitPlayer && dist2(e.x, e.y, p.x, p.y) < (e.r + p.r + 4) ** 2) {
    e.hitPlayer = true;
    damagePlayer(game, c.damage * e.dmgScale, { kind: 'bossCharge', id: e.atkId, x: e.x, y: e.y });
  }
  if (res.hitWall) {
    e.stun = c.wallStun;
    e.state = 'stunned';
    e.stateTime = 0;
    game.telemetry.wallSlams++;
    emit(game, 'chargerWall', { id: e.id, x: e.x, y: e.y, boss: true });
  } else if (e.patternT >= c.maxTime) {
    if (e.phase === 3 && !e.secondCharge) {
      // Phase 3 : seconde traversée enchaînée, avec son propre télégraphe.
      e.secondCharge = true;
      setState(e, 'charge');
      return;
    }
    toRest(game, e);
  }
}

function ring(game, e, d, dt) {
  const r = d.ring;
  const windup = r.windup * wmult();
  if (e.patternStep === 0) {
    e.tele = { shape: 'circle', r: 90, progress: e.stateTime / windup };
    if (e.stateTime >= windup) {
      e.tele = null;
      e.patternStep = 1;
      e.patternT = 0;
    }
    return;
  }
  e.patternT -= dt;
  const waves = r.waves + (e.phase - 1);
  if (e.patternStep <= waves && e.patternT <= 0) {
    // Brèches contiguës à un angle aléatoire : il y a toujours un couloir sûr.
    const n = r.bullets;
    const gapStart = Math.floor(rand(game.rng.ai) * n);
    const offset = (e.patternStep % 2) * (Math.PI / n);
    for (let i = 0; i < n; i++) {
      const rel = (i - gapStart + n) % n;
      if (rel < r.gapCount) continue;
      const a = offset + (i / n) * Math.PI * 2;
      spawnProjectile(game, {
        owner: 'enemy', kind: 'bossOrb', x: e.x + Math.cos(a) * e.r, y: e.y + Math.sin(a) * e.r,
        vx: Math.cos(a) * r.speed, vy: Math.sin(a) * r.speed, r: r.radius, damage: r.damage * e.dmgScale, range: 1400, sourceId: e.id,
      });
    }
    emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: 'bossRing' });
    e.patternStep++;
    e.patternT = r.waveInterval;
  }
  if (e.patternStep > waves) toRest(game, e);
}

function summon(game, e, d) {
  const s = d.summon;
  if (e.patternStep === 0) {
    e.tele = { shape: 'circle', r: 70, progress: e.stateTime / s.windup };
    if (e.stateTime >= s.windup) {
      e.tele = null;
      for (let i = 0; i < s.count; i++) {
        const pt = findSpawnPoint(game, 14, 150, { x: e.x, y: e.y, minR: e.r + 40, maxR: e.r + 160 });
        if (pt) queueSpawn(game, s.kind, pt.x, pt.y, { summoned: true });
      }
      e.patternStep = 1;
      emit(game, 'bossSummon', { id: e.id, x: e.x, y: e.y });
    }
    return;
  }
  toRest(game, e);
}
