// properties.test.mjs — property-based checks across many seeds + seeded input traces.
// Run: node --test properties.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CollectRunnerGame, generateLevels, makeRng, TOTAL_LEVELS } from './game.mjs';

const SEED_COUNT = 40;
const TICKS_PER_TRACE = 400; // 400 * 25ms = 10s of simulated play per seed
const TICK_MS = 25;

/** Build a deterministic input trace for a given seed: a sequence of {left,right,jump}. */
function buildInputTrace(seed, length) {
  const rng = makeRng(seed * 7919 + 13); // distinct stream from the level-gen RNG
  const trace = [];
  for (let i = 0; i < length; i++) {
    const r = rng();
    trace.push({
      left: r < 0.15,
      right: r >= 0.15 && r < 0.75, // right-biased: needs speed to clear obstacles/finish
      jump: rng() < 0.35,
    });
  }
  return trace;
}

function totalCoinsFor(seed) {
  const levels = generateLevels(seed);
  return levels.reduce((sum, lvl) => sum + lvl.coins.length, 0);
}

function runTrace(seed, trace) {
  const g = new CollectRunnerGame({ seed });
  const history = [];
  for (const input of trace) {
    g.step(TICK_MS, input);
    history.push(g.view());
  }
  return history;
}

for (let s = 1; s <= SEED_COUNT; s++) {
  const seed = s * 101 + 3; // spread seeds out, avoid trivially small numbers

  test(`seed ${seed}: determinism — same seed + same input trace => identical trace`, () => {
    const trace = buildInputTrace(seed, TICKS_PER_TRACE);
    const h1 = runTrace(seed, trace);
    const h2 = runTrace(seed, trace);
    assert.deepEqual(h1, h2, `seed ${seed} produced divergent traces on repeat`);
  });

  test(`seed ${seed}: bounds — coins/level/x/y stay within valid ranges`, () => {
    const trace = buildInputTrace(seed, TICKS_PER_TRACE);
    const totalCoins = totalCoinsFor(seed);
    const history = runTrace(seed, trace);
    for (const v of history) {
      assert.ok(v.coins >= 0, `coins went negative: ${v.coins}`);
      assert.ok(v.coins <= totalCoins, `coins ${v.coins} exceeded total ${totalCoins}`);
      assert.ok(v.level >= 0 && v.level < TOTAL_LEVELS, `level ${v.level} out of range`);
      assert.ok(v.x >= 0, `x went negative: ${v.x}`);
      assert.ok(v.y <= 1e-9, `y went positive (below ground): ${v.y}`);
      assert.ok(v.won ? v.over : true, `won=true must imply over=true`);
    }
  });

  test(`seed ${seed}: coins are monotonically non-decreasing over time`, () => {
    const trace = buildInputTrace(seed, TICKS_PER_TRACE);
    const history = runTrace(seed, trace);
    let prev = 0;
    for (const v of history) {
      assert.ok(v.coins >= prev, `coins decreased from ${prev} to ${v.coins}`);
      prev = v.coins;
    }
  });

  test(`seed ${seed}: defeat/victory is monotone (over never flips back to false)`, () => {
    const trace = buildInputTrace(seed, TICKS_PER_TRACE);
    const history = runTrace(seed, trace);
    let sawOver = false;
    for (const v of history) {
      if (sawOver) assert.equal(v.over, true, 'over flipped back to false after being true');
      if (v.over) sawOver = true;
    }
  });
}

test('different seeds produce different level layouts (not all identical)', () => {
  const layouts = [];
  for (let s = 1; s <= SEED_COUNT; s++) {
    const seed = s * 101 + 3;
    layouts.push(JSON.stringify(generateLevels(seed)[0].obstacles));
  }
  const distinct = new Set(layouts);
  assert.ok(distinct.size > 1, 'all 40 seeds produced an identical level 0 layout');
});
