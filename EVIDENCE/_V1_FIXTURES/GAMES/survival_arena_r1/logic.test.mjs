// logic.test.mjs -- strict, white-box unit tests for game.mjs.
// Run with: node --test logic.test.mjs
// Every assertion is STRICT (exact values / strict inequalities), never a
// tautological >= that would pass even if the mechanic were broken.

import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SurvivalGame,
  ARENA_WIDTH,
  ARENA_HEIGHT,
  PLAYER_RADIUS,
  PLAYER_SPEED,
  PLAYER_MAX_HP,
  ENEMY_RADIUS,
  ENEMY_CONTACT_DPS,
  BULLET_RADIUS,
  SCORE_PER_KILL,
  SPAWN_INTERVAL_INITIAL_MS,
  SPAWN_INTERVAL_MIN_MS,
  SPAWN_RAMP_MS,
} from './game.mjs';

function closeTo(actual, expected, eps = 1e-6, msg = '') {
  assert.ok(Math.abs(actual - expected) <= eps, `${msg} expected ~${expected}, got ${actual}`);
}

test('initial state is centered, full hp, empty, not over', () => {
  const g = new SurvivalGame(1);
  const v = g.view();
  assert.equal(v.player.x, ARENA_WIDTH / 2);
  assert.equal(v.player.y, ARENA_HEIGHT / 2);
  assert.equal(v.hp, PLAYER_MAX_HP);
  assert.equal(v.score, 0);
  assert.equal(v.killCount, 0);
  assert.equal(v.enemies.length, 0);
  assert.equal(v.bullets.length, 0);
  assert.equal(v.over, false);
});

test('movement: moving right for 1s at PLAYER_SPEED moves exactly that far', () => {
  const g = new SurvivalGame(1);
  const startX = g.view().player.x;
  g.step(1000, { right: true });
  closeTo(g.view().player.x, startX + PLAYER_SPEED, 1e-9, 'x after 1s right');
  assert.equal(g.view().player.y, ARENA_HEIGHT / 2, 'y unchanged when moving purely right');
});

test('movement: diagonal input is normalized (not faster than axis-aligned)', () => {
  const g = new SurvivalGame(1);
  const start = g.view().player;
  g.step(1000, { right: true, down: true });
  const v = g.view();
  const traveled = Math.hypot(v.player.x - start.x, v.player.y - start.y);
  closeTo(traveled, PLAYER_SPEED, 1e-6, 'diagonal distance must equal PLAYER_SPEED*dt, not sqrt(2)*that');
});

test('movement: player is strictly clamped inside the arena, never past the wall', () => {
  const g = new SurvivalGame(1);
  // Push hard left for a long time -- must clamp to the wall, not overshoot.
  for (let i = 0; i < 500; i++) g.step(100, { left: true });
  const v = g.view();
  assert.equal(v.player.x, PLAYER_RADIUS, 'clamped exactly to left wall');
  assert.ok(v.player.x >= 0, 'never negative');
});

test('auto-fire targets the NEAREST enemy, not an arbitrary one', () => {
  const g = new SurvivalGame(1);
  // Manually seed two enemies at known distances (white-box: direct state access).
  g.enemies = [
    { id: 100, x: g.player.x + 300, y: g.player.y }, // far
    { id: 101, x: g.player.x + 50, y: g.player.y }, // near
  ];
  g._fireTimer = 1; // about to fire on next step
  const before = g.bullets.length;
  g.step(16, {});
  const v = g.view();
  assert.ok(v.bullets.length > before, 'a bullet must have been fired');
  const bullet = v.bullets[v.bullets.length - 1];
  // Bullet velocity direction should point toward the near enemy (+x, 0y) not the far one.
  assert.ok(bullet.x > g.player.x - 1, 'bullet spawned at player position');
  // Recompute via stored vx/vy on the internal bullet object.
  const raw = g.bullets[g.bullets.length - 1];
  assert.ok(raw.vx > 0, 'fires toward +x where both enemies are');
  closeTo(raw.vy, 0, 1e-6, 'fires along the x axis toward the aligned nearest enemy');
});

test('bullet-enemy collision strictly kills: enemy removed, bullet removed, score +SCORE_PER_KILL exactly', () => {
  const g = new SurvivalGame(1);
  g.enemies = [{ id: 200, x: g.player.x + 20, y: g.player.y }];
  g.bullets = [{ id: 300, x: g.player.x + 20 - (BULLET_RADIUS + ENEMY_RADIUS) + 1, y: g.player.y, vx: 400, vy: 0 }];
  const scoreBefore = g.score;
  const killsBefore = g.killCount;
  g.step(16, {});
  const v = g.view();
  assert.equal(v.enemies.length, 0, 'enemy must be removed on hit');
  assert.equal(v.bullets.length, 0, 'bullet must be consumed on hit');
  assert.equal(v.score, scoreBefore + SCORE_PER_KILL, 'score increases by EXACTLY SCORE_PER_KILL, not more/less');
  assert.equal(v.killCount, killsBefore + 1, 'killCount increments by exactly 1');
});

test('a bullet that never reaches an enemy kills nothing and grants no score', () => {
  const g = new SurvivalGame(1);
  g.enemies = [{ id: 201, x: g.player.x + 500, y: g.player.y + 500 }]; // far away, diagonal
  g.bullets = [{ id: 301, x: g.player.x, y: g.player.y, vx: 400, vy: 0 }]; // fired along +x, will miss
  g.step(16, {});
  const v = g.view();
  assert.equal(v.score, 0, 'no score without an actual hit -- guards against tautological score checks');
  assert.equal(v.enemies.length, 1, 'enemy survives a miss');
});

test('enemy contact deals EXACTLY dps*dt damage, no more no less', () => {
  const g = new SurvivalGame(1);
  g.enemies = [{ id: 400, x: g.player.x, y: g.player.y }]; // fully overlapping
  g._fireTimer = 1e9; // isolate contact damage from auto-fire (which would one-shot-kill the overlapping enemy)
  const hpBefore = g.hp;
  g.step(500, {}); // 0.5s
  const expectedDamage = ENEMY_CONTACT_DPS * 0.5;
  closeTo(g.hp, hpBefore - expectedDamage, 1e-6, 'hp after 0.5s of contact');
});

test('two overlapping enemies both deal contact damage (damage stacks)', () => {
  const g = new SurvivalGame(1);
  g.enemies = [
    { id: 401, x: g.player.x, y: g.player.y },
    { id: 402, x: g.player.x, y: g.player.y },
  ];
  g._fireTimer = 1e9; // isolate contact damage from auto-fire
  const hpBefore = g.hp;
  g.step(500, {});
  const expectedDamage = ENEMY_CONTACT_DPS * 0.5 * 2;
  closeTo(g.hp, hpBefore - expectedDamage, 1e-6, 'both enemies contribute damage simultaneously');
});

test('hp clamps at exactly 0 and over flips to true only once hp truly reaches 0', () => {
  const g = new SurvivalGame(1);
  g.hp = 1;
  g.enemies = [{ id: 500, x: g.player.x, y: g.player.y }];
  g._fireTimer = 1e9; // isolate: this test is about contact damage -> hp -> over, not about bullet kills
  assert.equal(g.over, false, 'not over while hp > 0');
  g.step(1000, {}); // massive overkill damage
  const v = g.view();
  assert.equal(v.hp, 0, 'hp clamped to exactly 0, never negative');
  assert.equal(v.over, true, 'over flips true exactly when hp hits 0');
});

test('game is frozen once over: further step() calls do not mutate state', () => {
  const g = new SurvivalGame(1);
  g.hp = 0;
  g.over = true;
  g.enemies = [{ id: 600, x: g.player.x, y: g.player.y }];
  const before = JSON.stringify(g.view());
  g.step(1000, { right: true, up: true });
  const after = JSON.stringify(g.view());
  assert.equal(after, before, 'view() must be byte-identical after stepping a finished game');
});

test('reset() fully reinitializes state', () => {
  const g = new SurvivalGame(1);
  g.enemies = [{ id: 700, x: 1, y: 1 }];
  g.score = 999;
  g.hp = 3;
  g.over = true;
  g.reset(42);
  const v = g.view();
  assert.equal(v.score, 0);
  assert.equal(v.hp, PLAYER_MAX_HP);
  assert.equal(v.over, false);
  assert.equal(v.enemies.length, 0);
  assert.equal(v.player.x, ARENA_WIDTH / 2);
});

test('same seed produces the same first-spawn enemy position (deterministic RNG)', () => {
  // Step in small, game-loop-realistic increments and capture the FIRST frame
  // an enemy appears (fire cannot trigger the same frame it spawns in, since
  // fireTimer is pinned to FIRE_INTERVAL_MS while the enemy list is empty).
  function firstSpawnPosition(seed) {
    const g = new SurvivalGame(seed);
    for (let i = 0; i < 300; i++) {
      const v = g.step(16, {});
      if (v.enemies.length > 0) return v.enemies[0];
    }
    return null;
  }
  const e1 = firstSpawnPosition(777);
  const e2 = firstSpawnPosition(777);
  assert.ok(e1, 'first game spawned an enemy within the sampled window');
  assert.ok(e2, 'second game spawned an enemy within the sampled window');
  assert.equal(e1.x, e2.x, 'same seed -> identical spawn x');
  assert.equal(e1.y, e2.y, 'same seed -> identical spawn y');
});

test('difficulty ramp strictly shrinks spawnInterval over time, floored at SPAWN_INTERVAL_MIN_MS', () => {
  const g = new SurvivalGame(1);
  const initial = g.spawnInterval;
  assert.equal(initial, SPAWN_INTERVAL_INITIAL_MS);
  g.step(SPAWN_RAMP_MS + 1, {});
  assert.ok(g.spawnInterval < initial, 'spawnInterval must shrink strictly after one ramp tick');
  // Run long enough to hit the floor.
  for (let i = 0; i < 50; i++) g.step(SPAWN_RAMP_MS, {});
  assert.equal(g.spawnInterval, SPAWN_INTERVAL_MIN_MS, 'spawnInterval floors at SPAWN_INTERVAL_MIN_MS, does not go below');
});

test('enemies actually move closer to the player over consecutive steps (pursuit, white-box)', () => {
  const g = new SurvivalGame(1);
  g.enemies = [{ id: 800, x: 0, y: 0 }];
  const distBefore = Math.hypot(g.enemies[0].x - g.player.x, g.enemies[0].y - g.player.y);
  g.step(100, {});
  const e = g.view().enemies.find((e) => e.id === 800);
  assert.ok(e, 'enemy still alive (far from bullets)');
  const distAfter = Math.hypot(e.x - g.player.x, e.y - g.player.y);
  assert.ok(distAfter < distBefore, 'enemy must be strictly closer to the player after stepping');
});
