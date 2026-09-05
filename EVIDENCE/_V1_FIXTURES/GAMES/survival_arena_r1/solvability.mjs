#!/usr/bin/env node
// solvability.mjs -- black-box PLAYABILITY oracle.
//
// Proves, by actually PLAYING the game through step()/view() only (never by
// poking internals or forcing state), that the core mechanics work in real
// play, not just in isolated unit tests:
//   (a) auto-fire actually kills enemies during real play (kills > 0)
//   (b) enemies actually pursue the player (distance strictly decreases)
//   (c) death is reachable through real mechanics (no debug hook)
//   (d) an active (move + kite) bot survives at least as long, and on
//       balance strictly longer, than a passive (do-nothing) bot
// Exit 0 only if ALL properties hold; exit 1 with a diagnostic otherwise.

import { SurvivalGame } from './game.mjs';

const DT_MS = 50;

function report(name, ok, detail) {
  console.log(`[${ok ? 'PASS' : 'FAIL'}] ${name} -- ${detail}`);
  return ok;
}

// ---------------------------------------------------------------------------
// (a) auto-fire kills enemies in real play (passive bot, no movement at all).
// ---------------------------------------------------------------------------
function checkAutoFireKills() {
  const g = new SurvivalGame(1234);
  const MAX_STEPS = 20000; // up to 1000s of game time
  for (let i = 0; i < MAX_STEPS; i++) {
    const v = g.step(DT_MS, {});
    if (v.killCount > 0) {
      return report('auto-fire kills enemies', true, `killCount=${v.killCount}, score=${v.score} reached at t=${v.time.toFixed(0)}ms`);
    }
    if (v.over) break;
  }
  return report('auto-fire kills enemies', false, 'killCount never exceeded 0 within the sampled window');
}

// ---------------------------------------------------------------------------
// (b) enemies pursue the player: distance from a *specific* enemy (tracked by
// id across consecutive frames, to avoid conflating "nearest enemy" churn
// from kills/spawns) to the player strictly decreases while the player holds
// still -- isolating enemy AI from any player-side movement.
// ---------------------------------------------------------------------------
function checkPursuit() {
  const g = new SurvivalGame(555);
  let prevView = g.view();
  let samples = 0;
  for (let i = 0; i < 2000; i++) {
    const v = g.step(DT_MS, {});
    if (prevView.enemies.length > 0 && v.enemies.length > 0) {
      const prevById = new Map(prevView.enemies.map((e) => [e.id, e]));
      for (const e of v.enemies) {
        const before = prevById.get(e.id);
        if (!before) continue; // this enemy didn't exist last frame, skip
        const distBefore = Math.hypot(before.x - prevView.player.x, before.y - prevView.player.y);
        const distAfter = Math.hypot(e.x - v.player.x, e.y - v.player.y);
        samples++;
        if (distAfter < distBefore) {
          return report(
            'enemies pursue the player',
            true,
            `enemy id=${e.id} distance ${distBefore.toFixed(2)}px -> ${distAfter.toFixed(2)}px (sample #${samples})`
          );
        }
      }
    }
    if (v.over) break;
    prevView = v;
  }
  return report('enemies pursue the player', false, `no strict distance decrease observed across ${samples} same-enemy frame pairs`);
}

// ---------------------------------------------------------------------------
// (c) death is reachable through real mechanics: a passive bot that never
// dodges and is never propped up by a debug hook must eventually lose.
// ---------------------------------------------------------------------------
function checkDeathReachable() {
  const g = new SurvivalGame(4242);
  const MAX_STEPS = 40000; // up to 2000s of game time
  for (let i = 0; i < MAX_STEPS; i++) {
    const v = g.step(DT_MS, {});
    if (v.over) {
      return report('death is reachable via real play', true, `over=true at t=${v.time.toFixed(0)}ms, hp=${v.hp}, score=${v.score}`);
    }
  }
  return report('death is reachable via real play', false, `game never ended within ${MAX_STEPS} steps of passive play`);
}

// ---------------------------------------------------------------------------
// (d) active bot: flee directly away from the nearest enemy every frame.
// Auto-fire is engine-driven regardless of movement, so this isolates the
// value of movement/kiting specifically.
// ---------------------------------------------------------------------------
function fleeInput(view) {
  if (view.enemies.length === 0) return {};
  let nearest = view.enemies[0];
  let bestDist = Math.hypot(nearest.x - view.player.x, nearest.y - view.player.y);
  for (const e of view.enemies) {
    const d = Math.hypot(e.x - view.player.x, e.y - view.player.y);
    if (d < bestDist) {
      bestDist = d;
      nearest = e;
    }
  }
  const dx = view.player.x - nearest.x;
  const dy = view.player.y - nearest.y;
  return { left: dx < 0, right: dx > 0, up: dy < 0, down: dy > 0 };
}

function passiveInput() {
  return {};
}

function survivalTime(seed, botFn, capMs) {
  const g = new SurvivalGame(seed);
  let v = g.view();
  while (v.time < capMs) {
    v = g.step(DT_MS, botFn(v));
    if (v.over) return v.time;
  }
  return v.time; // reached the cap while still alive -- counts as "survived the cap"
}

function checkActiveBeatsPassive() {
  const CAP_MS = 300000; // 300s cap per run
  const SEEDS = [1, 2, 3, 4, 5];
  let wins = 0;
  let ties = 0;
  let regressions = 0;
  const detail = [];
  for (const seed of SEEDS) {
    const passive = survivalTime(seed, passiveInput, CAP_MS);
    const active = survivalTime(seed, fleeInput, CAP_MS);
    detail.push(`seed${seed}[passive=${passive.toFixed(0)}ms active=${active.toFixed(0)}ms]`);
    if (active > passive) wins++;
    else if (active === passive) ties++;
    else regressions++;
  }
  const ok = wins >= Math.ceil(SEEDS.length / 2) && regressions === 0;
  return report(
    'active (kiting) bot survives longer than passive bot',
    ok,
    `${wins} win / ${ties} tie / ${regressions} regression across ${SEEDS.length} seeds -- ${detail.join(', ')}`
  );
}

// ---------------------------------------------------------------------------
const results = [checkAutoFireKills(), checkPursuit(), checkDeathReachable(), checkActiveBeatsPassive()];

const allPass = results.every(Boolean);
console.log(allPass ? '\nSOLVABILITY: ALL PROPERTIES HOLD' : '\nSOLVABILITY: FAILED');
process.exit(allPass ? 0 : 1);
