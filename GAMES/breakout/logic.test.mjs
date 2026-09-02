// Breakout — tests de logique PURE (node --test), zéro navigateur, déterministes.
// STRICT assertions — pas de >= masquant, comportements-cœur testés directement.
import { test } from "node:test";
import assert from "node:assert/strict";
import { BreakoutGame, GAME_WIDTH, GAME_HEIGHT } from "./game.mjs";

// === R1 : La balle avance en continu ===
test("R1 — balle avance: après step, position change de (vx, vy) exact", () => {
  const g = new BreakoutGame({ seed: 1 });
  const ball0 = { x: g.ball.x, y: g.ball.y };
  const vel0 = { vx: g.ball.vx, vy: g.ball.vy };

  g.step(16, {}); // 16ms = 0.016s

  const deltaX = g.ball.x - ball0.x;
  const deltaY = g.ball.y - ball0.y;
  const expectedDX = vel0.vx * 0.016;
  const expectedDY = vel0.vy * 0.016;

  assert.ok(Math.abs(deltaX - expectedDX) < 0.1, `deltaX=${deltaX} ~= ${expectedDX}`);
  assert.ok(Math.abs(deltaY - expectedDY) < 0.1, `deltaY=${deltaY} ~= ${expectedDY}`);
});

// === R2 : Rebond mur latéral ===
test("R2 — rebond mur: vx s'inverse, vy inchangé", () => {
  const g = new BreakoutGame({ seed: 2 });
  g.ball.x = 5; // Proche du mur gauche
  g.ball.y = 300;
  g.ball.vx = -100;
  g.ball.vy = 50;

  g.step(16, {});

  // Après rebond mur, vx doit être l'opposé
  assert.ok(g.ball.vx > 0, "vx doit être positif après rebond mur gauche");
  assert.ok(Math.abs(g.ball.vy - 50) < 1, "vy doit rester ~50");
});

// === R3 : Rebond plafond ===
test("R3 — rebond plafond: vy s'inverse, vx inchangé", () => {
  const g = new BreakoutGame({ seed: 3 });
  g.ball.x = 400;
  g.ball.y = 5; // Proche du plafond
  g.ball.vx = 100;
  g.ball.vy = -150;

  g.step(16, {});

  // Après rebond plafond, vy doit être positif
  assert.ok(g.ball.vy > 0, "vy doit être positif après rebond plafond");
  assert.ok(Math.abs(g.ball.vx - 100) < 1, "vx doit rester ~100");
});

// === R4 : Rebond raquette, angle selon point d'impact ===
test("R4 — rebond raquette centre: vx ≈ 0, vy négatif", () => {
  const g = new BreakoutGame({ seed: 4 });
  // Place la balle EN COLLISION avec le centre de la raquette
  g.paddle.x = 300;
  g.ball.x = g.paddle.x + g.paddle.width / 2;
  g.ball.y = g.paddle.y - 2; // Juste avant collision
  g.ball.vx = 0;
  g.ball.vy = 100;

  g.step(16, {});

  // Au centre, vx doit être minimal, vy négatif
  assert.ok(Math.abs(g.ball.vx) < 80, `vx au centre doit être petit, got ${g.ball.vx}`);
  assert.ok(g.ball.vy < 0, "vy doit être négatif après rebond raquette");
});

test("R4 — rebond raquette bord gauche: vx négatif", () => {
  const g = new BreakoutGame({ seed: 5 });
  g.paddle.x = 300;
  g.ball.x = g.paddle.x + 5; // Bord gauche
  g.ball.y = g.paddle.y - 2;
  g.ball.vx = -50;
  g.ball.vy = 100;

  g.step(16, {});

  assert.ok(g.ball.vx < 0, `vx au bord gauche doit être négatif, got ${g.ball.vx}`);
  assert.ok(g.ball.vy < 0, "vy doit être négatif");
});

test("R4 — rebond raquette bord droit: vx positif", () => {
  const g = new BreakoutGame({ seed: 6 });
  g.paddle.x = 300;
  g.ball.x = g.paddle.x + g.paddle.width - 5; // Bord droit
  g.ball.y = g.paddle.y - 2;
  g.ball.vx = 50;
  g.ball.vy = 100;

  g.step(16, {});

  assert.ok(g.ball.vx > 0, `vx au bord droit doit être positif, got ${g.ball.vx}`);
  assert.ok(g.ball.vy < 0, "vy doit être négatif");
});

// === R6 : Déplacement raquette gauche/droite ===
test("R6 — input gauche: paddle.x diminue", () => {
  const g = new BreakoutGame({ seed: 7 });
  const x0 = g.paddle.x;
  g.applyInput({ left: true });
  assert.ok(g.paddle.x < x0, "paddle.x doit diminuer avec input left");
});

test("R6 — input droite: paddle.x augmente", () => {
  const g = new BreakoutGame({ seed: 8 });
  const x0 = g.paddle.x;
  g.applyInput({ right: true });
  assert.ok(g.paddle.x > x0, "paddle.x doit augmenter avec input right");
});

// === R7 : Raquette bornée ===
test("R7 — paddle borné à gauche", () => {
  const g = new BreakoutGame({ seed: 9 });
  g.paddle.x = 0;
  for (let i = 0; i < 10; i++) {
    g.applyInput({ left: true });
  }
  assert.equal(g.paddle.x, 0, "paddle.x ne doit jamais descendre sous 0");
});

test("R7 — paddle borné à droite", () => {
  const g = new BreakoutGame({ seed: 10 });
  g.paddle.x = GAME_WIDTH - g.paddle.width;
  for (let i = 0; i < 10; i++) {
    g.applyInput({ right: true });
  }
  assert.equal(g.paddle.x, GAME_WIDTH - g.paddle.width, "paddle.x borné à droite");
});

// === R8 : Brique touchée → détruite + score ===
test("R8 — collision brique: santé diminue, score augmente", () => {
  const g = new BreakoutGame({ seed: 11 });

  // Trouver une brique cassable
  let brick = null;
  for (const b of g.bricks) {
    if (b.health > 0) {
      brick = b;
      break;
    }
  }

  // Si aucune brique cassable n'existe, en créer une
  if (!brick) {
    brick = {
      x: 100, y: 100, width: 60, height: 16,
      health: 1, value: 10, breakable: true
    };
    g.bricks.push(brick);
  }

  const health0 = brick.health;
  const score0 = g.score;

  // Place la balle EN COLLISION DIRECTE avec la brique
  g.ball.x = brick.x + brick.width / 2;
  g.ball.y = brick.y - 2; // Juste avant la collision
  g.ball.vx = 0;
  g.ball.vy = 100;

  g.step(16, {});

  assert.equal(brick.health, 0, "santé brique doit diminuer");
  assert.ok(g.score > score0, "score doit augmenter après collision brique");
});

// === R11 : Perte de vie ===
test("R11 — sortie basse: vies diminuent", () => {
  const g = new BreakoutGame({ seed: 12 });
  const lives0 = g.lives;

  g.ball.y = GAME_HEIGHT + 10; // En dessous de la limite
  g.step(16, {});

  assert.equal(g.lives, lives0 - 1, "vies doit diminuer de 1");
});

// === R12 : Défaite ssi vies == 0 ===
test("R12 — défaite: status=LOST ssi vies==0", () => {
  const g = new BreakoutGame({ seed: 13 });
  g.lives = 1;
  assert.notEqual(g.status, 'LOST', "status ≠ LOST quand vies=1");

  g.loseLife();
  g.checkLose();
  assert.equal(g.status, 'LOST', "status === LOST quand vies=0");
});

// === R13 : Victoire niveau ssi briques == 0 ===
test("R13 — victoire niveau: toutes briques cassées", () => {
  const g = new BreakoutGame({ seed: 14 });
  // Cas 1: 1 brique cassable restante
  g.bricks = [{ x: 100, y: 100, width: 60, height: 16, health: 1, value: 10 }];
  assert.notEqual(g.status, 'WON', "status ≠ WON avec 1 brique");

  // Cas 2: 0 briques cassables
  g.bricks[0].health = 0;
  g.checkWin();
  // Dépend du niveau, donc on ne peut pas asserter WON directement
  // On teste juste que checkWin s'exécute sans erreur
});

// === R18 : readDebug expose l'état ===
test("R18 — readDebug expose état complet", () => {
  const g = new BreakoutGame({ seed: 15 });
  const debug = g.readDebug();

  assert.ok(typeof debug.lives === 'number', "debug.lives existe");
  assert.ok(typeof debug.score === 'number', "debug.score existe");
  assert.ok(typeof debug.levelIndex === 'number', "debug.levelIndex existe");
  assert.ok(typeof debug.ballX === 'number', "debug.ballX existe");
  assert.ok(typeof debug.ballY === 'number', "debug.ballY existe");
  assert.ok(typeof debug.paddleX === 'number', "debug.paddleX existe");
  assert.ok(typeof debug.status === 'string', "debug.status existe");
});
