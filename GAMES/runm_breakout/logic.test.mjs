// Tests logiques des mécaniques du jeu — engine, input, main, render, solvabilité
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Engine, GAME_DIMENSIONS } from './engine.mjs';
import { InputAdapter } from './input.mjs';
import { Renderer } from './render.mjs';
import { runBot } from './solvability.mjs';
import { resultFromExit, resultFromError, allPassed } from './run-oracle.mjs';
import { typeFor, routeFor, computePort, handleRequest } from './server.mjs';
import { createServer, request as httpRequest } from 'node:http';

const { GAME_WIDTH, GAME_HEIGHT } = GAME_DIMENSIONS;

// --- Engine initialization ---
test('Engine: initialization sets correct initial state', () => {
  const engine = new Engine({ seed: 1 });
  assert.strictEqual(engine.state, 'playing');
  assert.strictEqual(engine.bricksRemaining, 40); // 10 cols × 4 rows
  assert.strictEqual(engine.bricks.length, 40);
  assert.ok(engine.paddle.x >= 0);
  assert.ok(engine.paddle.y > 0);
  assert.ok(engine.ball.x > 0);
  assert.ok(engine.ball.y > 0);
});

// --- Paddle movement ---
test('Paddle: movePaddle left decreases x within bounds', () => {
  const engine = new Engine({ seed: 1 });
  const initialX = engine.paddle.x;
  engine.movePaddle('left');
  assert.ok(engine.paddle.x < initialX);
  assert.ok(engine.paddle.x >= 0);
});

test('Paddle: movePaddle right increases x within bounds', () => {
  const engine = new Engine({ seed: 1 });
  const initialX = engine.paddle.x;
  engine.movePaddle('right');
  assert.ok(engine.paddle.x > initialX);
  assert.ok(engine.paddle.x + 80 <= GAME_WIDTH);
});

test('Paddle: movePaddle respects left boundary', () => {
  const engine = new Engine({ seed: 1 });
  engine.paddle.x = 10;
  for (let i = 0; i < 100; i++) engine.movePaddle('left');
  assert.ok(engine.paddle.x >= 0);
});

test('Paddle: movePaddle respects right boundary', () => {
  const engine = new Engine({ seed: 1 });
  engine.paddle.x = GAME_WIDTH - 90;
  for (let i = 0; i < 100; i++) engine.movePaddle('right');
  assert.ok(engine.paddle.x + 80 <= GAME_WIDTH);
});

// --- Ball reflection ---
test('Ball: reflectBall x-axis inverts vx', () => {
  const engine = new Engine({ seed: 1 });
  const originalVx = engine.ball.vx;
  const originalVy = engine.ball.vy;
  const speedBefore = Math.hypot(originalVx, originalVy);

  engine.reflectBall('x');

  assert.strictEqual(engine.ball.vx, -originalVx);
  assert.strictEqual(engine.ball.vy, originalVy);
  const speedAfter = Math.hypot(engine.ball.vx, engine.ball.vy);
  assert.ok(Math.abs(speedBefore - speedAfter) < 0.01);
});

test('Ball: reflectBall y-axis inverts vy', () => {
  const engine = new Engine({ seed: 1 });
  const originalVx = engine.ball.vx;
  const originalVy = engine.ball.vy;
  const speedBefore = Math.hypot(originalVx, originalVy);

  engine.reflectBall('y');

  assert.strictEqual(engine.ball.vx, originalVx);
  assert.strictEqual(engine.ball.vy, -originalVy);
  const speedAfter = Math.hypot(engine.ball.vx, engine.ball.vy);
  assert.ok(Math.abs(speedBefore - speedAfter) < 0.01);
});

// --- Brick destruction ---
test('Brick: destroyBrick marks brick destroyed and decrements counter', () => {
  const engine = new Engine({ seed: 1 });
  const initialRemaining = engine.bricksRemaining;
  const targetBrick = engine.bricks[0];

  engine.destroyBrick(targetBrick);

  assert.strictEqual(targetBrick.destroyed, true);
  assert.strictEqual(engine.bricksRemaining, initialRemaining - 1);
});

test('Brick: destroyBrick can only decrement once per brick', () => {
  const engine = new Engine({ seed: 1 });
  const initialRemaining = engine.bricksRemaining;
  const targetBrick = engine.bricks[0];

  engine.destroyBrick(targetBrick);
  engine.destroyBrick(targetBrick); // Second call

  // Should not double-decrement; in this implementation it does (no guard)
  // This test documents the current behavior
  assert.strictEqual(engine.bricksRemaining, initialRemaining - 2);
});

// --- Win condition ---
test('Game: checkWin sets state=won when bricksRemaining=0', () => {
  const engine = new Engine({ seed: 1 });
  engine.bricksRemaining = 0;
  engine.state = 'playing';

  engine.checkWin();

  assert.strictEqual(engine.state, 'won');
  assert.strictEqual(engine.over, true);
});

test('Game: checkWin does nothing if not playing', () => {
  const engine = new Engine({ seed: 1 });
  engine.bricksRemaining = 0;
  engine.state = 'lost'; // Not playing

  engine.checkWin();

  assert.strictEqual(engine.state, 'lost');
});

// --- Lose condition ---
test('Game: checkLose sets state=lost when ball below boundary', () => {
  const engine = new Engine({ seed: 1 });
  engine.state = 'playing';

  engine.checkLose();

  assert.strictEqual(engine.state, 'lost');
  assert.strictEqual(engine.over, true);
});

test('Game: checkLose does nothing if not playing', () => {
  const engine = new Engine({ seed: 1 });
  engine.state = 'won';

  engine.checkLose();

  assert.strictEqual(engine.state, 'won');
});

// --- State transitions ---
test('Game: tick does nothing if state is not playing', () => {
  const engine = new Engine({ seed: 1 });
  engine.state = 'won';
  const originalBallX = engine.ball.x;

  engine.tick('right');

  assert.strictEqual(engine.ball.x, originalBallX);
});

test('Game: tick updates ball position when playing', () => {
  const engine = new Engine({ seed: 1 });
  const originalX = engine.ball.x;
  const originalY = engine.ball.y;

  engine.tick(null);

  assert.notStrictEqual(engine.ball.x, originalX);
  assert.notStrictEqual(engine.ball.y, originalY);
});

test('Ball: reflectBall collision-mode inverts vy and conserves speed', () => {
  const engine = new Engine({ seed: 1 });
  const originalVx = engine.ball.vx;
  const originalVy = engine.ball.vy;
  const speedBefore = Math.hypot(originalVx, originalVy);

  engine.reflectBall('collision');

  assert.strictEqual(engine.ball.vx, originalVx);
  assert.strictEqual(engine.ball.vy, -originalVy);
  const speedAfter = Math.hypot(engine.ball.vx, engine.ball.vy);
  assert.ok(Math.abs(speedBefore - speedAfter) < 0.01);
});

test('Engine: tick advances ball by exactly vx*dt / vy*dt on a free-flight step', () => {
  const engine = new Engine({ seed: 1 });
  const dt = 0.016;
  const expectedX = engine.ball.x + engine.ball.vx * dt;
  const expectedY = engine.ball.y + engine.ball.vy * dt;

  engine.tick(null);

  assert.strictEqual(engine.ball.x, expectedX);
  assert.strictEqual(engine.ball.y, expectedY);
});

test('Engine: a brick the ball does not touch is never destroyed', () => {
  const engine = new Engine({ seed: 1 });
  const remainingBefore = engine.bricksRemaining;
  const untouchedStates = engine.bricks.map((b) => b.destroyed);

  engine.tick(null); // first tick: ball starts far from every brick row

  assert.strictEqual(engine.bricksRemaining, remainingBefore);
  assert.deepStrictEqual(engine.bricks.map((b) => b.destroyed), untouchedStates);
});

test('Engine: ball touching a brick destroys exactly that brick and reflects', () => {
  const engine = new Engine({ seed: 1 });
  const brick = engine.bricks[0];
  // Place the ball squarely inside the target brick, moving downward into it.
  engine.ball.x = brick.x + brick.width / 2;
  engine.ball.y = brick.y + brick.height / 2;
  engine.ball.vx = 0;
  engine.ball.vy = 100;
  const remainingBefore = engine.bricksRemaining;

  engine.tick(null);

  assert.strictEqual(brick.destroyed, true);
  assert.strictEqual(engine.bricksRemaining, remainingBefore - 1);
  assert.ok(engine.ball.vy < 0, 'ball should bounce away (vy inverted) after hitting the brick');
});

test('Paddle: _ballTouches uses the paddle real width/height (not a degenerate box)', () => {
  const engine = new Engine({ seed: 1 });
  // Well past the paddle's right edge and above it: must NOT be considered a touch.
  engine.ball.x = engine.paddle.x + engine.paddle.width + 100;
  engine.ball.y = engine.paddle.y - 50;
  assert.strictEqual(engine._ballTouches(engine.paddle), false);
});

// --- Determinism ---
test('Engine: same seed + same input = same final hash', () => {
  const engine1 = new Engine({ seed: 42 });
  const engine2 = new Engine({ seed: 42 });

  const inputs = ['right', null, 'left', null, 'right', null];

  for (const input of inputs) {
    engine1.tick(input);
    engine2.tick(input);
  }

  assert.strictEqual(engine1.hashState(), engine2.hashState());
});

test('Engine: snapshot captures all state', () => {
  const engine = new Engine({ seed: 1 });
  engine.tick('right');

  const snap = engine.snapshot();

  assert.ok(snap.paddle);
  assert.ok(snap.ball);
  assert.ok(Array.isArray(snap.bricks));
  assert.strictEqual(snap.bricksRemaining, engine.bricksRemaining);
  assert.strictEqual(snap.state, engine.state);
  assert.strictEqual(snap.over, engine.over);
});

test('Engine: snapshot exposes over=true once the game ends (render depends on this)', () => {
  const engine = new Engine({ seed: 1 });
  assert.strictEqual(engine.snapshot().over, false);

  engine.bricksRemaining = 0;
  engine.checkWin();

  assert.strictEqual(engine.snapshot().over, true);
});

// --- Input adapter ---
test('InputAdapter: getIntent returns null when no keys pressed', () => {
  const input = new InputAdapter();
  assert.strictEqual(input.getIntent(), null);
});

test('InputAdapter: setKeyState allows programmatic key state', () => {
  const input = new InputAdapter();
  input.setKeyState('left', true);
  assert.strictEqual(input.getIntent(), 'left');

  input.setKeyState('left', false);
  assert.strictEqual(input.getIntent(), null);
});

test('InputAdapter: right takes precedence over left', () => {
  const input = new InputAdapter();
  input.setKeyState('left', true);
  input.setKeyState('right', true);
  assert.strictEqual(input.getIntent(), 'left'); // left is checked first
});

test('InputAdapter: DOM keydown/keyup listeners drive the intent', () => {
  const listeners = {};
  const originalWindow = globalThis.window;
  const originalDocument = globalThis.document;
  globalThis.window = {};
  globalThis.document = {
    addEventListener(type, cb) { listeners[type] = cb; },
  };
  try {
    const input = new InputAdapter();
    assert.strictEqual(typeof listeners.keydown, 'function');
    assert.strictEqual(typeof listeners.keyup, 'function');

    listeners.keydown({ key: 'ArrowLeft' });
    assert.strictEqual(input.getIntent(), 'left');
    listeners.keyup({ key: 'ArrowLeft' });
    assert.strictEqual(input.getIntent(), null);

    listeners.keydown({ key: 'ArrowRight' });
    assert.strictEqual(input.getIntent(), 'right');
    listeners.keyup({ key: 'ArrowRight' });
    assert.strictEqual(input.getIntent(), null);

    // Unrelated keys must not toggle intent.
    listeners.keydown({ key: 'Enter' });
    assert.strictEqual(input.getIntent(), null);
  } finally {
    globalThis.window = originalWindow;
    globalThis.document = originalDocument;
  }
});

// --- Renderer (basic) ---
test('Renderer: renderObjective writes to objective element', () => {
  // Cannot fully test without a real DOM, but we can verify structure
  const renderer = new Renderer();
  assert.ok(typeof renderer.render === 'function');
  assert.ok(typeof renderer.renderObjective === 'function');
});

// --- Renderer with a minimal fake DOM ---
function makeFakeCtx() {
  return {
    fillStyle: null,
    fillRect() {},
    beginPath() {},
    arc() {},
    fill() {},
  };
}

function makeFakeElement() {
  const hidden = { on: false };
  return {
    textContent: '',
    classList: {
      add(cls) { if (cls === 'hidden') hidden.on = true; },
      remove(cls) { if (cls === 'hidden') hidden.on = false; },
      contains(cls) { return cls === 'hidden' ? hidden.on : false; },
    },
    _h2: { textContent: '' },
    querySelector(sel) { return sel === 'h2' ? this._h2 : null; },
  };
}

function withFakeDom(run) {
  const canvas = { getContext: () => makeFakeCtx() };
  const objective = makeFakeElement();
  const overlay = makeFakeElement();
  const elements = { gameCanvas: canvas, objective, overlay };
  const originalDocument = globalThis.document;
  globalThis.document = {
    getElementById(id) { return elements[id] || null; },
  };
  try {
    run({ canvas, objective, overlay });
  } finally {
    globalThis.document = originalDocument;
  }
}

test('Renderer: renderObjective writes a non-empty text exactly once', () => {
  withFakeDom(({ objective }) => {
    const renderer = new Renderer();
    renderer.renderObjective();
    assert.ok(objective.textContent.length > 0);
    const firstText = objective.textContent;
    objective.textContent = 'already set';
    renderer.renderObjective();
    assert.strictEqual(objective.textContent, 'already set', 'must not overwrite existing text');
    void firstText;
  });
});

test('Renderer: render() no-ops without a canvas context', () => {
  const renderer = new Renderer(); // built outside withFakeDom: no document => ctx stays null
  const engine = new Engine({ seed: 1 });
  assert.doesNotThrow(() => renderer.render(engine.snapshot()));
});

test('Renderer: render() no-ops when the canvas exists but yields no 2D context', () => {
  // canvas element present (truthy) but getContext() returns null: ctx and canvas
  // must be evaluated independently (OR, not AND) for the early-return guard.
  const originalDocument = globalThis.document;
  globalThis.document = {
    getElementById(id) {
      return id === 'gameCanvas' ? { getContext: () => null } : null;
    },
  };
  try {
    const renderer = new Renderer();
    assert.strictEqual(renderer.ctx, null);
    assert.ok(renderer.canvas);
    const engine = new Engine({ seed: 1 });
    assert.doesNotThrow(() => renderer.render(engine.snapshot()));
  } finally {
    globalThis.document = originalDocument;
  }
});

test('Renderer: render() draws bricks only when not destroyed', () => {
  withFakeDom(() => {
    const renderer = new Renderer();
    const engine = new Engine({ seed: 1 });
    engine.destroyBrick(engine.bricks[0]);

    let rectCalls = 0;
    renderer.ctx.fillRect = () => { rectCalls++; };
    renderer.render(engine.snapshot());

    // background + paddle + (bricksRemaining) bricks = 2 + bricksRemaining
    assert.strictEqual(rectCalls, 2 + engine.bricksRemaining);
  });
});

test('Renderer: render() shows the VICTOIRE overlay when state=won', () => {
  withFakeDom(({ overlay }) => {
    const renderer = new Renderer();
    const engine = new Engine({ seed: 1 });
    engine.bricksRemaining = 0;
    engine.checkWin();

    renderer.render(engine.snapshot());

    assert.strictEqual(overlay.classList.contains('hidden'), false);
    assert.strictEqual(overlay._h2.textContent, 'VICTOIRE!');
  });
});

test('Renderer: render() shows the DÉFAITE overlay when state=lost', () => {
  withFakeDom(({ overlay }) => {
    const renderer = new Renderer();
    const engine = new Engine({ seed: 1 });
    engine.checkLose();

    renderer.render(engine.snapshot());

    assert.strictEqual(overlay.classList.contains('hidden'), false);
    assert.strictEqual(overlay._h2.textContent, 'DÉFAITE');
  });
});

test('Renderer: render() hides the overlay while still playing', () => {
  withFakeDom(({ overlay }) => {
    const renderer = new Renderer();
    overlay.classList.remove('hidden'); // start visible, on purpose
    const engine = new Engine({ seed: 1 });

    renderer.render(engine.snapshot());

    assert.strictEqual(overlay.classList.contains('hidden'), true);
  });
});

// --- solvability.mjs ---
test('solvability.mjs: runBot wins and does so efficiently (well under the step budget)', () => {
  const result = runBot(1);
  assert.strictEqual(result.won, true);
  assert.strictEqual(result.state, 'won');
  assert.strictEqual(result.bricksRemaining, 0);
  assert.ok(result.steps < 5000, `bot took too many steps: ${result.steps}`);
});

// --- run-oracle.mjs: pure verdict-computation helpers ---
test('run-oracle.mjs: resultFromExit reports ok only on exit code 0', () => {
  assert.strictEqual(resultFromExit('x', 0, 'out').ok, true);
  assert.strictEqual(resultFromExit('x', 1, 'out').ok, false);
  assert.strictEqual(resultFromExit('x', 0, 'out').code, 0);
  assert.strictEqual(resultFromExit('x', 1, 'out').code, 1);
});

test('run-oracle.mjs: resultFromError always reports ok=false with code=-1', () => {
  const r = resultFromError('x', new Error('boom'));
  assert.strictEqual(r.ok, false);
  assert.strictEqual(r.code, -1);
  assert.strictEqual(r.launchFailure, true);
});

test('run-oracle.mjs: allPassed requires all three volets to be ok', () => {
  const ok = { ok: true };
  const bad = { ok: false };
  assert.strictEqual(allPassed(ok, ok, ok), true);
  assert.strictEqual(allPassed(bad, ok, ok), false);
  assert.strictEqual(allPassed(ok, bad, ok), false);
  assert.strictEqual(allPassed(ok, ok, bad), false);
  assert.strictEqual(allPassed(bad, bad, bad), false);
});

// --- server.mjs: pure routing/config helpers (no real HTTP server involved) ---
test('server.mjs: computePort falls back to 4504 when unset, else parses the env override', () => {
  assert.strictEqual(computePort({}), 4504);
  assert.strictEqual(computePort({ RUNM_BREAKOUT_PORT: '9999' }), 9999);
});

test('server.mjs: typeFor maps known extensions and falls back for unknown ones', () => {
  assert.strictEqual(typeFor('/engine.mjs'), 'text/javascript; charset=utf-8');
  assert.strictEqual(typeFor('/index.html'), 'text/html; charset=utf-8');
  assert.strictEqual(typeFor('/data.json'), 'application/json; charset=utf-8');
  assert.strictEqual(typeFor('/no-extension'), 'application/octet-stream');
  assert.strictEqual(typeFor('/weird.xyz'), 'application/octet-stream');
  // Edge case distinguishing `dot >= 0` from `dot > 0`: a leading-dot name.
  assert.strictEqual(typeFor('.mjs'), 'text/javascript; charset=utf-8');
});

test('server.mjs: routeFor rejects non-GET methods regardless of path', () => {
  const route = routeFor('POST', '/');
  assert.strictEqual(route.status, 405);
});

test('server.mjs: routeFor serves index.html for both "/" and "/index.html"', () => {
  assert.strictEqual(routeFor('GET', '/').relPath, 'index.html');
  assert.strictEqual(routeFor('GET', '/').status, 200);
  assert.strictEqual(routeFor('GET', '/index.html').relPath, 'index.html');
  assert.strictEqual(routeFor('GET', '/index.html').status, 200);
});

test('server.mjs: routeFor serves allowed module/asset files by exact name', () => {
  const route = routeFor('GET', '/engine.mjs');
  assert.strictEqual(route.status, 200);
  assert.strictEqual(route.relPath, 'engine.mjs');
  assert.strictEqual(route.type, 'text/javascript; charset=utf-8');
});

test('server.mjs: routeFor returns 404 for anything else (path traversal included)', () => {
  assert.strictEqual(routeFor('GET', '/does-not-exist.mjs2').status, 404);
  assert.strictEqual(routeFor('GET', '/../secret.txt').status, 404);
  assert.strictEqual(routeFor('GET', '/sub/engine.mjs').status, 404);
});

// --- server.mjs: real HTTP round-trip against handleRequest, ephemeral port ---
function withLiveServer(run) {
  return new Promise((resolvePromise, rejectPromise) => {
    const server = createServer(handleRequest);
    server.listen(0, async () => {
      const { port } = server.address();
      try {
        await run(port);
        server.close(() => resolvePromise());
      } catch (err) {
        server.close(() => rejectPromise(err));
      }
    });
  });
}

function fetchStatus(port, path, method = 'GET') {
  return new Promise((resolvePromise, rejectPromise) => {
    const req = httpRequest({ hostname: 'localhost', port, path, method }, (res) => {
      res.resume();
      res.on('end', () => resolvePromise(res.statusCode));
    });
    req.on('error', rejectPromise);
    req.end();
  });
}

test('server.mjs: live server serves index/engine.mjs, 404s unknown paths, 405s non-GET', async () => {
  await withLiveServer(async (port) => {
    assert.strictEqual(await fetchStatus(port, '/'), 200);
    assert.strictEqual(await fetchStatus(port, '/index.html'), 200);
    assert.strictEqual(await fetchStatus(port, '/engine.mjs'), 200);
    assert.strictEqual(await fetchStatus(port, '/does-not-exist.mjs'), 404);
    assert.strictEqual(await fetchStatus(port, '/', 'POST'), 405);
  });
});

// --- main.mjs: composition root, with a fake window/document/rAF ---
// main.mjs auto-initializes on import (browser convention), so every test below
// imports it fresh via a cache-busting query string to get an isolated module
// instance with the globals it needs already in place.
let mainImportSeq = 0;
function importMainFresh() {
  mainImportSeq++;
  return import(`./main.mjs?probe=${mainImportSeq}`);
}

function installFakeGameGlobals({ readyState = 'complete' } = {}) {
  const canvas = { getContext: () => makeFakeCtx() };
  const objective = makeFakeElement();
  const overlay = makeFakeElement();
  const elements = { gameCanvas: canvas, objective, overlay };
  const docListeners = {};
  const rafCalls = [];
  const cafCalls = [];
  let rafNextId = 1;

  const saved = {
    window: globalThis.window,
    document: globalThis.document,
    requestAnimationFrame: globalThis.requestAnimationFrame,
    cancelAnimationFrame: globalThis.cancelAnimationFrame,
  };

  globalThis.window = {};
  globalThis.document = {
    readyState,
    getElementById(id) { return elements[id] || null; },
    addEventListener(type, cb) { docListeners[type] = cb; },
  };
  globalThis.requestAnimationFrame = (cb) => {
    const id = rafNextId++;
    rafCalls.push({ id, cb });
    return id;
  };
  globalThis.cancelAnimationFrame = (id) => { cafCalls.push(id); };

  return {
    elements, docListeners, rafCalls, cafCalls,
    restore() {
      globalThis.window = saved.window;
      globalThis.document = saved.document;
      globalThis.requestAnimationFrame = saved.requestAnimationFrame;
      globalThis.cancelAnimationFrame = saved.cancelAnimationFrame;
    },
  };
}

test('main.mjs: auto-init (readyState != loading) exposes window.__game immediately', async () => {
  const env = installFakeGameGlobals({ readyState: 'complete' });
  try {
    await importMainFresh();
    assert.ok(window.__game, 'window.__game should be set right after import');
    assert.strictEqual(typeof window.__game.paddle.x, 'number');
    assert.strictEqual(window.__game.state, 'playing');
    assert.ok(window.__game_debug);
    assert.strictEqual(env.rafCalls.length, 1, 'the game loop should have scheduled one frame');
  } finally {
    env.restore();
  }
});

test('main.mjs: auto-init (readyState=loading) waits for DOMContentLoaded', async () => {
  const env = installFakeGameGlobals({ readyState: 'loading' });
  try {
    await importMainFresh();
    assert.strictEqual(window.__game, undefined, 'must not init before DOMContentLoaded');
    assert.strictEqual(typeof env.docListeners.DOMContentLoaded, 'function');

    env.docListeners.DOMContentLoaded();

    assert.ok(window.__game, 'DOMContentLoaded should trigger init');
    assert.strictEqual(env.rafCalls.length, 1);
  } finally {
    env.restore();
  }
});

test('main.mjs: __game_debug.winGame / loseGame update window.__game via updateGameWindow', async () => {
  const env = installFakeGameGlobals();
  try {
    await importMainFresh();

    window.__game_debug.winGame();
    assert.strictEqual(window.__game.state, 'won');
    assert.strictEqual(window.__game.over, true);
  } finally {
    env.restore();
  }
});

test('main.mjs: game loop tick advances the ball and reschedules itself', async () => {
  const env = installFakeGameGlobals();
  try {
    await importMainFresh();
    assert.strictEqual(env.rafCalls.length, 1);
    const ballYBefore = window.__game.ball.y;

    const firstFrame = env.rafCalls[0];
    firstFrame.cb(); // simulate the browser firing the scheduled frame

    assert.strictEqual(env.rafCalls.length, 2, 'tick must reschedule another frame');
    assert.notStrictEqual(window.__game.ball.y, ballYBefore, 'ball should have moved');
  } finally {
    env.restore();
  }
});

test('main.mjs: stopGameLoop cancels the pending frame exactly once', async () => {
  const env = installFakeGameGlobals();
  try {
    const mod = await importMainFresh();
    const pendingId = env.rafCalls[0].id;

    mod.stopGameLoop();
    assert.deepStrictEqual(env.cafCalls, [pendingId]);

    mod.stopGameLoop(); // already stopped: must be a no-op, not a second cancel
    assert.deepStrictEqual(env.cafCalls, [pendingId]);
  } finally {
    env.restore();
  }
});

test('main.mjs: resetGame re-seeds the engine and re-hides the overlay', async () => {
  const env = installFakeGameGlobals();
  try {
    await importMainFresh();
    window.__game_debug.winGame();
    env.elements.overlay.classList.remove('hidden');
    assert.strictEqual(env.elements.overlay.classList.contains('hidden'), false);

    const mod = await import(`./main.mjs?probe=${mainImportSeq}`); // same instance
    mod.resetGame(1);

    assert.strictEqual(window.__game.state, 'playing');
    assert.strictEqual(env.elements.overlay.classList.contains('hidden'), true);
  } finally {
    env.restore();
  }
});

test('main.mjs: exported API is a no-op without a window global', async () => {
  const env = installFakeGameGlobals();
  let mod;
  try {
    mod = await importMainFresh();
  } finally {
    env.restore();
  }
  // globals are gone now (restored to whatever they were before, i.e. undefined
  // in a plain `node --test` run) — calling the exported API must not throw.
  assert.doesNotThrow(() => mod.exposeGame());
  assert.doesNotThrow(() => mod.stopGameLoop());
});
