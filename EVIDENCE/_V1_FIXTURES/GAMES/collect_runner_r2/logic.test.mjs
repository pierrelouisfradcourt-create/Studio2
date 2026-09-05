// logic.test.mjs — strict unit tests for game.mjs. One assertion per observable rule.
// Run: node --test logic.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  CollectRunnerGame,
  generateLevels,
  BASE_SPEED,
  LEFT_MULT,
  RIGHT_MULT,
} from './game.mjs';

const NO_INPUT = { left: false, right: false, jump: false };
const EPS = 0.02;

function closeTo(actual, expected, eps, msg) {
  assert.ok(Math.abs(actual - expected) <= eps, `${msg}: expected ~${expected}, got ${actual}`);
}

test('initial state is exact and clean', () => {
  const g = new CollectRunnerGame({ seed: 1 });
  assert.equal(g.x, 0);
  assert.equal(g.y, 0);
  assert.equal(g.vy, 0);
  assert.equal(g.level, 0);
  assert.equal(g.coins, 0);
  assert.equal(g.over, false);
  assert.equal(g.won, false);
  assert.equal(g.onGround, true);
});

test('no input moves forward at exactly BASE_SPEED', () => {
  const g = new CollectRunnerGame({ seed: 1 });
  g.step(1000, NO_INPUT);
  closeTo(g.x, BASE_SPEED, EPS, 'x after 1s neutral input');
});

test('left-only input moves forward at exactly BASE_SPEED * LEFT_MULT', () => {
  const g = new CollectRunnerGame({ seed: 1 });
  g.step(1000, { left: true, right: false, jump: false });
  closeTo(g.x, BASE_SPEED * LEFT_MULT, EPS, 'x after 1s left');
});

test('right-only input moves forward at exactly BASE_SPEED * RIGHT_MULT', () => {
  const g = new CollectRunnerGame({ seed: 1 });
  g.step(1000, { left: false, right: true, jump: false });
  closeTo(g.x, BASE_SPEED * RIGHT_MULT, EPS, 'x after 1s right');
});

test('left+right together cancel out to BASE_SPEED (neutral)', () => {
  const g = new CollectRunnerGame({ seed: 1 });
  g.step(1000, { left: true, right: true, jump: false });
  closeTo(g.x, BASE_SPEED, EPS, 'x after 1s left+right');
});

test('jump from ground: vy strictly negative and onGround strictly false', () => {
  const g = new CollectRunnerGame({ seed: 1 });
  g.step(20, { left: false, right: false, jump: true });
  assert.ok(g.vy < 0, `vy should be negative after jump, got ${g.vy}`);
  assert.equal(g.onGround, false);
});

test('holding jump mid-air does not trigger a second jump (no double jump)', () => {
  const g = new CollectRunnerGame({ seed: 1 });
  g.step(20, { left: false, right: false, jump: true });
  const vyAfterFirstJump = g.vy;
  g.step(20, { left: false, right: false, jump: true }); // still airborne, jump held
  // vy should have continued to integrate gravity (increase), not been reset to JUMP_VY again
  assert.ok(g.vy > vyAfterFirstJump, 'vy should be rising toward 0 from gravity, not reset');
});

test('after a full jump arc (0.7s) the player lands back at y=0, vy=0, onGround=true', () => {
  const g = new CollectRunnerGame({ seed: 1 });
  g.step(20, { left: false, right: false, jump: true });
  // total air time is 0.7s; we already consumed 20ms, drive the rest in 20ms substeps
  let elapsed = 20;
  while (elapsed < 760) {
    g.step(20, NO_INPUT);
    elapsed += 20;
  }
  assert.equal(g.onGround, true);
  closeTo(g.y, 0, 1e-6, 'y should be exactly 0 on landing');
  closeTo(g.vy, 0, 1e-6, 'vy should be exactly 0 on landing');
});

test('walking into the first obstacle without jumping causes defeat, no coin', () => {
  const g = new CollectRunnerGame({ seed: 1 });
  const firstObstacleX = g.levels[0].obstacles[0].x;
  // run neutral speed until we would reach/pass the obstacle
  const totalMs = ((firstObstacleX + 50) / BASE_SPEED) * 1000;
  let elapsed = 0;
  while (elapsed < totalMs && !g.over) {
    g.step(20, NO_INPUT);
    elapsed += 20;
  }
  assert.equal(g.over, true);
  assert.equal(g.won, false);
  assert.equal(g.coins, 0);
});

test('jumping over the first obstacle at the right time collects exactly 1 coin', () => {
  const g = new CollectRunnerGame({ seed: 1 });
  const firstObstacleX = g.levels[0].obstacles[0].x;
  const input = { left: false, right: true, jump: false };
  const speed = BASE_SPEED * RIGHT_MULT;
  const jumpAtMs = ((firstObstacleX - 60) / speed) * 1000;
  let elapsed = 0;
  let jumped = false;
  while (elapsed < 3000 && !g.over && g.coins < 1) {
    const doJump = !jumped && elapsed >= jumpAtMs;
    if (doJump) jumped = true;
    g.step(20, { ...input, jump: doJump });
    elapsed += 20;
  }
  assert.equal(g.over, false, 'should not have collided');
  assert.equal(g.coins, 1, 'should have collected exactly 1 coin, not more or less');
});

test('a fresh instance with a different seed produces a different level layout', () => {
  const a = generateLevels(1);
  const b = generateLevels(2);
  assert.notDeepEqual(a[0].obstacles, b[0].obstacles);
});

test('same seed produces the same level layout every time (deterministic generation)', () => {
  const a = generateLevels(42);
  const b = generateLevels(42);
  assert.deepEqual(a, b);
});

test('state is frozen after game over: further step() calls are no-ops', () => {
  const g = new CollectRunnerGame({ seed: 1 });
  const firstObstacleX = g.levels[0].obstacles[0].x;
  const totalMs = ((firstObstacleX + 50) / BASE_SPEED) * 1000;
  let elapsed = 0;
  while (elapsed < totalMs && !g.over) {
    g.step(20, NO_INPUT);
    elapsed += 20;
  }
  assert.equal(g.over, true);
  const snapshot = g.view();
  g.step(1000, { left: false, right: true, jump: true });
  assert.deepEqual(g.view(), snapshot);
});

test('a large dtMs in a single step() call does not tunnel through the first obstacle', () => {
  const g = new CollectRunnerGame({ seed: 1 });
  const firstObstacleX = g.levels[0].obstacles[0].x;
  // one giant step that would, without substepping, jump straight past the obstacle
  const bigMs = ((firstObstacleX + 200) / BASE_SPEED) * 1000;
  g.step(bigMs, NO_INPUT);
  assert.equal(g.over, true, 'the obstacle must still be detected despite the large dt');
});
