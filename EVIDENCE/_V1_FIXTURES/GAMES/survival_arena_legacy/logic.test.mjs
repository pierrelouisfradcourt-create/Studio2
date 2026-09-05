// Survival Arena — tests de logique PURE (node --test), zéro navigateur, déterministes.
// Toute seed fixe reproduit exactement le même déroulé (RNG xorshift32 dans game.mjs).
import { test } from "node:test";
import assert from "node:assert/strict";
import { SurvivalGame, ARENA_WIDTH, ARENA_HEIGHT } from "./game.mjs";

test("le joueur bouge selon l'input (chaque direction)", () => {
  const g = new SurvivalGame({ seed: 1 });
  const x0 = g.player.x;
  const y0 = g.player.y;

  g.step(100, { right: true });
  assert.ok(g.player.x > x0, "right doit augmenter x");
  assert.equal(g.player.y, y0, "right seul ne doit pas bouger y");

  const g2 = new SurvivalGame({ seed: 1 });
  const x2 = g2.player.x;
  const y2 = g2.player.y;
  g2.step(100, { down: true });
  assert.equal(g2.player.x, x2);
  assert.ok(g2.player.y > y2, "down doit augmenter y");

  const g3 = new SurvivalGame({ seed: 1 });
  const x3 = g3.player.x;
  g3.step(100, { left: true });
  assert.ok(g3.player.x < x3, "left doit diminuer x");

  const g4 = new SurvivalGame({ seed: 1 });
  const y4 = g4.player.y;
  g4.step(100, { up: true });
  assert.ok(g4.player.y < y4, "up doit diminuer y");
});

test("aucun input => le joueur ne bouge pas", () => {
  const g = new SurvivalGame({ seed: 2 });
  const x0 = g.player.x;
  const y0 = g.player.y;
  g.step(200, {});
  assert.equal(g.player.x, x0);
  assert.equal(g.player.y, y0);
});

test("le joueur reste dans les limites de l'arène (clamp)", () => {
  const g = new SurvivalGame({ seed: 3 });
  for (let i = 0; i < 500; i++) g.step(16, { left: true, up: true });
  assert.ok(g.player.x >= g.player.r);
  assert.ok(g.player.y >= g.player.r);
});

test("un ennemi finit par spawn avec le temps", () => {
  const g = new SurvivalGame({ seed: 42 });
  assert.equal(g.enemies.length, 0, "aucun ennemi au départ");
  let spawned = false;
  for (let i = 0; i < 400; i++) {
    g.step(16, {});
    if (g.enemies.length > 0) { spawned = true; break; }
  }
  assert.ok(spawned, "un ennemi devrait avoir spawné après quelques secondes");
});

test("un ennemi au contact réduit les PV du joueur", () => {
  const g = new SurvivalGame({ seed: 7 });
  const hpBefore = g.hp;
  // place un ennemi manuellement en contact direct avec le joueur (état interne du même module)
  g.enemies.push({ id: 9001, x: g.player.x, y: g.player.y, r: 12, speed: 0, hp: 3 });
  g.step(16, {});
  assert.ok(g.hp < hpBefore, "les PV doivent baisser au contact");
});

test("un ennemi au contact ne inflige pas de dégâts en boucle sans cooldown écoulé", () => {
  const g = new SurvivalGame({ seed: 7 });
  g.enemies.push({ id: 9002, x: g.player.x, y: g.player.y, r: 12, speed: 0, hp: 3 });
  g.step(16, {});
  const hpAfterFirstHit = g.hp;
  g.step(16, {}); // toujours dans le cooldown (500ms)
  assert.equal(g.hp, hpAfterFirstHit, "pas de second coup avant la fin du cooldown");
});

test("PV=0 => over===true", () => {
  const g = new SurvivalGame({ seed: 11 });
  assert.equal(g.over, false);
  g.debugHit(g.maxHp);
  assert.equal(g.hp, 0);
  assert.equal(g.over, true);
});

test("over===true => step() n'a plus d'effet (simulation gelée)", () => {
  const g = new SurvivalGame({ seed: 11 });
  g.debugHit(g.maxHp);
  const t0 = g.timeAlive;
  const s0 = g.score;
  g.step(1000, { right: true });
  assert.equal(g.timeAlive, t0);
  assert.equal(g.score, s0);
});

test("le score augmente au fil du temps (survie)", () => {
  const g = new SurvivalGame({ seed: 5 });
  assert.equal(g.score, 0);
  for (let i = 0; i < 50; i++) g.step(16, {});
  assert.ok(g.score > 0, "le score de survie doit augmenter avec le temps");
});

test("le score augmente encore plus vite avec des kills", () => {
  const g = new SurvivalGame({ seed: 5 });
  for (let i = 0; i < 50; i++) g.step(16, {});
  const scoreNoKill = g.score;

  const g2 = new SurvivalGame({ seed: 5 });
  g2.enemies.push({ id: 8001, x: g2.player.x + 5, y: g2.player.y, r: 12, speed: 0, hp: 1 });
  for (let i = 0; i < 50; i++) g2.step(16, {});
  // STRICT (fini le `>=` tautologique) : le tir auto DOIT tuer l'ennemi placé —
  // sinon la mécanique cœur (tir/dégâts) est cassée — ET un kill DOIT augmenter
  // strictement le score. Un jeu au tir mort échouerait ici au lieu de passer vert.
  const killed = !g2.enemies.some((e) => e.id === 8001);
  assert.ok(killed, "le tir auto doit TUER l'ennemi placé (mécanique cœur prouvée)");
  assert.ok(g2.score > scoreNoKill, "un kill doit STRICTEMENT augmenter le score (pas >=)");
});

test("la difficulté croît : le spawn s'accélère avec le temps", () => {
  const gEarly = new SurvivalGame({ seed: 99 });
  let earlySpawns = 0;
  for (let i = 0; i < 250; i++) { // ~4000ms depuis timeAlive=0
    gEarly.step(16, {});
    earlySpawns = gEarly.enemies.length;
  }

  const gLate = new SurvivalGame({ seed: 99 });
  gLate.timeAlive = 40000; // avance artificiellement le temps interne (difficulté haute)
  let lateSpawns = 0;
  for (let i = 0; i < 250; i++) { // même fenêtre de 4000ms, mais en régime "difficile"
    gLate.step(16, {});
    lateSpawns = gLate.enemies.length;
  }

  assert.ok(
    lateSpawns > earlySpawns,
    `attendu plus de spawns en fin de partie (early=${earlySpawns}, late=${lateSpawns})`
  );
});

test("déterminisme : même seed => même déroulé exact", () => {
  function run(seed) {
    const g = new SurvivalGame({ seed });
    const trace = [];
    for (let i = 0; i < 300; i++) {
      const input = { right: i % 3 === 0, down: i % 5 === 0 };
      g.step(16, input);
      trace.push([
        Math.round(g.player.x * 1000),
        Math.round(g.player.y * 1000),
        g.hp,
        g.score,
        g.enemies.length,
      ]);
    }
    return trace;
  }
  const a = run(1234);
  const b = run(1234);
  assert.deepEqual(a, b, "deux runs avec la même seed doivent produire exactement le même déroulé");
});

test("reset() relance une partie propre avec une nouvelle seed", () => {
  const g = new SurvivalGame({ seed: 1 });
  g.debugHit(g.maxHp);
  assert.equal(g.over, true);
  g.reset(2);
  assert.equal(g.over, false);
  assert.equal(g.hp, g.maxHp);
  assert.equal(g.score, 0);
  assert.equal(g.enemies.length, 0);
  assert.equal(g.player.x, g.width / 2);
});

test("dimensions par défaut de l'arène", () => {
  const g = new SurvivalGame({ seed: 1 });
  assert.equal(g.width, ARENA_WIDTH);
  assert.equal(g.height, ARENA_HEIGHT);
});
