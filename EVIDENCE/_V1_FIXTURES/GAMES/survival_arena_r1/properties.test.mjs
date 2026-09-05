// properties.test.mjs -- property-based checks across ~40 seeds with seeded
// (non-random-at-test-time) input sequences. Verifies invariants that must
// hold for ANY seed: determinism, arena bounds, hp bounds, monotonic `over`
// and monotonic `score`.
// Run with: node --test properties.test.mjs

import test from 'node:test';
import assert from 'node:assert/strict';
import { SurvivalGame, ARENA_WIDTH, ARENA_HEIGHT, PLAYER_RADIUS, PLAYER_MAX_HP } from './game.mjs';

const SEED_COUNT = 40;
const STEPS = 400;
const DT_MS = 33; // ~30fps

// Small deterministic LCG used ONLY to generate input sequences for the test
// itself (not part of the engine) -- keeps the whole test fully reproducible.
function lcg(seed) {
  let s = seed >>> 0;
  return function next() {
    s = (Math.imul(s, 1103515245) + 12345) >>> 0;
    return s / 4294967296;
  };
}

function buildInputSequence(seed, steps) {
  const rand = lcg(seed * 7919 + 13);
  const seq = [];
  for (let i = 0; i < steps; i++) {
    seq.push({
      up: rand() < 0.25,
      down: rand() < 0.25,
      left: rand() < 0.25,
      right: rand() < 0.25,
    });
  }
  return seq;
}

function runTrace(seed, inputs) {
  const g = new SurvivalGame(seed);
  const trace = [];
  for (const input of inputs) {
    trace.push(g.step(DT_MS, input));
  }
  return trace;
}

test('determinism: identical seed + identical input sequence => byte-identical trace', () => {
  for (let seed = 1; seed <= SEED_COUNT; seed++) {
    const inputs = buildInputSequence(seed, STEPS);
    const traceA = runTrace(seed, inputs);
    const traceB = runTrace(seed, inputs);
    assert.deepEqual(traceA, traceB, `seed ${seed}: two runs with identical inputs must match exactly`);
  }
});

test('player position always stays within arena bounds (accounting for radius)', () => {
  for (let seed = 1; seed <= SEED_COUNT; seed++) {
    const inputs = buildInputSequence(seed, STEPS);
    const trace = runTrace(seed, inputs);
    for (const v of trace) {
      assert.ok(v.player.x >= PLAYER_RADIUS - 1e-9, `seed ${seed}: player.x below left wall`);
      assert.ok(v.player.x <= ARENA_WIDTH - PLAYER_RADIUS + 1e-9, `seed ${seed}: player.x past right wall`);
      assert.ok(v.player.y >= PLAYER_RADIUS - 1e-9, `seed ${seed}: player.y above top wall`);
      assert.ok(v.player.y <= ARENA_HEIGHT - PLAYER_RADIUS + 1e-9, `seed ${seed}: player.y past bottom wall`);
    }
  }
});

test('hp is never negative and never exceeds PLAYER_MAX_HP', () => {
  for (let seed = 1; seed <= SEED_COUNT; seed++) {
    const inputs = buildInputSequence(seed, STEPS);
    const trace = runTrace(seed, inputs);
    for (const v of trace) {
      assert.ok(v.hp >= 0, `seed ${seed}: hp went negative (${v.hp})`);
      assert.ok(v.hp <= PLAYER_MAX_HP, `seed ${seed}: hp exceeded max (${v.hp})`);
    }
  }
});

test('`over` is monotone: once true, stays true for the rest of the run', () => {
  for (let seed = 1; seed <= SEED_COUNT; seed++) {
    const inputs = buildInputSequence(seed, STEPS);
    const trace = runTrace(seed, inputs);
    let seenOver = false;
    for (const v of trace) {
      if (seenOver) {
        assert.equal(v.over, true, `seed ${seed}: over flipped back to false`);
      }
      if (v.over) seenOver = true;
    }
  }
});

test('score is monotone non-decreasing across a run (never loses points)', () => {
  for (let seed = 1; seed <= SEED_COUNT; seed++) {
    const inputs = buildInputSequence(seed, STEPS);
    const trace = runTrace(seed, inputs);
    let prev = 0;
    for (const v of trace) {
      assert.ok(v.score >= prev, `seed ${seed}: score decreased (${prev} -> ${v.score})`);
      prev = v.score;
    }
  }
});

test('killCount and score stay consistent: score === killCount * SCORE_PER_KILL', () => {
  for (let seed = 1; seed <= SEED_COUNT; seed++) {
    const inputs = buildInputSequence(seed, STEPS);
    const trace = runTrace(seed, inputs);
    for (const v of trace) {
      assert.equal(v.score, v.killCount * 10, `seed ${seed}: score/killCount mismatch`);
    }
  }
});
