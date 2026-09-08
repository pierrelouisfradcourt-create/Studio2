// Tests de propriétés — invariants tenus sur de longues séquences et plusieurs seeds.
// Complète logic.test.mjs : ici on vérifie une propriété qui doit rester vraie pendant
// toute une partie, pas un seul cas.
import { test } from 'node:test';
import assert from 'node:assert';

import { GameState } from './logic.mjs';

const SEEDS = [1, 2, 3, 4, 5, 6, 7, 8];
const TICKS_PAR_SEED = 500;

/** Bot de suivi simple : caresse si rien n'est abordable, achète sinon. */
function politiqueGourmande(state) {
  for (let idx = state.producteurs.length - 1; idx >= 0; idx--) {
    if (state.producteurAbordable(idx)) {
      state.acheterProducteur(idx);
      return;
    }
  }
  state.caresser();
}

test('ronrons ne devient jamais négatif, quelle que soit la seed', () => {
  for (const seed of SEEDS) {
    const state = new GameState(seed);
    for (let i = 0; i < TICKS_PAR_SEED; i++) {
      politiqueGourmande(state);
      state.tick();
      assert.ok(state.ronrons >= 0, `seed ${seed} tick ${i}: ronrons négatif`);
    }
  }
});

test('le coût d\'un producteur ne décroît jamais après un achat', () => {
  for (const seed of SEEDS) {
    const state = new GameState(seed);
    const derniersCouts = state.producteurs.map((_, idx) => state.coutProducteur(idx));
    for (let i = 0; i < TICKS_PAR_SEED; i++) {
      politiqueGourmande(state);
      state.tick();
      state.producteurs.forEach((_, idx) => {
        const cout = state.coutProducteur(idx);
        assert.ok(cout >= derniersCouts[idx], `seed ${seed}: coût producteur ${idx} a régressé`);
        derniersCouts[idx] = cout;
      });
    }
  }
});

test('renouveauPortee ne fait jamais reculer prestige ni gainParCaresse', () => {
  for (const seed of SEEDS) {
    const state = new GameState(seed);
    let prestigeAvant = state.prestige;
    let gainAvant = state.gainParCaresse;
    for (let i = 0; i < TICKS_PAR_SEED; i++) {
      politiqueGourmande(state);
      state.tick();
      if (state.ronrons > 200 && i % 47 === 0) {
        state.renouveauPortee();
        assert.ok(state.prestige >= prestigeAvant, `seed ${seed}: prestige a reculé`);
        assert.ok(state.gainParCaresse >= gainAvant, `seed ${seed}: gainParCaresse a reculé`);
        assert.strictEqual(state.ronrons, 0, `seed ${seed}: ronrons non remis à zéro`);
        prestigeAvant = state.prestige;
        gainAvant = state.gainParCaresse;
      }
    }
  }
});

test('objectifCourant retourne toujours une chaîne non vide', () => {
  for (const seed of SEEDS) {
    const state = new GameState(seed);
    for (let i = 0; i < 100; i++) {
      politiqueGourmande(state);
      state.tick();
      const obj = state.objectifCourant();
      assert.strictEqual(typeof obj, 'string');
      assert.ok(obj.length > 0, `seed ${seed}: objectif vide au tick ${i}`);
    }
  }
});

test('identique seed + suite d\'actions => trajectoire de hash identique', () => {
  for (const seed of SEEDS) {
    const jouer = () => {
      const state = new GameState(seed);
      const hashes = [];
      for (let i = 0; i < 200; i++) {
        politiqueGourmande(state);
        state.tick();
        hashes.push(state.hashEtat());
      }
      return hashes;
    };
    assert.deepStrictEqual(jouer(), jouer(), `seed ${seed}: divergence de trajectoire`);
  }
});

test('une politique active accumule strictement plus qu\'une politique passive, sur chaque seed', () => {
  for (const seed of SEEDS) {
    const state = new GameState(seed);
    const { diff } = state.comparerPolitiques(300);
    assert.ok(diff > 0, `seed ${seed}: la politique active ne dépasse pas la passive`);
  }
});
