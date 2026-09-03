// Moteur de Breakout — simulation déterministe pure.
// État: {paddle, ball, bricks, bricksRemaining, state}
// Aucune dépendance à render, input ou main.

const GAME_WIDTH = 800;
const GAME_HEIGHT = 600;

// Pas logique de la simulation. La valeur était écrite en dur, deux fois, sous la
// forme déjà convertie (`0.016`) : nommée ici, elle devient le pas DÉCLARÉ du moteur,
// lisible par un oracle comme par un humain. `16 / 1000` est bit à bit identique au
// littéral `0.016` — le déterminisme des états déjà mesurés est inchangé.
const TICK_MS = 16;
const DT_SECONDS = TICK_MS / 1000;

const PADDLE_WIDTH = 80;
const PADDLE_HEIGHT = 12;
const PADDLE_SPEED = 300;
const PADDLE_Y = GAME_HEIGHT - 30;

const BALL_RADIUS = 5;
const BALL_SPEED = 250;

const BRICK_WIDTH = 60;
const BRICK_HEIGHT = 16;
const BRICK_COLS = 10;
const BRICK_ROWS = 4;
const BRICK_GAP = 4;

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

function circleAabbCollide(cx, cy, cr, bx, by, bw, bh) {
  const closestX = clamp(cx, bx, bx + bw);
  const closestY = clamp(cy, by, by + bh);
  const dx = cx - closestX;
  const dy = cy - closestY;
  return dx * dx + dy * dy < cr * cr;
}

function simpleHash(state) {
  let h = 0;
  const str = JSON.stringify(state);
  for (let i = 0; i < str.length; i++) {
    h = ((h << 5) - h) + str.charCodeAt(i);
    h |= 0;
  }
  return Math.abs(h).toString(16);
}

export class Engine {
  constructor({ seed = 1 } = {}) {
    this.seed = seed;
    this.level = 1;
    this.init();
  }

  init() {
    this.paddle = {
      x: GAME_WIDTH / 2 - PADDLE_WIDTH / 2,
      y: PADDLE_Y,
      width: PADDLE_WIDTH,
      height: PADDLE_HEIGHT,
    };
    this.ball = {
      x: this.paddle.x + PADDLE_WIDTH / 2,
      y: this.paddle.y - 20,
      vx: BALL_SPEED * 0.6,
      vy: -BALL_SPEED * 0.8,
    };
    this.bricks = this._generateBricks();
    this.bricksRemaining = this.bricks.length;
    this.state = 'playing';
    this.over = false;
  }

  _generateBricks() {
    const bricks = [];
    const offsetX = (GAME_WIDTH - (BRICK_COLS * (BRICK_WIDTH + BRICK_GAP))) / 2;
    for (let row = 0; row < BRICK_ROWS; row++) {
      for (let col = 0; col < BRICK_COLS; col++) {
        bricks.push({
          x: offsetX + col * (BRICK_WIDTH + BRICK_GAP),
          y: 40 + row * (BRICK_HEIGHT + BRICK_GAP),
          width: BRICK_WIDTH,
          height: BRICK_HEIGHT,
          destroyed: false,
        });
      }
    }
    return bricks;
  }

  movePaddle(direction) {
    const step = PADDLE_SPEED * DT_SECONDS;
    if (direction === 'left') {
      this.paddle.x = clamp(this.paddle.x - step, 0, GAME_WIDTH - PADDLE_WIDTH);
    } else if (direction === 'right') {
      this.paddle.x = clamp(this.paddle.x + step, 0, GAME_WIDTH - PADDLE_WIDTH);
    }
  }

  tick(inputDirection) {
    if (this.state !== 'playing') return;

    if (inputDirection) {
      this.movePaddle(inputDirection);
    }

    this.ball.x += this.ball.vx * DT_SECONDS;
    this.ball.y += this.ball.vy * DT_SECONDS;

    // Rebond murs latéraux
    if (this.ball.x - BALL_RADIUS < 0 || this.ball.x + BALL_RADIUS > GAME_WIDTH) {
      this.reflectBall('x');
      this.ball.x = clamp(this.ball.x, BALL_RADIUS, GAME_WIDTH - BALL_RADIUS);
    }

    // Rebond plafond
    if (this.ball.y - BALL_RADIUS < 0) {
      this.reflectBall('y');
      this.ball.y = BALL_RADIUS;
    }

    // Rebond raquette
    if (this._ballTouches(this.paddle)) {
      this.reflectBall('y');
    }

    // Rebond briques
    for (const brick of this.bricks) {
      if (!brick.destroyed && this._ballTouches(brick)) {
        this.destroyBrick(brick);
        this.reflectBall('collision');
        break;
      }
    }

    // Défaite
    if (this.ball.y > GAME_HEIGHT) {
      this.checkLose();
    }

    // Victoire
    this.checkWin();
  }

  reflectBall(mode) {
    if (mode === 'x') {
      this.ball.vx = -this.ball.vx;
    } else if (mode === 'y') {
      this.ball.vy = -this.ball.vy;
    } else if (mode === 'collision') {
      this.ball.vy = -this.ball.vy;
    }
  }

  destroyBrick(brick) {
    brick.destroyed = true;
    this.bricksRemaining--;
  }

  checkWin() {
    if (this.bricksRemaining === 0 && this.state === 'playing') {
      this.state = 'won';
      this.over = true;
    }
  }

  checkLose() {
    if (this.state === 'playing') {
      this.state = 'lost';
      this.over = true;
    }
  }

  _ballTouches(rect) {
    return circleAabbCollide(
      this.ball.x, this.ball.y, BALL_RADIUS,
      rect.x, rect.y, rect.width, rect.height
    );
  }

  hashState() {
    return simpleHash({
      paddle: this.paddle,
      ball: this.ball,
      bricksRemaining: this.bricksRemaining,
      state: this.state,
    });
  }

  snapshot() {
    return {
      paddle: { x: this.paddle.x },
      ball: { x: this.ball.x, y: this.ball.y, vx: this.ball.vx, vy: this.ball.vy },
      bricks: this.bricks.map(b => ({ ...b })),
      bricksRemaining: this.bricksRemaining,
      state: this.state,
      over: this.over,
    };
  }
}

export const GAME_DIMENSIONS = { GAME_WIDTH, GAME_HEIGHT };
