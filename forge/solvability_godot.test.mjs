import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runSolvability } from './solvability_godot.mjs';

test('tous les essais gagnes -> verdict OK', () => {
  const fakeTrial = () => ({ succeeded: true, ticks: 4 });
  const r = runSolvability({ trials: 5, seed_start: 1 }, fakeTrial);
  assert.equal(r.verdict, 'OK');
  assert.equal(r.won, 5);
  assert.deepEqual(r.failed_seeds, []);
});

test('un seul essai perdu -> verdict FAIL et le seed est nomme', () => {
  const fakeTrial = (seed) => ({ succeeded: seed !== 3, ticks: 4 });
  const r = runSolvability({ trials: 5, seed_start: 1 }, fakeTrial);
  assert.equal(r.verdict, 'FAIL');
  assert.deepEqual(r.failed_seeds, [3]);
});

test('une exception de trial -> BLOCKED, jamais un faux vert', () => {
  const fakeTrial = () => { throw new Error('Godot exit 1'); };
  const r = runSolvability({ trials: 3, seed_start: 1 }, fakeTrial);
  assert.equal(r.verdict, 'BLOCKED');
});

test('trials=0 -> BLOCKED (aucune preuve n est pas une preuve)', () => {
  const r = runSolvability({ trials: 0, seed_start: 1 }, () => ({ succeeded: true, ticks: 1 }));
  assert.equal(r.verdict, 'BLOCKED');
});
