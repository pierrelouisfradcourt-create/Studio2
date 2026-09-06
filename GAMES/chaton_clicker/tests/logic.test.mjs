import { GameState } from '../src/logic.mjs';
import assert from 'assert';

describe('logic.mjs', () => {
  describe('R3: caresser', () => {
    it('P02 gain: ronrons augmente apres caresse', () => {
      const state = new GameState(42);
      const before = state.ronrons;
      state.caresser();
      assert(state.ronrons > before, 'ronrons should increase after caresser');
    });
  });

  describe('R5: producteurAbordable', () => {
    it('P04: faux tant que ronrons < cout', () => {
      const state = new GameState(42);
      state.ronrons = 5;
      assert(!state.producteurAbordable(0), 'producteur not affordable at 5 ronrons (cost 10)');
    });

    it('P04: vrai des que ronrons >= cout', () => {
      const state = new GameState(42);
      state.ronrons = 10;
      assert(state.producteurAbordable(0), 'producteur should be affordable at 10 ronrons');
    });
  });

  describe('R7: tick', () => {
    it('P06 effet: apres achat, tick augmente ronrons sans caresse', () => {
      const state = new GameState(42);
      state.ronrons = 15;
      state.acheterProducteur(0);
      const before = state.ronrons;
      state.tick();
      assert(state.ronrons > before, 'ronrons should increase from tick');
    });
  });

  describe('R8: coutProducteur', () => {
    it('P12: cout(n+1) > cout(n)', () => {
      const state = new GameState(42);
      state.ronrons = 200;
      const cost1 = state.producteurs[0].cost;
      state.acheterProducteur(0);
      const cost2 = state.producteurs[0].cost;
      assert(cost2 > cost1, 'cost should increase after purchase');
    });
  });

  describe('R9: comparerPolitiques', () => {
    it('P05: divergence entre passif et actif sur 300 frames', () => {
      const state = new GameState(42);
      const result = state.comparerPolitiques(300);
      assert(result.diff > 0, 'actif should outpace passif');
      assert(result.actif > result.passif, 'active policy should have more ronrons');
    });
  });

  describe('R10-R11: objectifCourant', () => {
    it('P07: texte initial', () => {
      const state = new GameState(42);
      const obj = state.objectifCourant();
      assert(obj.includes('Caresse'), 'initial objective should mention caresse');
    });

    it('P07: texte apres 1er achat', () => {
      const state = new GameState(42);
      state.ronrons = 15;
      state.acheterProducteur(0);
      const obj = state.objectifCourant();
      assert(!obj.includes('Caresse'), 'objective after purchase should differ');
    });

    it('P08: 3e texte apres 2e achat', () => {
      const state = new GameState(42);
      state.ronrons = 100;
      state.acheterProducteur(0);
      state.ronrons = 50;
      state.acheterProducteur(1);
      const obj = state.objectifCourant();
      assert(obj.includes('prestige'), 'objective after 2nd purchase should mention prestige');
    });
  });

  describe('R12: rejouerBoucle', () => {
    it('P09: rejeu dans etat enrichi', () => {
      const state = new GameState(42);
      state.ronrons = 15;
      state.acheterProducteur(0);
      const result = state.rejouerBoucle(50);
      assert(result.ronrons_apres > 0, 'ronrons should increase in replay');
      assert(result.producteurs_achetes >= 0, 'should track purchases');
    });
  });

  describe('R14: renouveauPortee', () => {
    it('P10 effet: ronrons == 0 apres renouveau', () => {
      const state = new GameState(42);
      state.ronrons = 100;
      state.renouveauPortee();
      assert.strictEqual(state.ronrons, 0, 'ronrons should reset after renouveau');
    });
  });

  describe('R15: gainParCaresse', () => {
    it('P11: gain apres renouveau > gain avant', () => {
      const state = new GameState(42);
      const gain_before = state.gainParCaresse;
      state.ronrons = 100;
      state.renouveauPortee();
      const gain_after = state.gainParCaresse;
      assert(gain_after > gain_before, 'gain should increase after renouveau');
    });
  });

  describe('R16: hashEtat', () => {
    it('P13: determinisme par graine et suite egales', () => {
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
  });
});
