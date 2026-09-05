// Property-based testing (homegrown, sans dépendance) : au lieu de cas à seed fixe,
// on vérifie des INVARIANTS sur 40 seeds + des séquences d'inputs aléatoires seedées
// (donc reproductibles). C'est la classe de tests que le red-team a montrée absente :
// elle attrape les bugs que les exemples ponctuels ratent.
import test from "node:test";
import assert from "node:assert";
import { CollectRunnerGame } from "./game.mjs";

// Générateur seedé (LCG) -> "aléatoire" mais 100% reproductible.
function lcg(seed) {
  let s = (seed >>> 0) || 1;
  return () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296;
}

const SEEDS = Array.from({ length: 40 }, (_, i) => i * 7 + 1);

test("propriété: déterminisme sur 40 seeds (même seed + mêmes inputs => trace identique)", () => {
  for (const seed of SEEDS) {
    const a = new CollectRunnerGame({ seed });
    const b = new CollectRunnerGame({ seed });
    for (let i = 0; i < 200; i++) {
      const inp = { right: i % 3 === 0, left: i % 7 === 0, jump: i % 5 === 0 };
      a.step(16, inp);
      b.step(16, inp);
    }
    assert.deepStrictEqual(a.view(), b.view(), `seed ${seed} non déterministe`);
  }
});

test("propriété: le joueur reste dans l'arène pour TOUTE séquence d'inputs", () => {
  for (const seed of SEEDS) {
    const g = new CollectRunnerGame({ seed });
    const rnd = lcg(seed);
    for (let i = 0; i < 400; i++) {
      g.step(16, { left: rnd() < 0.3, right: rnd() < 0.5, jump: rnd() < 0.2 });
      assert.ok(g.player.x >= 0 && g.player.x <= g.width,
        `x=${g.player.x} hors [0,${g.width}] seed ${seed} step ${i}`);
    }
  }
});

test("propriété: le compteur de pièces ne DÉCROÎT jamais", () => {
  for (const seed of SEEDS) {
    const g = new CollectRunnerGame({ seed });
    const rnd = lcg(seed + 99);
    let prev = 0;
    for (let i = 0; i < 400; i++) {
      g.step(16, { right: true, jump: rnd() < 0.3 });
      assert.ok(g.coins >= prev, `coins a baissé (${prev}->${g.coins}) seed ${seed}`);
      prev = g.coins;
    }
  }
});

test("propriété: la défaite est monotone (une fois over, reste over)", () => {
  for (const seed of SEEDS) {
    const g = new CollectRunnerGame({ seed });
    let wasOver = false;
    for (let i = 0; i < 500; i++) {
      g.step(16, { right: true });
      if (g.over) wasOver = true;
      if (wasOver) assert.ok(g.over, `over est redevenu false seed ${seed} step ${i}`);
    }
  }
});
