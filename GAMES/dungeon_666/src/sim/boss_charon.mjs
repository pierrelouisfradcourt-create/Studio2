// Gardien « Charon, le Passeur » (modèle `gardien`, section 1 puis en rotation).
// Patterns enchaînés, chacun télégraphié :
//   slam   — trois impacts circulaires successifs, posés là où se trouve le héros
//   charge — ligne télégraphiée puis ruée ; s'il percute un mur, il reste sonné (punition)
//   ring   — anneaux de projectiles avec des brèches : lire, se placer, dasher à travers
//   summon — (phase 3) invoque des diablotins via des cercles d'invocation (alerte inoffensive)

import { rand } from '../core/rng.mjs';
import { dist2 } from '../core/math.mjs';
import { emit } from './state.mjs';
import { moveCircle } from './physics.mjs';
import { damagePlayer, spawnHazard } from './combat.mjs';
import { spawnProjectile } from './projectiles.mjs';
import { queueSpawn, findSpawnPoint } from './spawns.mjs';
import { wmult, toPlayer, setState, toRest } from './boss_common.mjs';

const CHARGE_HIT_PAD = 4; // u ajoutés au contact boss/héros pendant la charge

export function slam(game, e, d, dt, speed) {
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

export function charge(game, e, d, dt) {
  const c = d.charge;
  const p = game.player;
  const windup = e.secondCharge ? d.secondChargeWindup : c.windup * wmult();
  if (e.patternStep === 0) {
    if (e.stateTime < windup * 0.7) {
      const tp = toPlayer(game, e);
      e.dirX = tp.dx;
      e.dirY = tp.dy;
    }
    // Largeur = zone qui touche réellement (rayon du boss + marge du test de contact) : esquiver
    // « au pixel » le bord rouge doit toujours suffire.
    e.tele = { shape: 'line', angle: Math.atan2(e.dirY, e.dirX), length: c.speed * c.maxTime, width: Math.max(c.width, 2 * (e.r + CHARGE_HIT_PAD)), progress: e.stateTime / windup };
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
  if (!e.hitPlayer && dist2(e.x, e.y, p.x, p.y) < (e.r + p.r + CHARGE_HIT_PAD) ** 2) {
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

export function ring(game, e, d, dt) {
  const r = d.ring;
  const windup = r.windup * wmult();
  if (e.patternStep === 0) {
    e.tele = { shape: 'circle', r: r.teleRadius, progress: e.stateTime / windup };
    if (e.stateTime >= windup) {
      e.tele = null;
      e.patternStep = 1;
      e.patternT = 0;
    }
    return;
  }
  e.patternT -= dt;
  const waves = r.waves + (e.phase - 1);
  // Salve en cours : le cercle d'alerte reste affiché et se remplit avant chaque vague, pour
  // qu'on ne revienne pas au contact sous le tir suivant.
  if (e.patternStep <= waves) e.tele = { shape: 'circle', r: r.teleRadius, progress: 1 - Math.max(0, e.patternT) / r.waveInterval };
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

export function summon(game, e, d) {
  const s = d.summon;
  if (e.patternStep === 0) {
    // Invocation : alerte inoffensive, dessinée autrement que le rouge « ça fait mal ».
    e.tele = { shape: 'circle', r: 70, progress: e.stateTime / s.windup, harmless: true };
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

// Patterns disponibles par phase : la charge arrive en phase 2, les invocations en phase 3.
export const CHARON = {
  byPhase: { 1: ['slam', 'ring'], 2: ['slam', 'ring', 'charge'], 3: ['slam', 'ring', 'charge', 'summon'] },
  patterns: { slam, charge, ring, summon },
};
