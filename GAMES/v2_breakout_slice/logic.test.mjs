// Tests unitaires — un test par règle, exécutables hors navigateur (node --test).
// Les modules DOM (input/render/main) sont exercés avec un environnement factice
// injecté : aucune dépendance navigateur, aucun global installé.

import { test } from 'node:test';
import assert from 'node:assert';

import {
  Engine, GAME_DIMENSIONS, makeRng,
  STATE_PLAYING, STATE_WON, STATE_LOST, DIR_LEFT, DIR_RIGHT, AXIS_X, AXIS_Y,
} from './engine.mjs';
import { InputHandler, KEY_LEFT, KEY_RIGHT, INTENT_LEFT, INTENT_RIGHT } from './input.mjs';
import {
  Renderer, overlayTextFor, objectiveTextFor, OBJECTIVE_TEXT, WIN_TEXT, LOSE_TEXT,
} from './render.mjs';
import { createGame, autoBootstrap, seedFromLocation, DEFAULT_SEED } from './main.mjs';

const { GAME_WIDTH, PADDLE_WIDTH, PADDLE_SPEED, BALL_SPEED, BALL_RADIUS, DT_SECONDS } =
  GAME_DIMENSIONS;

// --- doublures d'environnement -------------------------------------------------

function makeCtx() {
  const calls = { fillRect: [], fillText: [], arc: [] };
  return {
    calls,
    fillStyle: '',
    font: '',
    fillRect: (...args) => calls.fillRect.push(args),
    fillText: (...args) => calls.fillText.push(args),
    arc: (...args) => calls.arc.push(args),
    beginPath: () => {},
    fill: () => {},
  };
}

function makeCanvas() {
  const ctx = makeCtx();
  return { width: 800, height: 600, ctx, getContext: () => ctx };
}

function makeElement() {
  const classes = new Set();
  const listeners = new Map();
  return {
    textContent: '',
    classList: {
      add: (c) => classes.add(c),
      remove: (c) => classes.delete(c),
      contains: (c) => classes.has(c),
    },
    addEventListener(type, fn) {
      const bucket = listeners.get(type) ?? [];
      bucket.push(fn);
      listeners.set(type, bucket);
    },
    fire(type, event) {
      for (const fn of listeners.get(type) ?? []) fn(event);
    },
  };
}

function makeEnv({ readyState = 'complete', search = '' } = {}) {
  const canvas = makeCanvas();
  const overlay = makeElement();
  const overlayText = makeElement();
  const objectif = makeElement();
  const restart = makeElement();
  const byId = { gameCanvas: canvas, overlay, overlayText, objectif, restart };
  const document = { readyState, getElementById: (id) => byId[id] ?? null };

  const listeners = new Map();
  const frames = [];
  const window = {
    location: { search },
    cancelled: null,
    frames,
    addEventListener(type, fn) {
      const bucket = listeners.get(type) ?? [];
      bucket.push(fn);
      listeners.set(type, bucket);
    },
    fire(type, event) {
      for (const fn of listeners.get(type) ?? []) fn(event);
    },
    listenerCount: (type) => (listeners.get(type) ?? []).length,
    requestAnimationFrame(fn) {
      frames.push(fn);
      return frames.length;
    },
    cancelAnimationFrame(id) {
      window.cancelled = id;
    },
  };
  return { window, document, canvas, overlay, overlayText, objectif, restart };
}

function speedOf(ball) {
  return Math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy);
}

// --- moteur : état initial ------------------------------------------------------

test('Engine: init sets a playing game with a full wall of intact bricks', () => {
  const engine = new Engine({ seed: 1 });
  assert.strictEqual(engine.state, STATE_PLAYING);
  assert.strictEqual(engine.over, false);
  assert.strictEqual(engine.ticks, 0);
  assert.strictEqual(engine.bricks.length, GAME_DIMENSIONS.BRICK_COUNT);
  assert.strictEqual(engine.bricksRemaining, GAME_DIMENSIONS.BRICK_COUNT);
  assert.ok(engine.bricks.every((brick) => brick.destroyed === false),
    'toute brique doit naître intacte');
});

test('Engine: the served ball sits above the paddle and carries the nominal speed', () => {
  const engine = new Engine({ seed: 3 });
  assert.ok(engine.ball.y < engine.paddle.y, 'la balle est servie au-dessus de la raquette');
  assert.ok(engine.ball.vy < 0, 'la balle est servie vers le haut');
  assert.ok(Math.abs(speedOf(engine.ball) - BALL_SPEED) < 1e-9);
});

test('Engine: tick advances the ball by exactly v*dt and counts the tick', () => {
  const engine = new Engine({ seed: 1 });
  engine.ball = { x: 400, y: 300, vx: 100, vy: 50 };
  engine.tick(null);
  assert.strictEqual(engine.ticks, 1);
  assert.strictEqual(engine.ball.x, 400 + 100 * DT_SECONDS);
  assert.strictEqual(engine.ball.y, 300 + 50 * DT_SECONDS);
  assert.strictEqual(engine.ball.vx, 100, 'aucun rebond ne doit survenir en plein champ');
  assert.strictEqual(engine.ball.vy, 50, 'aucun rebond ne doit survenir en plein champ');
});

test('Engine: a finished game is frozen — tick changes nothing', () => {
  const engine = new Engine({ seed: 1 });
  engine.state = STATE_WON;
  const before = engine.hashState();
  engine.tick(DIR_RIGHT);
  assert.strictEqual(engine.hashState(), before);
  assert.strictEqual(engine.ticks, 0);
});

// --- R2 raquette ----------------------------------------------------------------

test('Paddle: movePaddle right increases x, left decreases it, no intent keeps it', () => {
  const engine = new Engine({ seed: 1 });
  const start = engine.paddle.x;
  const step = PADDLE_SPEED * DT_SECONDS;

  engine.movePaddle(DIR_RIGHT);
  assert.strictEqual(engine.paddle.x, start + step);

  engine.movePaddle(DIR_LEFT);
  assert.strictEqual(engine.paddle.x, start);

  engine.movePaddle(null);
  assert.strictEqual(engine.paddle.x, start);
});

test('Paddle: movePaddle stays inside the play field on both edges', () => {
  const engine = new Engine({ seed: 1 });
  engine.paddle.x = 0;
  engine.movePaddle(DIR_LEFT);
  assert.strictEqual(engine.paddle.x, 0);

  engine.paddle.x = GAME_WIDTH - PADDLE_WIDTH;
  engine.movePaddle(DIR_RIGHT);
  assert.strictEqual(engine.paddle.x, GAME_WIDTH - PADDLE_WIDTH);
});

// --- R3 rebond ------------------------------------------------------------------

test('Ball: reflectBall x inverts vx and leaves vy untouched', () => {
  const engine = new Engine({ seed: 1 });
  engine.ball = { x: 100, y: 100, vx: 120, vy: -80 };
  engine.reflectBall(AXIS_X);
  assert.strictEqual(engine.ball.vx, -120);
  assert.strictEqual(engine.ball.vy, -80);
});

test('Ball: reflectBall y inverts vy and leaves vx untouched', () => {
  const engine = new Engine({ seed: 1 });
  engine.ball = { x: 100, y: 100, vx: 120, vy: -80 };
  engine.reflectBall(AXIS_Y);
  assert.strictEqual(engine.ball.vy, 80);
  assert.strictEqual(engine.ball.vx, 120);
});

test('Ball: bounces off the left wall', () => {
  const engine = new Engine({ seed: 1 });
  engine.ball = { x: BALL_RADIUS, y: 300, vx: -120, vy: 0 };
  engine.tick(null);
  assert.ok(engine.ball.vx > 0, 'vx doit repartir vers la droite');
  assert.ok(engine.ball.x >= BALL_RADIUS);
});

test('Ball: bounces off the right wall', () => {
  const engine = new Engine({ seed: 1 });
  engine.ball = { x: GAME_WIDTH - BALL_RADIUS, y: 300, vx: 120, vy: 0 };
  engine.tick(null);
  assert.ok(engine.ball.vx < 0, 'vx doit repartir vers la gauche');
  assert.ok(engine.ball.x <= GAME_WIDTH - BALL_RADIUS);
});

test('Ball: bounces off the ceiling', () => {
  const engine = new Engine({ seed: 1 });
  engine.ball = { x: 400, y: BALL_RADIUS, vx: 0, vy: -120 };
  engine.tick(null);
  assert.ok(engine.ball.vy > 0, 'vy doit repartir vers le bas');
  assert.ok(engine.ball.y >= BALL_RADIUS);
});

test('Paddle bounce: a descending ball touching the paddle is sent back up', () => {
  const engine = new Engine({ seed: 1 });
  engine.ball = {
    x: engine.paddle.x + PADDLE_WIDTH / 2,
    y: engine.paddle.y - BALL_RADIUS,
    vx: 0,
    vy: 200,
  };
  engine.tick(null);
  assert.ok(engine.ball.vy < 0, 'la balle doit remonter après contact raquette');
  assert.strictEqual(engine.state, STATE_PLAYING);
});

test('Paddle bounce: a rising ball inside the paddle is not reflected again', () => {
  const engine = new Engine({ seed: 1 });
  engine.ball = {
    x: engine.paddle.x + PADDLE_WIDTH / 2,
    y: engine.paddle.y,
    vx: 0,
    vy: -200,
  };
  engine.tick(null);
  assert.ok(engine.ball.vy < 0, 'une balle déjà remontante ne doit pas être renvoyée vers le bas');
});

// --- R4 / R5 briques ------------------------------------------------------------

test('Brick: destroyBrick marks the brick and decrements the counter by exactly one', () => {
  const engine = new Engine({ seed: 1 });
  const brick = engine.bricks[0];
  const before = engine.bricksRemaining;
  engine.destroyBrick(brick);
  assert.strictEqual(brick.destroyed, true);
  assert.strictEqual(engine.bricksRemaining, before - 1);
});

test('Brick: a ball touching a brick destroys exactly that brick in the same tick', () => {
  const engine = new Engine({ seed: 1 });
  const target = engine.bricks[0];
  engine.ball = {
    x: target.x + target.width / 2,
    y: target.y + target.height / 2,
    vx: 0,
    vy: -100,
  };
  engine.tick(null);

  assert.strictEqual(target.destroyed, true, 'la brique touchée disparaît au même tick');
  assert.strictEqual(engine.bricksRemaining, GAME_DIMENSIONS.BRICK_COUNT - 1);
  assert.strictEqual(engine.bricks.filter((b) => b.destroyed).length, 1,
    'une seule brique détruite');
  assert.ok(engine.ball.vy > 0, 'la balle rebondit sur la brique');
});

test('Brick: a tick far from the wall destroys nothing', () => {
  const engine = new Engine({ seed: 1 });
  engine.ball = { x: 400, y: 300, vx: 0, vy: 40 };
  engine.tick(null);
  assert.strictEqual(engine.bricksRemaining, GAME_DIMENSIONS.BRICK_COUNT);
  assert.ok(engine.bricks.every((brick) => brick.destroyed === false));
});

test('Brick: an already destroyed brick is not collidable', () => {
  const engine = new Engine({ seed: 1 });
  const target = engine.bricks[0];
  engine.destroyBrick(target);
  const after = engine.bricksRemaining;
  engine.ball = {
    x: target.x + target.width / 2,
    y: target.y + target.height / 2,
    vx: 0,
    vy: -100,
  };
  engine.tick(null);
  assert.strictEqual(engine.bricksRemaining, after, 'aucune seconde destruction');
  assert.ok(engine.ball.vy < 0, 'aucun rebond sur une brique détruite');
});

// --- R6 / R7 états terminaux ----------------------------------------------------

test('Game: checkWin sets won and over only once the wall is empty', () => {
  const engine = new Engine({ seed: 1 });
  engine.checkWin();
  assert.strictEqual(engine.state, STATE_PLAYING, 'mur plein => partie en cours');

  engine.bricksRemaining = 0;
  engine.checkWin();
  assert.strictEqual(engine.state, STATE_WON);
  assert.strictEqual(engine.over, true);
});

test('Game: checkLose sets lost and over from a playing game, and never revives a won one', () => {
  const engine = new Engine({ seed: 1 });
  engine.checkLose();
  assert.strictEqual(engine.state, STATE_LOST);
  assert.strictEqual(engine.over, true);

  const won = new Engine({ seed: 1 });
  won.state = STATE_WON;
  won.checkLose();
  assert.strictEqual(won.state, STATE_WON);
});

test('Game: a ball falling below the field loses the game', () => {
  const engine = new Engine({ seed: 1 });
  engine.ball = { x: 400, y: 600, vx: 0, vy: 400 };
  engine.tick(null);
  assert.strictEqual(engine.state, STATE_LOST);
  assert.strictEqual(engine.over, true);
});

// --- R9 déterminisme ------------------------------------------------------------

test('Engine: same seed and same inputs produce the same final hash', () => {
  const inputs = [DIR_LEFT, DIR_RIGHT, null, DIR_RIGHT, DIR_LEFT];
  const play = (seed) => {
    const engine = new Engine({ seed });
    for (let i = 0; i < 400; i++) engine.tick(inputs[i % inputs.length]);
    return engine.hashState();
  };
  assert.strictEqual(play(11), play(11));
});

test('Engine: the seed really drives the served ball', () => {
  const directions = new Set();
  for (let seed = 1; seed <= 12; seed++) {
    directions.add(new Engine({ seed }).ball.vx);
  }
  assert.ok(directions.size > 1, 'des seeds différentes doivent servir des balles différentes');
});

test('Engine: hashState changes when the state changes and is stable otherwise', () => {
  const engine = new Engine({ seed: 5 });
  const before = engine.hashState();
  assert.strictEqual(engine.hashState(), before);
  engine.destroyBrick(engine.bricks[0]);
  assert.notStrictEqual(engine.hashState(), before);
});

test('RNG: makeRng depends only on its seed', () => {
  const draw = (seed) => Array.from({ length: 5 }, makeRng(seed));
  assert.deepStrictEqual(draw(42), draw(42));
  assert.notDeepStrictEqual(draw(42), draw(43));
  for (const value of draw(7)) {
    assert.ok(value >= 0 && value < 1);
  }
});

// --- entrées --------------------------------------------------------------------

test('Input: keydown and keyup on the injected target drive the intent', () => {
  const target = makeElement();
  const input = new InputHandler(target);
  assert.strictEqual(input.getIntent(), null);

  target.fire('keydown', { key: KEY_RIGHT });
  assert.strictEqual(input.getIntent(), INTENT_RIGHT);

  target.fire('keyup', { key: KEY_RIGHT });
  assert.strictEqual(input.getIntent(), null);

  target.fire('keydown', { key: KEY_LEFT });
  assert.strictEqual(input.getIntent(), INTENT_LEFT);
});

test('Input: left wins over right, and reset clears held keys', () => {
  const target = makeElement();
  const input = new InputHandler(target);
  target.fire('keydown', { key: KEY_RIGHT });
  target.fire('keydown', { key: KEY_LEFT });
  assert.strictEqual(input.getIntent(), INTENT_LEFT);

  input.reset();
  assert.strictEqual(input.getIntent(), null);
});

test('Input: headless (no window) yields no intent and never throws', () => {
  const input = new InputHandler();
  assert.strictEqual(input.target, null);
  assert.strictEqual(input.getIntent(), null);
});

// --- rendu ----------------------------------------------------------------------

test('Renderer: renderObjective writes a non-empty objective text exactly once', () => {
  const canvas = makeCanvas();
  const renderer = new Renderer(canvas);
  renderer.renderObjective({ bricksRemaining: 40 });

  assert.strictEqual(canvas.ctx.calls.fillText.length, 1);
  const [text] = canvas.ctx.calls.fillText[0];
  assert.ok(text.length > 0, 'le HUD objectif porte un texte non vide');
  assert.ok(text.startsWith(OBJECTIVE_TEXT), 'le HUD décrit la destruction du mur');
  assert.ok(text.includes('briques'), 'le HUD nomme les briques');
  assert.strictEqual(text, objectiveTextFor({ bricksRemaining: 40 }));
});

test('Renderer: renderBricks paints only the bricks still standing', () => {
  const canvas = makeCanvas();
  const renderer = new Renderer(canvas);
  renderer.renderBricks([
    { x: 0, y: 0, width: 10, height: 5, destroyed: false },
    { x: 20, y: 0, width: 10, height: 5, destroyed: true },
  ]);
  assert.strictEqual(canvas.ctx.calls.fillRect.length, 1);
  assert.deepStrictEqual(canvas.ctx.calls.fillRect[0], [0, 0, 10, 5]);
});

test('Renderer: overlayTextFor maps every state to its panel text', () => {
  assert.strictEqual(overlayTextFor({ state: STATE_WON }), WIN_TEXT);
  assert.strictEqual(overlayTextFor({ state: STATE_LOST }), LOSE_TEXT);
  assert.strictEqual(overlayTextFor({ state: STATE_PLAYING }), '');
});

test('Renderer: renderOverlay paints the end-of-game panel text', () => {
  const canvas = makeCanvas();
  const renderer = new Renderer(canvas);
  renderer.renderOverlay({ state: STATE_LOST });
  const [text] = canvas.ctx.calls.fillText[0];
  assert.strictEqual(text, LOSE_TEXT);
});

test('Renderer: render paints background, bricks, paddle, ball and HUD', () => {
  const canvas = makeCanvas();
  const renderer = new Renderer(canvas);
  const engine = new Engine({ seed: 1 });
  renderer.render(engine);
  assert.ok(canvas.ctx.calls.fillRect.length > GAME_DIMENSIONS.BRICK_COUNT);
  assert.strictEqual(canvas.ctx.calls.arc.length, 1);
  assert.strictEqual(canvas.ctx.calls.fillText.length, 1);
});

// --- orchestration (main) -------------------------------------------------------

test('main: createGame exposes the inspectable state on window.__game', () => {
  const env = makeEnv();
  createGame({ window: env.window, document: env.document, seed: 4 });

  const published = env.window.__game;
  assert.strictEqual(typeof published.paddle.x, 'number');
  assert.strictEqual(typeof published.ball.x, 'number');
  assert.strictEqual(typeof published.ball.vy, 'number');
  assert.strictEqual(published.bricksRemaining, GAME_DIMENSIONS.BRICK_COUNT);
  assert.strictEqual(published.state, STATE_PLAYING);
  assert.strictEqual(published.over, false);
  assert.strictEqual(typeof env.window.__game_debug.hit, 'function');
});

test('main: the objective is written outside the canvas and follows the wall', () => {
  const env = makeEnv();
  const game = createGame({ window: env.window, document: env.document, seed: 4 });
  assert.ok(env.objectif.textContent.length > 0, 'le HUD objectif porte un texte non vide');
  assert.strictEqual(env.objectif.textContent, objectiveTextFor(game.engine));

  game.engine.destroyBrick(game.engine.bricks[0]);
  game.step();
  assert.ok(env.objectif.textContent.includes(String(game.engine.bricksRemaining)),
    'le HUD suit le nombre de briques restantes');
});

test('main: the overlay stays hidden while playing', () => {
  const env = makeEnv();
  const game = createGame({ window: env.window, document: env.document, seed: 4 });
  game.step();
  assert.ok(env.overlay.classList.contains('hidden'),
    'aucun panneau de fin tant que la partie tourne');
  assert.strictEqual(env.overlayText.textContent, '');
});

test('main: __game_debug.hit() forces the defeat panel and publishes the state', () => {
  const env = makeEnv();
  createGame({ window: env.window, document: env.document, seed: 4 });
  env.window.__game_debug.hit();

  assert.strictEqual(env.window.__game.state, STATE_LOST);
  assert.strictEqual(env.window.__game.over, true);
  assert.strictEqual(env.overlayText.textContent, LOSE_TEXT);
  assert.strictEqual(env.overlay.classList.contains('hidden'), false);
});

test('main: __game_debug.forceWin() empties the wall and shows the victory panel', () => {
  const env = makeEnv();
  createGame({ window: env.window, document: env.document, seed: 4 });
  env.window.__game_debug.forceWin();

  assert.strictEqual(env.window.__game.bricksRemaining, 0);
  assert.strictEqual(env.window.__game.state, STATE_WON);
  assert.strictEqual(env.overlayText.textContent, WIN_TEXT);
  assert.strictEqual(env.overlay.classList.contains('hidden'), false);
});

test('main: clicking #restart brings back a full wall and a playing state', () => {
  const env = makeEnv();
  createGame({ window: env.window, document: env.document, seed: 4 });
  env.window.__game_debug.forceWin();
  env.restart.fire('click');

  assert.strictEqual(env.window.__game.state, STATE_PLAYING);
  assert.strictEqual(env.window.__game.bricksRemaining, GAME_DIMENSIONS.BRICK_COUNT);
  assert.ok(env.overlay.classList.contains('hidden'));
});

test('main: a held key reaches the paddle through one step', () => {
  const env = makeEnv();
  const game = createGame({ window: env.window, document: env.document, seed: 4 });
  const before = env.window.__game.paddle.x;

  env.window.fire('keydown', { key: KEY_RIGHT });
  game.step();
  assert.ok(env.window.__game.paddle.x > before, 'Flèche droite déplace la raquette');

  env.window.fire('keyup', { key: KEY_RIGHT });
  env.window.fire('keydown', { key: KEY_LEFT });
  const middle = env.window.__game.paddle.x;
  game.step();
  assert.ok(env.window.__game.paddle.x < middle, 'Flèche gauche déplace la raquette');
});

test('main: start queues an animation frame and stop cancels it', () => {
  const env = makeEnv();
  const game = createGame({ window: env.window, document: env.document, seed: 4 });
  const id = game.start();
  assert.strictEqual(env.window.frames.length, 1);
  game.stop();
  assert.strictEqual(env.window.cancelled, id);
});

test('main: autoBootstrap defers to DOMContentLoaded while the document is loading', () => {
  const loading = makeEnv({ readyState: 'loading' });
  assert.strictEqual(autoBootstrap(loading.window, loading.document), null);
  assert.strictEqual(loading.window.listenerCount('DOMContentLoaded'), 1);
  assert.strictEqual(loading.window.__game, undefined);

  loading.window.fire('DOMContentLoaded');
  assert.strictEqual(loading.window.__game.state, STATE_PLAYING);

  const ready = makeEnv({ readyState: 'complete' });
  const game = autoBootstrap(ready.window, ready.document);
  assert.ok(game, 'un document prêt démarre immédiatement');
  assert.strictEqual(ready.window.__game.state, STATE_PLAYING);
});

test('main: seedFromLocation reads ?seed= and falls back to the default', () => {
  assert.strictEqual(seedFromLocation({ location: { search: '?seed=888' } }), 888);
  assert.strictEqual(seedFromLocation({ location: { search: '' } }), DEFAULT_SEED);
  assert.strictEqual(seedFromLocation({ location: { search: '?seed=abc' } }), DEFAULT_SEED);
  assert.strictEqual(seedFromLocation(null), DEFAULT_SEED, 'aucune fenêtre => seed par défaut');
});
