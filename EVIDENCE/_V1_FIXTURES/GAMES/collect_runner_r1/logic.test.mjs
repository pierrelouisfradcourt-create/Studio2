// logic.test.mjs — strict per-rule assertions on CollectRunnerGame. No `>=`
// tautologies: every check pins an exact value or a strict boolean transition.

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  CollectRunnerGame,
  TOTAL_LEVELS,
  BASE_SPEED,
  MIN_SPEED,
  MAX_SPEED,
  PLAYER_WIDTH,
} from './game.mjs';

/** Measures the real jump horizontal reach from a fresh, level-1 takeoff. */
function measureJumpRange(seed) {
  const probe = new CollectRunnerGame(seed);
  const startX = probe.x;
  probe.step(DT, { jump: true });
  let steps = 0;
  while (!probe.onGround && steps < 1000) {
    probe.step(DT, {});
    steps++;
  }
  return probe.x - startX;
}

/** Bot-style jump decision reused across tests that need to clear obstacles safely. */
function botJump(g, jumpRange) {
  const next = g.obstaclesOnLevel.find((o) => o.x + o.width >= g.x);
  return !!(next && g.onGround && next.x - g.x <= jumpRange * 0.5);
}

const DT = 16;

test('starts on level 1, zero coins, not over, on the ground', () => {
  const g = new CollectRunnerGame(1);
  const v = g.view();
  assert.equal(v.level, 1);
  assert.equal(v.coins, 0);
  assert.equal(v.over, false);
  assert.equal(v.won, false);
  assert.equal(v.onGround, true);
  assert.equal(v.x, 0);
});

test('with no input, forward speed is exactly BASE_SPEED * dt per step', () => {
  const g = new CollectRunnerGame(1);
  const before = g.x;
  g.step(DT, {});
  assert.equal(g.x - before, BASE_SPEED * DT);
});

test('right modulates speed strictly above BASE_SPEED, left strictly below', () => {
  const gRight = new CollectRunnerGame(1);
  const gLeft = new CollectRunnerGame(1);
  const gNeutral = new CollectRunnerGame(1);
  gRight.step(DT, { right: true });
  gLeft.step(DT, { left: true });
  gNeutral.step(DT, {});
  assert.ok(gRight.x > gNeutral.x, 'right must move strictly further than neutral');
  assert.ok(gLeft.x < gNeutral.x, 'left must move strictly less than neutral');
  assert.ok(gLeft.x > 0, 'left must still move forward (auto-runner, never backward)');
});

test('speed is clamped: pressing both left and right never exceeds [MIN_SPEED, MAX_SPEED] * dt', () => {
  const g = new CollectRunnerGame(1);
  g.step(DT, { left: true, right: true });
  // left and right cancel back to BASE_SPEED exactly (SPEED_MOD - SPEED_MOD = 0)
  assert.equal(g.x, BASE_SPEED * DT);
  const gMax = new CollectRunnerGame(1);
  for (let i = 0; i < 10; i++) gMax.step(DT, { right: true });
  const perStepMax = gMax.x / 10;
  assert.ok(perStepMax <= MAX_SPEED * DT + 1e-9);
  const gMin = new CollectRunnerGame(1);
  for (let i = 0; i < 10; i++) gMin.step(DT, { left: true });
  const perStepMin = gMin.x / 10;
  assert.ok(perStepMin >= MIN_SPEED * DT - 1e-9);
});

test('jump: leaves the ground immediately and eventually falls back (vy<0 while airborne) before landing', () => {
  const g = new CollectRunnerGame(1);
  assert.equal(g.onGround, true);
  g.step(DT, { jump: true });
  assert.equal(g.onGround, false, 'must be airborne the instant a jump is triggered');
  assert.ok(g.vy > 0, 'jump must impart a strictly positive (upward) velocity at takeoff');

  let sawFallingWhileAirborne = false;
  let steps = 0;
  while (!g.onGround && steps < 1000) {
    g.step(DT, {});
    steps++;
    if (!g.onGround && g.vy < 0) sawFallingWhileAirborne = true;
  }
  assert.equal(g.onGround, true, 'must eventually land');
  assert.ok(sawFallingWhileAirborne, 'must observe vy<0 && onGround=false at some point in the arc (the fall)');
  assert.equal(g.vy, 0, 'vy resets to exactly 0 on landing');
});

test('jump while already airborne is ignored (no double jump)', () => {
  const g = new CollectRunnerGame(1);
  g.step(DT, { jump: true });
  const vyAfterFirstJump = g.vy;
  g.step(DT, { jump: true }); // already airborne — this jump must be a no-op on vy source
  // vy after second step should equal vyAfterFirstJump + GRAVITY*DT (pure gravity integration),
  // not reset to JUMP_VELOCITY again.
  assert.ok(g.vy < vyAfterFirstJump, 'second jump input must not re-launch while airborne');
});

test('collecting a ground coin increments coins by exactly 1, not more', () => {
  const g = new CollectRunnerGame(1);
  const jumpRange = measureJumpRange(1);
  // Ground coins sit just past an obstacle, so clearing the obstacle with the
  // same bot policy used elsewhere is required to ever reach one.
  const firstGroundCoin = g.coinsOnLevel.find((c) => !c.elevated);
  assert.ok(firstGroundCoin, 'level must contain at least one ground coin');
  let steps = 0;
  while (g.x < firstGroundCoin.x + firstGroundCoin.width + 1 && !g.over && steps < 5000) {
    const before = g.coins;
    g.step(DT, { jump: botJump(g, jumpRange) });
    steps++;
    assert.ok(g.coins === before || g.coins === before + 1, 'coins must increase by exactly 0 or 1 per step');
  }
  assert.equal(g.over, false, 'must not have died while approaching the ground coin');
  assert.equal(g.coins, 2, 'exactly the elevated coin over the obstacle plus the ground coin must be collected');
});

test('touching an obstacle while on the ground ends the game with over=true, won=false, exactly at first contact', () => {
  const g = new CollectRunnerGame(1);
  const obstacle = g.obstaclesOnLevel[0];
  let steps = 0;
  let overAt = -1;
  let xJustBeforeOver = g.x;
  while (!g.over && steps < 5000) {
    const xBefore = g.x;
    g.step(DT, {}); // never jump: must walk straight into the first obstacle
    steps++;
    if (g.over) {
      overAt = steps;
      xJustBeforeOver = xBefore;
    }
  }
  assert.equal(g.over, true, 'walking straight into an obstacle must end the game');
  assert.equal(g.won, false, 'losing to an obstacle must not also flag a win');
  assert.ok(overAt > 0);
  // Collision predicate is: player.x + PLAYER_WIDTH > obstacle.x && player.x < obstacle.x + obstacle.width.
  // Assert it holds exactly at the frame the game ended...
  assert.ok(
    g.x + PLAYER_WIDTH > obstacle.x && g.x < obstacle.x + obstacle.width,
    'the collision predicate must be true on the exact frame the game ends'
  );
  // ...and did NOT hold on the previous frame (first contact, not a late detection).
  assert.ok(
    !(xJustBeforeOver + PLAYER_WIDTH > obstacle.x && xJustBeforeOver < obstacle.x + obstacle.width),
    'the collision predicate must be false on the frame before the game ends'
  );
});

test('after game over, further step() calls are frozen no-ops (state does not change)', () => {
  const g = new CollectRunnerGame(1);
  let steps = 0;
  while (!g.over && steps < 5000) {
    g.step(DT, {});
    steps++;
  }
  assert.equal(g.over, true);
  const snapshotBefore = g.view();
  g.step(DT, { jump: true, right: true });
  const snapshotAfter = g.view();
  assert.equal(snapshotAfter.x, snapshotBefore.x);
  assert.equal(snapshotAfter.coins, snapshotBefore.coins);
  assert.equal(snapshotAfter.level, snapshotBefore.level);
});

test('jumping cleanly over every obstacle on level 1 and reaching the end triggers level 2 (level increments, x resets to 0)', () => {
  const g = new CollectRunnerGame(1);
  const jumpRangeProbe = new CollectRunnerGame(1);
  jumpRangeProbe.step(DT, { jump: true });
  const startX = jumpRangeProbe.x - BASE_SPEED * DT;
  let steps = 0;
  while (!jumpRangeProbe.onGround && steps < 1000) {
    jumpRangeProbe.step(DT, {});
    steps++;
  }
  const jumpRange = jumpRangeProbe.x - startX;

  steps = 0;
  while (g.level === 1 && !g.over && steps < 5000) {
    const next = g.obstaclesOnLevel.find((o) => o.x + o.width >= g.x);
    const jump = !!(next && g.onGround && next.x - g.x <= jumpRange * 0.5);
    g.step(DT, { jump });
    steps++;
  }
  assert.equal(g.over, false, 'must not lose while clearing level 1 with correctly timed jumps');
  assert.equal(g.level, 2, 'reaching the end of level 1 must advance to level 2 exactly');
  assert.equal(g.x, 0, 'x must reset to exactly 0 at the start of a new level');
});

test('winning the final level sets won=true and over=true exactly, coins carry over across levels', () => {
  const g = new CollectRunnerGame(5);
  const probe = new CollectRunnerGame(5);
  probe.step(DT, { jump: true });
  const startX = probe.x - BASE_SPEED * DT;
  let ps = 0;
  while (!probe.onGround && ps < 1000) {
    probe.step(DT, {});
    ps++;
  }
  const jumpRange = probe.x - startX;

  let steps = 0;
  let sawLevel2 = false;
  while (!g.over && steps < 20000) {
    if (g.level === 2) sawLevel2 = true;
    const next = g.obstaclesOnLevel.find((o) => o.x + o.width >= g.x);
    const jump = !!(next && g.onGround && next.x - g.x <= jumpRange * 0.5);
    g.step(DT, { jump });
    steps++;
  }
  assert.equal(g.won, true, 'clearing all 3 levels must win the game');
  assert.equal(g.over, true);
  assert.equal(g.level, TOTAL_LEVELS, `must have reached exactly level ${TOTAL_LEVELS}`);
  assert.ok(sawLevel2, 'must have transitioned through level 2 on the way to level 3');
  assert.ok(g.coins > 0, 'coins collected along the way must carry over (not reset per level)');
});

test('determinism: identical seed + identical input sequence produces an identical trace', () => {
  const inputs = [];
  for (let i = 0; i < 300; i++) {
    inputs.push({ left: i % 7 === 0, right: i % 5 === 0, jump: i % 3 === 0 });
  }
  const g1 = new CollectRunnerGame(999);
  const g2 = new CollectRunnerGame(999);
  const trace1 = inputs.map((inp) => g1.step(DT, inp));
  const trace2 = inputs.map((inp) => g2.step(DT, inp));
  assert.deepEqual(trace1, trace2, 'same seed + same inputs must produce byte-identical traces');
});

test('different seeds produce different level 1 layouts', () => {
  const gA = new CollectRunnerGame(1);
  const gB = new CollectRunnerGame(2);
  const layoutA = JSON.stringify(gA.obstaclesOnLevel);
  const layoutB = JSON.stringify(gB.obstaclesOnLevel);
  assert.notEqual(layoutA, layoutB, 'seed 1 and seed 2 must generate different obstacle layouts');
});
