// properties.test.mjs — invariants checked across ~40 seeds with seeded-random
// input sequences: determinism, arena containment, monotonic coins, monotonic
// (never-un-ending) game-over, and layout diversity across seeds.

import test from 'node:test';
import assert from 'node:assert/strict';
import { CollectRunnerGame, TOTAL_LEVELS } from './game.mjs';

const DT = 16;
const SEED_COUNT = 40;
const STEPS_PER_RUN = 400;

// Small seeded RNG dedicated to *test input generation* (kept separate from
// the engine's own RNG so the test never depends on game.mjs internals).
function testRng(seed) {
  let x = (seed >>> 0) || 1;
  return function next() {
    x ^= x << 13; x >>>= 0;
    x ^= x >>> 17;
    x ^= x << 5; x >>>= 0;
    return x / 4294967296;
  };
}

function randomInputSequence(seed, count) {
  const rng = testRng(seed * 7919 + 3);
  const inputs = [];
  for (let i = 0; i < count; i++) {
    inputs.push({
      left: rng() < 0.2,
      right: rng() < 0.2,
      jump: rng() < 0.35,
    });
  }
  return inputs;
}

test('for ~40 seeds: same seed + same random input sequence => identical trace (determinism)', () => {
  for (let seed = 1; seed <= SEED_COUNT; seed++) {
    const inputs = randomInputSequence(seed, STEPS_PER_RUN);
    const g1 = new CollectRunnerGame(seed);
    const g2 = new CollectRunnerGame(seed);
    const trace1 = inputs.map((inp) => g1.step(DT, inp));
    const trace2 = inputs.map((inp) => g2.step(DT, inp));
    assert.deepEqual(trace1, trace2, `determinism violated for seed ${seed}`);
  }
});

test('for ~40 seeds: player x always stays within [0, levelLength] and y never goes negative', () => {
  for (let seed = 1; seed <= SEED_COUNT; seed++) {
    const inputs = randomInputSequence(seed, STEPS_PER_RUN);
    const g = new CollectRunnerGame(seed);
    for (const inp of inputs) {
      g.step(DT, inp);
      assert.ok(g.x >= 0, `seed ${seed}: x went negative (${g.x})`);
      assert.ok(
        g.x <= g.levelLength + 1e-6 || g.over,
        `seed ${seed}: x (${g.x}) exceeded levelLength (${g.levelLength}) without ending the game`
      );
      assert.ok(g.y >= 0, `seed ${seed}: y went negative (${g.y})`);
      if (g.over) break;
    }
  }
});

test('for ~40 seeds: coins counter is monotonically non-decreasing and never resets mid-run', () => {
  for (let seed = 1; seed <= SEED_COUNT; seed++) {
    const inputs = randomInputSequence(seed, STEPS_PER_RUN);
    const g = new CollectRunnerGame(seed);
    let previousCoins = 0;
    for (const inp of inputs) {
      g.step(DT, inp);
      assert.ok(g.coins >= previousCoins, `seed ${seed}: coins decreased (${previousCoins} -> ${g.coins})`);
      previousCoins = g.coins;
      if (g.over) break;
    }
  }
});

test('for ~40 seeds: once over is true it stays true forever after (monotonic, never reverses)', () => {
  for (let seed = 1; seed <= SEED_COUNT; seed++) {
    const inputs = randomInputSequence(seed, STEPS_PER_RUN * 3);
    const g = new CollectRunnerGame(seed);
    let becameOverAt = -1;
    for (let i = 0; i < inputs.length; i++) {
      g.step(DT, inputs[i]);
      if (g.over && becameOverAt === -1) becameOverAt = i;
      if (becameOverAt !== -1) {
        assert.equal(g.over, true, `seed ${seed}: over flipped back to false at step ${i}`);
      }
    }
  }
});

test('for ~40 seeds: level never exceeds TOTAL_LEVELS and only increases', () => {
  for (let seed = 1; seed <= SEED_COUNT; seed++) {
    const inputs = randomInputSequence(seed, STEPS_PER_RUN * 3);
    const g = new CollectRunnerGame(seed);
    let previousLevel = g.level;
    for (const inp of inputs) {
      g.step(DT, inp);
      assert.ok(g.level >= previousLevel, `seed ${seed}: level decreased`);
      assert.ok(g.level <= TOTAL_LEVELS, `seed ${seed}: level ${g.level} exceeds TOTAL_LEVELS`);
      previousLevel = g.level;
      if (g.over) break;
    }
  }
});

test('different seeds produce different level layouts across a wide sample (not all identical)', () => {
  const layouts = new Set();
  for (let seed = 1; seed <= SEED_COUNT; seed++) {
    const g = new CollectRunnerGame(seed);
    layouts.add(JSON.stringify(g.obstaclesOnLevel) + '|' + JSON.stringify(g.coinsOnLevel));
  }
  assert.ok(layouts.size > 1, 'expected varied layouts across seeds, got only one distinct layout');
  // Require meaningful diversity, not just one outlier among 40 identical seeds.
  assert.ok(layouts.size >= SEED_COUNT * 0.5, `expected at least half the seeds to differ, got ${layouts.size}/${SEED_COUNT} distinct layouts`);
});
