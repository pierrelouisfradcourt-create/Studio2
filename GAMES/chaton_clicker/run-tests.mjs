#!/usr/bin/env node

import { GameState } from './src/logic.mjs';
import assert from 'assert';

const tests = [];
let passed = 0;
let failed = 0;

function test(name, fn) {
  tests.push({ name, fn });
}

async function runTests() {
  console.log('LOGIC UNIT TESTS');
  console.log('='.repeat(60));

  for (const t of tests) {
    try {
      await t.fn();
      console.log(`✓ ${t.name}`);
      passed++;
    } catch (err) {
      console.error(`✗ ${t.name}`);
      console.error(`  ${err.message}`);
      failed++;
    }
  }

  console.log('='.repeat(60));
  console.log(`Results: ${passed} passed, ${failed} failed`);
  return failed === 0;
}

test('P02 gain: ronrons augmente apres caresse', () => {
  const state = new GameState(42);
  const before = state.ronrons;
  state.caresser();
  assert(state.ronrons > before, 'ronrons should increase after caresser');
});

test('P04: producteur not affordable at 5 ronrons', () => {
  const state = new GameState(42);
  state.ronrons = 5;
  assert(!state.producteurAbordable(0), 'producteur not affordable at 5 ronrons');
});

test('P04: producteur affordable at 10 ronrons', () => {
  const state = new GameState(42);
  state.ronrons = 10;
  assert(state.producteurAbordable(0), 'producteur should be affordable at 10 ronrons');
});

test('P06 effet: tick augmente ronrons apres achat', () => {
  const state = new GameState(42);
  state.ronrons = 15;
  state.acheterProducteur(0);
  const before = state.ronrons;
  state.tick();
  assert(state.ronrons > before, 'ronrons should increase from tick');
});

test('P12: cout producteur croissant', () => {
  const state = new GameState(42);
  state.ronrons = 200;
  const cost1 = state.producteurs[0].cost;
  state.acheterProducteur(0);
  const cost2 = state.producteurs[0].cost;
  assert(cost2 > cost1, 'cost should increase after purchase');
});

test('P05: divergence politique actif vs passif', () => {
  const state = new GameState(42);
  const result = state.comparerPolitiques(300);
  assert(result.diff > 0, 'actif should outpace passif');
  assert(result.actif > result.passif, 'active policy should have more ronrons');
});

test('P07: texte objectif initial', () => {
  const state = new GameState(42);
  const obj = state.objectifCourant();
  assert(obj.includes('Caresse'), 'initial objective should mention caresse');
});

test('P07: texte objectif apres 1er achat', () => {
  const state = new GameState(42);
  state.ronrons = 15;
  state.acheterProducteur(0);
  const obj = state.objectifCourant();
  assert(!obj.includes('Caresse'), 'objective after purchase should differ');
});

test('P08: 3e texte objectif apres 2 achats', () => {
  const state = new GameState(42);
  state.ronrons = 100;
  state.acheterProducteur(0);
  state.ronrons = 50;
  state.acheterProducteur(1);
  const obj = state.objectifCourant();
  assert(obj.includes('prestige'), 'objective after 2nd purchase should mention prestige');
});

test('P09: rejeu boucle enrichi', () => {
  const state = new GameState(42);
  state.ronrons = 15;
  state.acheterProducteur(0);
  const result = state.rejouerBoucle(50);
  assert(result.ronrons_apres > 0, 'ronrons should increase in replay');
  assert(result.producteurs_achetes >= 0, 'should track purchases');
});

test('P10 effet: renouveauPortee reset ronrons', () => {
  const state = new GameState(42);
  state.ronrons = 100;
  state.renouveauPortee();
  assert.strictEqual(state.ronrons, 0, 'ronrons should reset after renouveau');
});

test('P11: gain apres renouveau > gain avant', () => {
  const state = new GameState(42);
  const gain_before = state.gainParCaresse;
  state.ronrons = 100;
  state.renouveauPortee();
  const gain_after = state.gainParCaresse;
  assert(gain_after > gain_before, 'gain should increase after renouveau');
});

test('P13: determinisme par graine et suite egales', () => {
  const state1 = new GameState(42);
  const state2 = new GameState(42);

  for (let i = 0; i < 10; i++) {
    state1.caresser();
    state2.caresser();
  }
  state1.acheterProducteur(0);
  state2.acheterProducteur(0);

  assert.strictEqual(state1.hashEtat(), state2.hashEtat(), 'same seed and actions => same hash');
});

runTests().then(success => {
  if (success) {
    console.log('\n✓ LOGIC TESTS PASS');
    process.exit(0);
  } else {
    console.log('\n✗ LOGIC TESTS FAIL');
    process.exit(1);
  }
});
