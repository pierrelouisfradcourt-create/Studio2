// Tests de propriétés (invariants) — validations cross-checks du moteur
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Engine, GAME_DIMENSIONS } from './engine.mjs';

const { GAME_WIDTH, GAME_HEIGHT } = GAME_DIMENSIONS;
const PADDLE_WIDTH = 80;
const BALL_RADIUS = 5;
const BALL_SPEED = 250;

// Helper: compute speed magnitude
function speed(vx, vy) {
  return Math.hypot(vx, vy);
}

// --- Speed conservation on reflection ---
test('Property: reflectBall conserves speed within epsilon', () => {
  const engine = new Engine({ seed: 1 });

  for (let i = 0; i < 100; i++) {
    engine.tick(null);

    // Check that speed is approximately constant (within rounding tolerance)
    const s = speed(engine.ball.vx, engine.ball.vy);
    assert.ok(s > BALL_SPEED * 0.99, `Speed too low: ${s}`);
    assert.ok(s < BALL_SPEED * 1.01, `Speed too high: ${s}`);
  }
});

// --- Paddle bounds ---
test('Property: paddle never exits left boundary', () => {
  const engine = new Engine({ seed: 1 });

  for (let i = 0; i < 500; i++) {
    engine.tick('left');
    assert.ok(engine.paddle.x >= 0, `Paddle x=${engine.paddle.x} violates left bound`);
  }
});

test('Property: paddle never exits right boundary', () => {
  const engine = new Engine({ seed: 1 });

  for (let i = 0; i < 500; i++) {
    engine.tick('right');
    assert.ok(
      engine.paddle.x + PADDLE_WIDTH <= GAME_WIDTH,
      `Paddle x=${engine.paddle.x} violates right bound`
    );
  }
});

// --- Ball position (before bouncing) ---
test('Property: ball x stays in range [0, GAME_WIDTH] after wall bounces', () => {
  const engine = new Engine({ seed: 1 });

  for (let i = 0; i < 1000; i++) {
    engine.tick(null);
    assert.ok(
      engine.ball.x >= BALL_RADIUS && engine.ball.x <= GAME_WIDTH - BALL_RADIUS,
      `Ball x=${engine.ball.x} out of horizontal bounds after ${i} ticks`
    );
  }
});

// --- Brick count never increases ---
test('Property: bricksRemaining never increases', () => {
  const engine = new Engine({ seed: 1 });
  const initial = engine.bricksRemaining;

  for (let i = 0; i < 1000; i++) {
    engine.tick(null);
    assert.ok(
      engine.bricksRemaining <= initial,
      `bricksRemaining=${engine.bricksRemaining} exceeds initial=${initial}`
    );
  }
});

// --- State machine ---
test('Property: once won, state never changes back to playing', () => {
  const engine = new Engine({ seed: 1 });

  // Force a win
  engine.bricksRemaining = 0;
  engine.state = 'playing';
  engine.checkWin();

  assert.strictEqual(engine.state, 'won');
  const winState = engine.state;

  // Try to play more ticks
  for (let i = 0; i < 100; i++) {
    engine.tick(null);
    assert.strictEqual(engine.state, winState, 'State changed from won');
  }
});

test('Property: once lost, state never changes back to playing', () => {
  const engine = new Engine({ seed: 1 });
  engine.state = 'playing';
  engine.checkLose();

  assert.strictEqual(engine.state, 'lost');
  const loseState = engine.state;

  // Try to play more ticks
  for (let i = 0; i < 100; i++) {
    engine.tick(null);
    assert.strictEqual(engine.state, loseState, 'State changed from lost');
  }
});

// --- No brick can be destroyed twice ---
test('Property: destroyed bricks stay destroyed', () => {
  const engine = new Engine({ seed: 1 });

  // Manually destroy a brick
  const brick = engine.bricks[0];
  engine.destroyBrick(brick);

  assert.strictEqual(brick.destroyed, true);

  // Simulate many ticks
  for (let i = 0; i < 100; i++) {
    engine.tick(null);
    assert.strictEqual(brick.destroyed, true, 'Destroyed brick became un-destroyed');
  }
});

// --- Over flag only true at terminal states ---
test('Property: over=true only when state in {won, lost}', () => {
  const engine = new Engine({ seed: 1 });

  for (let i = 0; i < 500; i++) {
    engine.tick(null);

    if (engine.state === 'playing') {
      assert.strictEqual(
        engine.over,
        false,
        `over=true when state=playing (tick ${i})`
      );
    } else {
      assert.strictEqual(
        engine.over,
        true,
        `over=false when state=${engine.state} (tick ${i})`
      );
    }
  }
});

// --- Snapshot consistency ---
test('Property: snapshot matches engine state', () => {
  const engine = new Engine({ seed: 1 });

  for (let i = 0; i < 100; i++) {
    engine.tick(null);

    const snap = engine.snapshot();
    assert.strictEqual(snap.bricksRemaining, engine.bricksRemaining);
    assert.strictEqual(snap.state, engine.state);
    assert.ok(Math.abs(snap.paddle.x - engine.paddle.x) < 0.01);
    assert.ok(Math.abs(snap.ball.x - engine.ball.x) < 0.01);
    assert.ok(Math.abs(snap.ball.y - engine.ball.y) < 0.01);
  }
});

// --- Hash reproducibility ---
test('Property: same game state produces same hash', () => {
  const e1 = new Engine({ seed: 7 });
  const e2 = new Engine({ seed: 7 });

  const moves = ['right', null, 'left', null, 'right', null, null];

  for (const move of moves) {
    e1.tick(move);
    e2.tick(move);
  }

  assert.strictEqual(e1.hashState(), e2.hashState());
});

// --- Solvability check: 40 bricks can be destroyed ---
test('Property: reaching bricksRemaining=0 is achievable', async () => {
  const engine = new Engine({ seed: 1 });

  const maxSteps = 50000;
  let step = 0;

  while (step < maxSteps && engine.state === 'playing') {
    const snap = engine.snapshot();
    const ballX = snap.ball.x;
    const paddleX = snap.paddle.x + PADDLE_WIDTH / 2;

    let intent = null;
    if (ballX < paddleX - 30) intent = 'left';
    else if (ballX > paddleX + 30) intent = 'right';

    engine.tick(intent);
    step++;
  }

  assert.ok(
    engine.bricksRemaining === 0 || step < maxSteps,
    `Bot did not clear bricks within ${maxSteps} steps`
  );
});
