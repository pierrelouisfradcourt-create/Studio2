// Tests de propriétés — invariants tenus sur de longues séquences et plusieurs seeds.
// Complètent les tests unitaires : ici on ne vérifie pas UN cas, mais une propriété
// qui doit rester vraie pendant toute une partie.

import { test } from 'node:test';
import assert from 'node:assert';

import {
  Engine, GAME_DIMENSIONS, STATE_PLAYING, STATE_WON, STATE_LOST,
  DIR_LEFT, DIR_RIGHT, AXIS_X, AXIS_Y,
} from './engine.mjs';

const { GAME_WIDTH, PADDLE_WIDTH, BALL_SPEED, BALL_RADIUS } = GAME_DIMENSIONS;

const SEEDS = [1, 2, 3, 4, 5, 6, 7, 8];
// Balayage d'invariants : un début de partie suffit, l'invariant est vérifié à CHAQUE tick.
const MAX_TICKS = 3000;
// Parties menées jusqu'au bout (terminaison, rejeu) : budget large, moins de seeds.
const FULL_GAME_SEEDS = [1, 2, 3];
const FULL_GAME_BUDGET = 25000;

function speedOf(ball) {
  return Math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy);
}

/** Bot de suivi : ramène la raquette sous la balle — sert de pilote aux propriétés. */
function trackingIntent(engine) {
  const paddleCenter = engine.paddle.x + engine.paddle.width / 2;
  if (engine.ball.x < paddleCenter - 4) return DIR_LEFT;
  if (engine.ball.x > paddleCenter + 4) return DIR_RIGHT;
  return null;
}

test('reflectBall conserves speed on both axes', () => {
  for (const seed of SEEDS) {
    const engine = new Engine({ seed });
    const speed = speedOf(engine.ball);
    engine.reflectBall(AXIS_X);
    assert.ok(Math.abs(speedOf(engine.ball) - speed) < 1e-9);
    engine.reflectBall(AXIS_Y);
    assert.ok(Math.abs(speedOf(engine.ball) - speed) < 1e-9);
  }
});

test('the served ball always carries the nominal speed, whatever the seed', () => {
  for (let seed = 1; seed <= 40; seed++) {
    const engine = new Engine({ seed });
    assert.ok(Math.abs(speedOf(engine.ball) - BALL_SPEED) < 1e-9,
      `seed ${seed} : vitesse initiale hors norme`);
    assert.ok(engine.ball.vy < 0, `seed ${seed} : la balle doit partir vers le haut`);
  }
});

test('a paddle bounce sends the ball back up and conserves its speed', () => {
  const offsets = [-1, -0.5, 0, 0.4, 1];
  for (const offset of offsets) {
    const engine = new Engine({ seed: 1 });
    const half = PADDLE_WIDTH / 2;
    engine.ball = {
      x: engine.paddle.x + half + offset * half,
      y: engine.paddle.y - BALL_RADIUS,
      vx: 0,
      vy: BALL_SPEED,
    };
    engine.tick(null);
    assert.ok(engine.ball.vy < 0, `offset ${offset} : la balle doit repartir vers le haut`);
    assert.ok(Math.abs(speedOf(engine.ball) - BALL_SPEED) < 1e-9,
      `offset ${offset} : |v| doit être conservée`);
    assert.ok(Math.abs(engine.ball.vx) > 0,
      `offset ${offset} : la balle garde une composante horizontale`);
  }
});

test('the paddle never leaves the play field', () => {
  const engine = new Engine({ seed: 2 });
  for (let i = 0; i < 600; i++) {
    engine.tick(i % 2 === 0 ? DIR_LEFT : DIR_RIGHT);
    assert.ok(engine.paddle.x >= 0);
    assert.ok(engine.paddle.x + PADDLE_WIDTH <= GAME_WIDTH);
  }
});

test('the ball never crosses a side wall or the ceiling while the game runs', () => {
  for (const seed of SEEDS) {
    const engine = new Engine({ seed });
    for (let i = 0; i < MAX_TICKS && engine.state === STATE_PLAYING; i++) {
      engine.tick(trackingIntent(engine));
      assert.ok(engine.ball.x >= 0, `seed ${seed} : balle sortie à gauche`);
      assert.ok(engine.ball.x <= GAME_WIDTH, `seed ${seed} : balle sortie à droite`);
      assert.ok(engine.ball.y + BALL_RADIUS >= 0, `seed ${seed} : balle sortie par le haut`);
    }
  }
});

test('bricksRemaining always equals the number of intact bricks and never grows', () => {
  for (const seed of SEEDS) {
    const engine = new Engine({ seed });
    let previous = engine.bricksRemaining;
    for (let i = 0; i < MAX_TICKS && engine.state === STATE_PLAYING; i++) {
      engine.tick(trackingIntent(engine));
      const intact = engine.bricks.filter((brick) => brick.destroyed === false).length;
      assert.strictEqual(engine.bricksRemaining, intact);
      assert.ok(engine.bricksRemaining <= previous, 'le compteur ne remonte jamais');
      assert.ok(engine.bricksRemaining >= 0);
      previous = engine.bricksRemaining;
    }
  }
});

test('a terminal state is absorbing — won and lost never go back to playing', () => {
  for (const terminal of [STATE_WON, STATE_LOST]) {
    const engine = new Engine({ seed: 9 });
    engine.state = terminal;
    engine.over = true;
    for (let i = 0; i < 200; i++) engine.tick(DIR_RIGHT);
    assert.strictEqual(engine.state, terminal);
  }
});

test('the game always terminates within the tick budget under a tracking pilot', () => {
  for (const seed of FULL_GAME_SEEDS) {
    const engine = new Engine({ seed });
    let ticks = 0;
    while (ticks < FULL_GAME_BUDGET && engine.state === STATE_PLAYING) {
      engine.tick(trackingIntent(engine));
      ticks++;
    }
    assert.strictEqual(engine.state, STATE_WON,
      `seed ${seed} : partie non gagnée en ${FULL_GAME_BUDGET} ticks`);
    assert.strictEqual(engine.bricksRemaining, 0);
  }
});

test('identical seed and inputs produce an identical hash trajectory', () => {
  const inputs = [DIR_LEFT, null, DIR_RIGHT, DIR_RIGHT, null];
  for (const seed of SEEDS) {
    const a = new Engine({ seed });
    const b = new Engine({ seed });
    for (let i = 0; i < 500; i++) {
      const intent = inputs[i % inputs.length];
      a.tick(intent);
      b.tick(intent);
      assert.strictEqual(a.hashState(), b.hashState(), `seed ${seed} : divergence au tick ${i}`);
    }
  }
});

test('a replayed game reaches the same outcome as its first run', () => {
  for (const seed of FULL_GAME_SEEDS) {
    const play = () => {
      const engine = new Engine({ seed });
      let ticks = 0;
      while (ticks < FULL_GAME_BUDGET && engine.state === STATE_PLAYING) {
        engine.tick(trackingIntent(engine));
        ticks++;
      }
      return { state: engine.state, ticks, hash: engine.hashState() };
    };
    assert.deepStrictEqual(play(), play());
  }
});
