// Breakout — tests de propriétés (invariants, déterminisme, comportements globaux)
import { test } from "node:test";
import assert from "node:assert/strict";
import { BreakoutGame } from "./game.mjs";
import { generateLevel } from "./level.mjs";

// === R9 : Brique détruite ne réapparaît pas ===
test("R9 — brique cassée persiste: reste absente après N steps", () => {
  const g = new BreakoutGame({ seed: 1 });
  if (g.bricks.length === 0) return;

  const brick = g.bricks[0];
  brick.health = 0; // Détruit la brique

  const count0 = g.bricks.filter(b => b.health === 0).length;

  for (let i = 0; i < 100; i++) {
    g.step(16, {});
  }

  const count1 = g.bricks.filter(b => b.health === 0).length;
  assert.equal(count0, count1, "nombre de briques cassées doit rester constant");
});

// === R10 : Niveau seedé est déterministe ===
test("R10 — generateLevel déterministe: même seed = même disposition", () => {
  const level1 = generateLevel(42, 0);
  const level2 = generateLevel(42, 0);

  assert.equal(level1.bricks.length, level2.bricks.length, "même nombre de briques");
  for (let i = 0; i < level1.bricks.length; i++) {
    const b1 = level1.bricks[i];
    const b2 = level2.bricks[i];
    assert.equal(b1.x, b2.x, `brick ${i} x doit être identique`);
    assert.equal(b1.y, b2.y, `brick ${i} y doit être identique`);
    assert.equal(b1.health, b2.health, `brick ${i} health doit être identique`);
  }
});

// === R14 : Progression de niveau ===
test("R14 — nextLevel incrémente index", () => {
  const g = new BreakoutGame({ seed: 2 });
  const idx0 = g.levelIndex;

  // Casse toutes les briques du niveau 0
  g.bricks.forEach(b => { b.health = 0; });
  g.checkWin();

  // Si pas le dernier niveau, nextLevel doit avoir été appelé
  if (idx0 < 2) {
    assert.ok(g.levelIndex > idx0, "levelIndex doit augmenter");
  }
});

// === R17 : Reset remet l'état initial ===
test("R17 — reset remet état initial", () => {
  const g = new BreakoutGame({ seed: 3 });
  const lives0 = g.lives;
  const score0 = g.score;
  const level0 = g.levelIndex;

  // Altère l'état
  g.lives = 1;
  g.score = 500;
  g.levelIndex = 2;

  // Reset
  g.reset(3);

  assert.equal(g.lives, 3, "lives doit revenir à 3");
  assert.equal(g.score, 0, "score doit revenir à 0");
  assert.equal(g.levelIndex, 0, "levelIndex doit revenir à 0");
});

// === R19 : Architecture — game n'importe pas render/input/server ===
test("R19 — game.mjs n'importe pas render/input/server", async () => {
  const fs = await import("fs/promises");
  const content = await fs.readFile("./game.mjs", "utf-8");

  // game.mjs peut importer level (autorisé par blueprint)
  // mais ne doit jamais importer render, input, ou server
  assert.ok(!content.includes('from "./render'), "pas d\'import de render");
  assert.ok(!content.includes('from "./input'), "pas d\'import de input");
  assert.ok(!content.includes('from "./server'), "pas d\'import de server");

  // Chercher des accès DOM directs (avec . après pour éviter les faux positifs dans les commentaires)
  const lines = content.split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();
    // Skip les commentaires
    if (trimmed.startsWith('//')) continue;
    assert.ok(!line.includes('document.'), `ligne ${i+1}: pas d'accès à document`);
    // window. mais pas dans un commentaire
    if (line.includes('window.') && !line.trim().startsWith('//')) {
      assert.fail(`ligne ${i+1}: pas d'accès direct à window`);
    }
  }
});

// === Propriété: Score augmente monotoniquement ===
test("Propriété — score monotone: jamais diminue", () => {
  const g = new BreakoutGame({ seed: 4 });
  let prevScore = g.score;

  for (let i = 0; i < 1000; i++) {
    g.step(16, { right: i % 2 === 0 });
    assert.ok(g.score >= prevScore, `score doit être ≥ ${prevScore}, got ${g.score}`);
    prevScore = g.score;
  }
});

// === Propriété: Lives ne descend pas sous 0 ===
test("Propriété — lives ≥ 0: jamais négatif", () => {
  const g = new BreakoutGame({ seed: 5 });

  for (let i = 0; i < 500; i++) {
    g.step(16, {});
    assert.ok(g.lives >= 0, `lives ne doit jamais être < 0, got ${g.lives}`);
    if (g.status !== 'ACTIVE') break;
  }
});

// === Propriété: Paddle dans limites ===
test("Propriété — paddle dans limites: 0 ≤ x ≤ WIDTH-paddleWidth", () => {
  const g = new BreakoutGame({ seed: 6 });

  for (let i = 0; i < 500; i++) {
    g.applyInput({ left: i % 3 === 0, right: i % 3 === 1 });
    assert.ok(g.paddle.x >= 0, `paddle.x >= 0`);
    assert.ok(g.paddle.x <= g.width - g.paddle.width, `paddle.x <= width-width`);
  }
});

// === Propriété: Ball speed reste ≈ constant ===
test("Propriété — speed invariant: vitesse reste approximativement constante", () => {
  const g = new BreakoutGame({ seed: 7 });
  const speed0 = Math.hypot(g.ball.vx, g.ball.vy);

  for (let i = 0; i < 300; i++) {
    g.step(16, {});
    const speed = Math.hypot(g.ball.vx, g.ball.vy);
    // Après un rebond, la vitesse reste ~identique (rechamp via normalisation d'angle)
    assert.ok(Math.abs(speed - speed0) < speed0 * 0.3, `speed doit rester ≈ ${speed0}`);
  }
});

// === Déterminisme: deux parties avec même seed → même résultat ===
test("Déterminisme — même seed = même déroulé (100 steps)", () => {
  const seed = 888;

  const g1 = new BreakoutGame({ seed });
  const g2 = new BreakoutGame({ seed });

  for (let i = 0; i < 100; i++) {
    const input = { left: i % 3 === 0, right: i % 3 === 1 };
    g1.step(16, input);
    g2.step(16, input);
  }

  const state1 = g1.view();
  const state2 = g2.view();

  assert.equal(state1.ball.x.toFixed(2), state2.ball.x.toFixed(2), "balle x doit être identique");
  assert.equal(state1.ball.y.toFixed(2), state2.ball.y.toFixed(2), "balle y doit être identique");
  assert.equal(state1.paddle.x.toFixed(2), state2.paddle.x.toFixed(2), "paddle x doit être identique");
  assert.equal(state1.score, state2.score, "score doit être identique");
  assert.equal(state1.lives, state2.lives, "lives doit être identique");
});
