// Point d'entrée de la simulation. Déterministe : même graine + mêmes InputFrames
// => même partie, à l'octet près. Aucune dépendance au DOM, à l'horloge ou à Math.random.
//
//   const game = createGame({ seed });
//   stepGame(game, inputFrame);   // un pas fixe de 1/60 s
//   applyCommand(game, {type: 'choose', index: 0});   // menus (bénédiction, butin…)
//   game.events                   // événements de l'image, à vider par l'appelant

import { createRng, hashSeed } from '../core/rng.mjs';
import { dist2 } from '../core/math.mjs';
import { DT, createTuning } from './config.mjs';
import { createPlayer, createTelemetry, emit } from './state.mjs';
import { readInput, updatePlayer, canDash } from './player.mjs';
import { updateEnemies } from './enemies.mjs';
import { updateNav } from './nav.mjs';
import { updateProjectiles, updateHazards, compact } from './projectiles.mjs';
import { updateSpawns, updateWaves, doorTouched, refillSandboxWaves } from './room.mjs';
import { createRun, enterFloor, onRoomClear, openInteract, applyCommand as runCommand } from './run.mjs';
import { recomputeStats } from './stats.mjs';
import { moveCircle } from './physics.mjs';
import { healPlayer } from './combat.mjs';
import { starterItems } from './loot.mjs';

export { DT };
export const DEATH_DELAY = 1.4; // s de ralenti/agonie avant l'écran de mort

export function emptyInput() {
  return {
    moveX: 0, moveY: 0, aimX: 0, aimY: 0,
    attack: false, attackPressed: false, dashPressed: false,
    skillPressed: false, skillAimX: 0, skillAimY: 0,
    gadgetPressed: false, superPressed: false,
  };
}

/**
 * options : { seed, tuning (surcharges partielles), startFloor, meta, godMode, items, sandbox }
 * meta    : progression persistante {checkpoints: [1, ...], bestFloor}
 */
export function createGame(options = {}) {
  const seed = (options.seed ?? 1) >>> 0;
  const tuning = createTuning(options.tuning);
  const meta = options.meta ? structuredClone(options.meta) : { checkpoints: [1], bestFloor: 1, snapshots: {} };
  meta.snapshots = meta.snapshots ?? {};
  if (!meta.checkpoints?.length) meta.checkpoints = [1];
  const game = {
    seed,
    tuning,
    tick: 0,
    time: 0,
    rng: {
      gen: createRng(hashSeed(seed, 1)),
      combat: createRng(hashSeed(seed, 2)),
      ai: createRng(hashSeed(seed, 3)),
    },
    mode: 'play', // play | choice | dead | victory
    choice: null,
    hitstop: 0,
    hitstopBank: tuning.hitstopBank.max,
    deathT: 0,
    godMode: !!options.godMode,
    sandbox: !!options.sandbox, // arène d'essai : vagues sans fin, ni portes ni récompenses
    nextId: 1,
    events: [],
    telemetry: createTelemetry(),
    meta,
    run: createRun(options.startFloor ?? 1),
    player: null,
    room: null,
    info: null,
    enemies: [],
    projectiles: [],
    hazards: [],
    pickups: [],
    spawns: [],
  };
  game.player = createPlayer(tuning, 0, 0);
  Object.assign(game.run.items, starterItems(game), options.items ?? {});
  recomputeStats(game);
  game.player.hp = game.player.maxHp;
  enterFloor(game, options.startFloor ?? 1, { reward: 'boon', family: 'colere' });
  return game;
}

export function stepGame(game, input) {
  if (game.mode !== 'play') return;
  const dt = DT;
  game.tick++;
  const dashWanted = readInput(game, input ?? emptyInput());
  if (game.hitstop > 0) {
    // Le dash interrompt le gel d'impact : la réactivité passe avant l'emphase.
    if (dashWanted && game.tuning.dash.cancelsHitstop && canDash(game)) {
      game.hitstop = 0;
    } else {
      game.hitstop = Math.max(0, game.hitstop - dt);
      return;
    }
  }
  game.time += dt;
  const hb = game.tuning.hitstopBank;
  game.hitstopBank = Math.min(hb.max, game.hitstopBank + hb.refill * dt);
  updatePlayer(game, dt);
  updateNav(game);
  updateEnemies(game, dt);
  updateProjectiles(game, dt);
  updateHazards(game, dt);
  updateSpawns(game, dt);
  updatePickups(game, dt);
  compact(game.enemies);
  updateFlow(game, dt);
}

function updatePickups(game, dt) {
  const p = game.player;
  const t = game.tuning.room;
  const friction = Math.exp(-6 * dt);
  for (const pk of game.pickups) {
    pk.age += dt;
    const d2 = dist2(pk.x, pk.y, p.x, p.y);
    const settle = pk.age > 0.35;
    if (settle && p.state !== 'dead' && d2 < t.pickupMagnetRange * t.pickupMagnetRange) {
      const d = Math.sqrt(d2) || 1;
      pk.vx = ((p.x - pk.x) / d) * t.pickupMagnetSpeed;
      pk.vy = ((p.y - pk.y) / d) * t.pickupMagnetSpeed;
    } else {
      pk.vx *= friction;
      pk.vy *= friction;
    }
    moveCircle(game.room, pk, pk.vx * dt, pk.vy * dt);
    if (settle && p.state !== 'dead' && d2 < (p.r + pk.r) ** 2) {
      pk.dead = true;
      if (pk.kind === 'gold') {
        game.run.gold += pk.value;
        emit(game, 'pickup', { kind: 'gold', x: pk.x, y: pk.y, amount: pk.value });
      } else if (pk.kind === 'heal') {
        healPlayer(game, pk.value, true);
        emit(game, 'pickup', { kind: 'heal', x: pk.x, y: pk.y, amount: pk.value });
      }
    }
  }
  compact(game.pickups);
}

function updateFlow(game, dt) {
  const p = game.player;
  const room = game.room;
  if (p.state === 'dead') {
    game.deathT += dt;
    if (game.deathT >= DEATH_DELAY) {
      game.mode = 'dead';
      emit(game, 'gameOver', { floor: game.run.floor });
    }
    return;
  }
  if (updateWaves(game)) {
    if (game.sandbox) refillSandboxWaves(game);
    else onRoomClear(game);
  }
  if (game.mode !== 'play') return;
  const it = room.interact;
  if (it && !it.used && dist2(p.x, p.y, it.x, it.y) < (p.r + it.r) ** 2) openInteract(game);
  if (game.mode !== 'play') return;
  const door = doorTouched(game);
  if (door >= 0) {
    const chosen = room.doors[door];
    enterFloor(game, game.run.floor + 1, chosen);
  }
}

export function applyCommand(game, cmd) {
  return runCommand(game, cmd);
}

/** Empreinte compacte de l'état (tests de déterminisme). */
export function stateHash(game) {
  const p = game.player;
  let h = 2166136261;
  const mix = (v) => {
    const x = Math.round(v * 1000) | 0;
    h = Math.imul(h ^ x, 16777619) >>> 0;
  };
  mix(game.tick);
  mix(game.time);
  mix(game.rng.gen.s);
  mix(game.rng.combat.s);
  mix(game.rng.ai.s);
  mix(game.run.boons.length);
  mix(game.hitstop);
  mix(p.x);
  mix(p.y);
  mix(p.hp);
  mix(game.run.floor);
  mix(game.run.gold);
  for (const e of game.enemies) {
    mix(e.id);
    mix(e.x);
    mix(e.y);
    mix(e.hp);
  }
  for (const pr of game.projectiles) {
    mix(pr.x);
    mix(pr.y);
  }
  return h >>> 0;
}
