// Property-tests d'invariants pour sys-damage-floor (pat-damage-floor).
import { test } from "node:test";
import assert from "node:assert/strict";
import { effectiveDamage, applyHit } from "./damage_floor.mjs";

// RNG seedé injecté — le système sous test reste pur (aucun Math.random dedans).
function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

test("invariant 1 : degat effectif >= floor sur 5000 tirages", () => {
  const rnd = mulberry32(1234);
  for (let i = 0; i < 5000; i++) {
    const raw = Math.floor(rnd() * 50);
    const red = Math.floor(rnd() * 50);
    const floor = 1 + Math.floor(rnd() * 3);
    assert.ok(effectiveDamage(raw, red, floor) >= floor);
  }
});

test("invariant 2 : monotonie en rawDamage a reduction fixe", () => {
  const rnd = mulberry32(99);
  for (let i = 0; i < 2000; i++) {
    const red = Math.floor(rnd() * 20);
    const a = Math.floor(rnd() * 40);
    const b = a + Math.floor(rnd() * 20);
    assert.ok(effectiveDamage(b, red) >= effectiveDamage(a, red));
  }
});

test("invariant 3 : deterministe (memes entrees -> meme sortie)", () => {
  for (let i = 0; i < 100; i++) {
    assert.equal(effectiveDamage(37, 12, 1), effectiveDamage(37, 12, 1));
  }
});

test("cas limite : reduction >= rawDamage tombe sur le plancher, pas en dessous", () => {
  assert.equal(effectiveDamage(3, 100, 1), 1);
  assert.equal(effectiveDamage(3, 100, 2), 2);
});

test("applyHit borne hp a 0 et rapporte les degats", () => {
  assert.deepEqual(applyHit(5, 3, 0), { hp: 2, dealt: 3 });
  assert.deepEqual(applyHit(2, 10, 0), { hp: 0, dealt: 10 });
  assert.deepEqual(applyHit(2, 0, 100), { hp: 1, dealt: 1 }); // plancher garanti
});

test("entrees invalides -> RangeError (contrat defensif)", () => {
  assert.throws(() => effectiveDamage(-1, 0), RangeError);
  assert.throws(() => effectiveDamage(0, -1), RangeError);
  assert.throws(() => effectiveDamage(0, 0, 0), RangeError);
});
