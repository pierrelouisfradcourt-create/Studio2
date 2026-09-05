// Collect Runner — tests de logique PURE (node --test), zéro navigateur, déterministes.
// Toute seed fixe reproduit exactement le même déroulé (RNG xorshift32 dans game.mjs).
// STRICT assertions — pas de >= masquant, comportements-cœur testés directement.
import { test } from "node:test";
import assert from "node:assert/strict";
import { CollectRunnerGame, GAME_WIDTH, GAME_HEIGHT } from "./game.mjs";

// === RÈGLE 1 : Auto-advance (x augmente sans input) ===
test("Règle 1 - auto-advance: sans input, x augmente automatiquement", () => {
  const g = new CollectRunnerGame({ seed: 1 });
  const x0 = g.player.x;
  g.step(100, {}); // pas d'input
  assert.ok(g.player.x > x0, "x doit augmenter sans input (auto-advance)");
});

// === RÈGLE 2 : Gauche/Droite modulent la vitesse ===
test("Règle 2 - modulation vitesse: droite augmente x plus que sans input", () => {
  const g = new CollectRunnerGame({ seed: 2 });
  const x0 = g.player.x;
  g.step(100, { right: true });
  const xRight = g.player.x;

  const g2 = new CollectRunnerGame({ seed: 2 });
  const x2 = g2.player.x;
  g2.step(100, {}); // pas d'input
  const xNoInput = g2.player.x;

  assert.ok(xRight > xNoInput, "droite doit donner plus d'avance que sans input");
});

test("Règle 2b - modulation vitesse: gauche ralentit comparé à sans input", () => {
  const g = new CollectRunnerGame({ seed: 3 });
  g.step(100, { left: true });
  const xLeft = g.player.x;

  const g2 = new CollectRunnerGame({ seed: 3 });
  g2.step(100, {});
  const xNoInput = g2.player.x;

  assert.ok(xLeft < xNoInput, "gauche doit ralentir comparé au cas sans input");
});

// === RÈGLE 3 : Saut (vy négatif + onGround=false) ===
test("Règle 3 - saut: input jump fait vy négatif et onGround=false", () => {
  const g = new CollectRunnerGame({ seed: 4 });
  assert.equal(g.onGround, true, "doit être au sol au départ");
  g.step(16, { jump: true });
  assert.ok(g.vy < 0, "vy doit être négatif après saut");
  assert.equal(g.onGround, false, "onGround doit être false après saut");
});

// === RÈGLE 4 : Gravité (retombée + onGround=true à l'atterrissage) ===
test("Règle 4 - gravité: après saut, le joueur retombe et onGround repasse true", () => {
  const g = new CollectRunnerGame({ seed: 5 });
  const y0 = g.player.y;
  // Saut
  g.step(16, { jump: true });
  assert.ok(g.player.y < y0, "y doit diminuer au saut (vers le haut)");
  assert.ok(g.vy < 0, "vy doit être négatif au moment du saut");

  // Continue jusqu'à ce que le joueur retombe et que onGround repasse true
  let landed = false;
  for (let i = 0; i < 100 && !landed; i++) {
    g.step(16, {});
    if (g.onGround) landed = true;
  }
  assert.ok(landed, "joueur doit revenir au sol");
  assert.equal(g.onGround, true, "onGround doit repasser true à l'atterrissage");
  assert.equal(g.vy, 0, "vy doit être 0 au sol");
  assert.ok(g.player.y >= y0 - 1, "joueur doit être au sol (tolérance -1 pour arrondi)");
});

// === RÈGLE 5 : Collecte pièce -> coins exactement n+1 ===
test("Règle 5 - collecte pièce: ramasser une pièce augmente coins de EXACTEMENT 1", () => {
  const g = new CollectRunnerGame({ seed: 6 });
  const coins0 = g.coins;
  assert.equal(coins0, 0, "aucune pièce collectée au départ");

  // Positionne le joueur pour qu'il soit en collision avec la première pièce du niveau
  if (g.coinsOnLevel.length > 0) {
    const coin = g.coinsOnLevel[0];
    g.player.x = coin.x - 5;
    g.player.y = coin.y - 5;
    g.step(16, {}); // un step pour déclencher la collecte
    assert.equal(g.coins, coins0 + 1, "coins doit être exactement n+1");
  }
});

// === RÈGLE 6 : Obstacle touché -> over=true ===
test("Règle 6 - obstacle: collision avec un obstacle met over=true", () => {
  const g = new CollectRunnerGame({ seed: 7 });
  assert.equal(g.over, false, "over=false au départ");

  if (g.obstaclesOnLevel.length > 0) {
    const obs = g.obstaclesOnLevel[0];
    g.player.x = obs.x + 5;
    g.player.y = obs.y + 5;
    g.step(16, {});
    assert.equal(g.over, true, "over doit passer à true après collision avec un obstacle");
  }
});

// === RÈGLE 7 : Fin de niveau -> nextLevel (level+1, pièces reset) ===
test("Règle 7 - fin de niveau: collecte de toutes les pièces advance au niveau suivant", () => {
  const g = new CollectRunnerGame({ seed: 8 });
  const level0 = g.level;
  assert.equal(level0, 1, "level doit être 1 au départ");

  // Collecte toutes les pièces du niveau
  for (const coin of g.coinsOnLevel) {
    g.player.x = coin.x - 2;
    g.player.y = coin.y - 2;
    g.step(16, {});
  }

  assert.equal(g.level, level0 + 1, "level doit passer à n+1");
  assert.equal(g.levelCoins, 0, "levelCoins doit être resetté à 0 après passage de niveau");
});

// === RÈGLE 8 : Dernier niveau terminé -> won=true ===
test("Règle 8 - victoire: terminer le dernier niveau met won=true", () => {
  const g = new CollectRunnerGame({ seed: 9 });

  // Avance jusqu'au dernier niveau
  while (g.level < 3) {
    for (const coin of g.coinsOnLevel) {
      g.player.x = coin.x - 2;
      g.player.y = coin.y - 2;
      g.step(16, {});
    }
  }

  assert.equal(g.level, 3, "doit être au niveau 3");
  assert.equal(g.won, false, "won doit être false avant de collecter les pièces du dernier niveau");

  // Collecte les pièces du dernier niveau
  for (const coin of g.coinsOnLevel) {
    g.player.x = coin.x - 2;
    g.player.y = coin.y - 2;
    g.step(16, {});
  }

  assert.equal(g.won, true, "won doit passer à true après collecte de la dernière pièce");
});

// === RÈGLE 9 : Défaite gèle la simulation ===
test("Règle 9 - gel simulation: over=true => step() n'avance plus l'état", () => {
  const g = new CollectRunnerGame({ seed: 10 });
  const x0 = g.player.x;
  g.debugHit(); // force défaite
  assert.equal(g.over, true, "over doit être true après debugHit");
  g.step(1000, { right: true }); // essaie un step avec input
  assert.equal(g.player.x, x0, "x ne doit pas changer après over=true");
});

// === RÈGLE 10 : Déterminisme (même seed => même trace) ===
test("Règle 10 - déterminisme: même seed => trace identique", () => {
  function runTrace(seed) {
    const g = new CollectRunnerGame({ seed });
    const trace = [];
    for (let i = 0; i < 200; i++) {
      const input = { right: i % 5 === 0, jump: i % 7 === 0 };
      g.step(16, input);
      trace.push([
        Math.round(g.player.x * 1000),
        Math.round(g.player.y * 1000),
        g.vy.toFixed(1),
        g.onGround,
        g.coins,
        g.level,
      ]);
    }
    return trace;
  }

  const trace1 = runTrace(42);
  const trace2 = runTrace(42);
  assert.deepEqual(trace1, trace2, "deux runs avec seed 42 doivent produire la même trace");
});

// === RÈGLE 11 : État accessible via getters ===
test("Règle 11 - getters: x, coins, level, over, won, onGround accessibles", () => {
  const g = new CollectRunnerGame({ seed: 11 });
  const view = g.view();
  assert.ok(typeof view.player === "object", "player doit être dans la vue");
  assert.ok(typeof view.player.x === "number", "player.x doit être un nombre");
  assert.ok(typeof view.coins === "number", "coins doit être dans la vue");
  assert.ok(typeof view.level === "number", "level doit être dans la vue");
  assert.ok(typeof view.over === "boolean", "over doit être booléen");
  assert.ok(typeof view.won === "boolean", "won doit être booléen");
  assert.ok(typeof view.onGround === "boolean", "onGround doit être booléen");
});

// === RÈGLE 12 : Pas de Math.random() — RNG seedé ===
test("Règle 12 - RNG seedé: le même sequence de seeds produit les mêmes obstacles/pièces", () => {
  function getLayout(seed) {
    const g = new CollectRunnerGame({ seed });
    return {
      coins: g.coinsOnLevel.map(c => [Math.round(c.x * 100), Math.round(c.y * 100)]),
      obstacles: g.obstaclesOnLevel.map(o => [o.x, o.y]),
    };
  }

  const layout1 = getLayout(777);
  const layout2 = getLayout(777);
  assert.deepEqual(layout1, layout2, "même seed => même layout de pièces et obstacles");
});

// === BONUS : Déterminisme completo avec reset() ===
test("Bonus - reset relance proprement une partie", () => {
  const g = new CollectRunnerGame({ seed: 12 });
  g.debugHit();
  assert.equal(g.over, true);
  g.reset(13);
  assert.equal(g.over, false);
  assert.equal(g.coins, 0);
  assert.equal(g.level, 1);
  assert.equal(g.onGround, true);
});

// ============================================================================
// Tests ANTI-MUTANTS — tuent les survivants du mutation testing (forge.mutation).
// Chacun échoue si l'opérateur ciblé est muté => la mécanique est désormais gardée.
// ============================================================================

test("mutant L43: des seeds DIFFÉRENTS donnent des niveaux différents (RNG vraiment seedé)", () => {
  const a = new CollectRunnerGame({ seed: 1 }).view().coinsOnLevel;
  const b = new CollectRunnerGame({ seed: 12345 }).view().coinsOnLevel;
  assert.notDeepStrictEqual(a, b, "deux seeds distincts doivent produire des layouts distincts");
});

test("mutant L68/L71: positions GOLDEN exactes pour seed=1 (RNG interne figé)", () => {
  const v = new CollectRunnerGame({ seed: 1 }).view();
  assert.deepStrictEqual(v.coinsOnLevel.map((c) => +c.x.toFixed(4)), [230.0013, 462.3281, 681.1698]);
  assert.deepStrictEqual(v.coinsOnLevel.map((c) => +c.y.toFixed(4)), [484.6851, 483.5676, 481.5285]);
  assert.deepStrictEqual(v.obstaclesOnLevel.map((o) => +o.x.toFixed(4)), [220.0013, 452.3281, 671.1698]);
});

test("mutant L110: pas de double-saut (jump en l'air est un no-op)", () => {
  const g = new CollectRunnerGame({ seed: 3 });
  g.jump();
  assert.ok(g.vy < 0 && !g.onGround);
  g.vy = -50; // en pleine montée
  g.jump();   // 2e saut en l'air
  assert.strictEqual(g.vy, -50, "un saut en l'air ne doit PAS réarmer vy (onGround && !over)");
});

test("mutant L118: gravité gelée après défaite (applyGravity direct)", () => {
  const g = new CollectRunnerGame({ seed: 4 });
  g.over = true;
  g.player.y = 100; g.vy = 200;
  g.applyGravity(16);
  assert.strictEqual(g.player.y, 100, "après over, applyGravity ne bouge pas le joueur");
});

test("mutant L124: collision sol à l'égalité exacte (y == GROUND_LEVEL)", () => {
  const g = new CollectRunnerGame({ seed: 5 });
  g.player.y = g.height - 40; g.vy = 0; g.onGround = false;
  g.applyGravity(0); // dt=0 : y reste EXACTEMENT au sol
  assert.strictEqual(g.onGround, true, "à y==sol, la collision s'applique (>=, pas >)");
});

test("mutant L143: collecter une pièce incrémente levelCoins (+1, pas -1)", () => {
  const g = new CollectRunnerGame({ seed: 6 });
  const before = g.levelCoins;
  const coin = g.coinsOnLevel[0];
  g.player.x = coin.x - g.player.width / 2;
  g.player.y = coin.y - g.player.height / 2;
  g.collectCoin();
  assert.strictEqual(g.levelCoins, before + 1);
});

test("mutant L170: nextLevel n'avance pas si over (guard)", () => {
  const g = new CollectRunnerGame({ seed: 7 });
  g.over = true;
  g.coinsOnLevel.forEach((c) => (c.collected = true));
  g.nextLevel();
  assert.strictEqual(g.level, 1, "over => nextLevel ne doit PAS avancer le niveau");
});

test("mutant L190: onGround=true au début du niveau suivant", () => {
  const g = new CollectRunnerGame({ seed: 8 });
  g.onGround = false;
  g.coinsOnLevel.forEach((c) => (c.collected = true));
  g.nextLevel();
  assert.strictEqual(g.level, 2);
  assert.strictEqual(g.onGround, true, "au niveau suivant, le joueur est au sol");
});

test("mutant L226: debugHit ne s'applique pas sur une partie GAGNÉE", () => {
  const g = new CollectRunnerGame({ seed: 9 });
  g.won = true;
  g.debugHit();
  assert.strictEqual(g.over, false, "une partie gagnée ne devient pas 'over' via debugHit");
});
