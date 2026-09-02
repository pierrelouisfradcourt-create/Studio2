// Tests deterministes de input (preuve `test` : core.error_handling ; couvre aussi
// input.action). Entrees hors domaine -> etat toujours valide (error.guard).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { translate, dirFor, clampPaddle } from '../../05_SYSTEMS/input/input.mjs';
import { boot, step } from '../../05_SYSTEMS/game_loop/loop.mjs';
import { isValidState } from '../../05_SYSTEMS/game_state/state.mjs';

test('translate : entree brute totalement invalide -> action neutre', () => {
  for (const bad of [null, undefined, 42, 'x', true, NaN, []]) {
    assert.deepEqual(translate(bad), { p1: 0, p2: 0 });
  }
});

test('translate : chaines up/down', () => {
  assert.deepEqual(translate({ p1: 'up', p2: 'down' }), { p1: -1, p2: 1 });
  assert.deepEqual(translate({ p1: 'gauche', p2: '' }), { p1: 0, p2: 0 });
});

test('translate : objets up/down, simultane NEUTRALISE', () => {
  assert.equal(translate({ p1: { up: true } }).p1, -1);
  assert.equal(translate({ p1: { down: true } }).p1, 1);
  assert.equal(translate({ p1: { up: true, down: true } }).p1, 0); // tue &&/|| et simultane
  assert.equal(translate({ p1: {} }).p1, 0);
});

test('dirFor : vocabulaire ferme', () => {
  assert.equal(dirFor('up'), -1);
  assert.equal(dirFor('down'), 1);
  assert.equal(dirFor(null), 0);
  assert.equal(dirFor(999), 0);
});

test('clampPaddle : borne aux extremes, invariant a l interieur', () => {
  assert.equal(clampPaddle(-5, 0, 96), 0);    // sous le min
  assert.equal(clampPaddle(200, 0, 96), 96);  // au-dessus du max
  assert.equal(clampPaddle(50, 0, 96), 50);   // a l interieur
  assert.equal(clampPaddle(0, 0, 96), 0);     // borne exacte
  assert.equal(clampPaddle(96, 0, 96), 96);   // borne exacte
});

// --- Renforcement mutation (gate) ---
// dirFor ligne 19 `raw.up === true || raw[UP] === true` : un objet declarant
// EXPLICITEMENT up=false ne doit PAS monter (tue les deux true->false L19 : passer a
// `=== false` ferait de {up:false} un up presse).
test('dirFor : up=false explicite -> immobile (true->false L19)', () => {
  assert.equal(translate({ p1: { up: false } }).p1, 0);
  assert.equal(dirFor({ up: false }), 0);
});

// dirFor ligne 20 `raw.down === true || raw[DOWN] === true` : down=false explicite ne
// doit PAS descendre (tue les deux true->false L20).
test('dirFor : down=false explicite -> immobile (true->false L20)', () => {
  assert.equal(translate({ p1: { down: false } }).p1, 0);
  assert.equal(dirFor({ down: false }), 0);
});

test('error.guard : rafale d entrees hostiles -> etat TOUJOURS valide', () => {
  let s = boot(1);
  const hostiles = [
    null, undefined, {}, { p1: 'BOOM' }, { p1: { up: true, down: true } },
    { p1: 'up', p2: 'up' }, { p1: 'down', p2: 'down' }, 42, 'garbage',
    { p1: { up: true }, p2: { down: true } },
  ];
  for (let i = 0; i < 500; i += 1) {
    const raw = hostiles[i % hostiles.length];
    s = step(s, translate(raw)).state;
    assert.equal(isValidState(s), true, `etat invalide au tick ${i}`);
  }
});
