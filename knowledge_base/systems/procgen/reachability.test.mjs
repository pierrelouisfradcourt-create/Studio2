// Property-tests d'invariants pour sys-reachability (pat-full-reachability).
import { test } from "node:test";
import assert from "node:assert/strict";
import { reachableCells, isLevelReachable } from "./reachability.mjs";

function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const blocked = (c) => c === 1;

// Génère une grille seedée avec densité d'obstacles p ; start toujours libre.
function makeGrid(rnd, w, h, p) {
  const grid = Array.from({ length: h }, () => Array.from({ length: w }, () => (rnd() < p ? 1 : 0)));
  grid[0][0] = 0;
  return grid;
}

test("invariant 1 : couloir vide -> toutes les cases atteignables", () => {
  const grid = makeGrid(() => 1 /*jamais < p*/, 5, 5, 0); // 0 obstacle
  const reach = reachableCells(grid, { x: 0, y: 0 }, blocked);
  assert.equal(reach.size, 25);
});

test("invariant 2 : un mur vertical complet isole la moitie droite", () => {
  const w = 6, h = 5;
  const grid = Array.from({ length: h }, () => Array.from({ length: w }, () => 0));
  for (let y = 0; y < h; y++) grid[y][3] = 1; // colonne 3 = mur plein
  const reach = reachableCells(grid, { x: 0, y: 0 }, blocked);
  // colonnes 0,1,2 = 3*5 = 15 atteignables ; colonnes 4,5 injoignables
  assert.equal(reach.size, 15);
  const r = isLevelReachable(grid, { x: 0, y: 0 }, [{ x: 5, y: 2 }], blocked);
  assert.equal(r.ok, false);
  assert.deepEqual(r.unreachable, [{ x: 5, y: 2 }]);
});

test("invariant 3 : deterministe sur 300 grilles seedees (meme seed -> meme resultat)", () => {
  for (let s = 0; s < 300; s++) {
    const g1 = makeGrid(mulberry32(s), 8, 8, 0.25);
    const g2 = makeGrid(mulberry32(s), 8, 8, 0.25);
    const r1 = reachableCells(g1, { x: 0, y: 0 }, blocked);
    const r2 = reachableCells(g2, { x: 0, y: 0 }, blocked);
    assert.deepEqual([...r1].sort(), [...r2].sort());
  }
});

test("invariant 4 : reachable ⊆ cases libres, et start inclus", () => {
  const rnd = mulberry32(7);
  const grid = makeGrid(rnd, 10, 10, 0.3);
  const reach = reachableCells(grid, { x: 0, y: 0 }, blocked);
  assert.ok(reach.has("0,0"));
  for (const k of reach) {
    const [x, y] = k.split(",").map(Number);
    assert.equal(grid[y][x], 0, `case atteignable ${k} ne doit pas etre bloquee`);
  }
});

test("cas limite : start bloque -> rien d'atteignable", () => {
  const grid = [[1, 0], [0, 0]];
  const reach = reachableCells(grid, { x: 0, y: 0 }, blocked);
  assert.equal(reach.size, 0);
});

test("isLevelReachable : tous objectifs joignables -> ok", () => {
  const grid = Array.from({ length: 4 }, () => Array.from({ length: 4 }, () => 0));
  const r = isLevelReachable(grid, { x: 0, y: 0 }, [{ x: 3, y: 3 }, { x: 0, y: 3 }], blocked);
  assert.equal(r.ok, true);
  assert.deepEqual(r.unreachable, []);
});
