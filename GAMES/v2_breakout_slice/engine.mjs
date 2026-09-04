// Moteur de jeu — logique pure, testable HORS navigateur.
// Ne dépend NI de input, NI de render, NI de main (architecture_contract).
// Déterminisme : toute la variabilité passe par le RNG seedé (mulberry32) ;
// à seed égal + entrées égales, le déroulé et le hash d'état sont identiques.

const GAME_WIDTH = 800;
const GAME_HEIGHT = 600;
const TICK_MS = 16;
const DT_SECONDS = TICK_MS / 1000;

const PADDLE_WIDTH = 80;
const PADDLE_HEIGHT = 12;
const PADDLE_SPEED = 300;
const PADDLE_MARGIN_BOTTOM = 30;
const PADDLE_Y = GAME_HEIGHT - PADDLE_MARGIN_BOTTOM;

const BALL_RADIUS = 5;
const BALL_SPEED = 340;
const BALL_START_OFFSET = 24;
// Part horizontale de la vitesse initiale, tirée au sort dans cet intervalle :
// bornée pour garantir une composante verticale toujours franche (pas de balle
// quasi-horizontale qui ne redescendrait jamais vers les briques).
const BALL_MIN_VX_RATIO = 0.35;
const BALL_MAX_VX_RATIO = 0.65;
// Contrôle du joueur : le point d'impact sur la raquette oriente le renvoi. Borné
// pour que la balle garde toujours une composante verticale franche.
const PADDLE_STEER_MAX = 0.8;

const BRICK_WIDTH = 60;
const BRICK_HEIGHT = 16;
const BRICK_COLS = 10;
const BRICK_ROWS = 4;
const BRICK_GAP = 4;
const BRICK_TOP = 40;

const RNG_STEP = 0x6d2b79f5;
const RNG_DIVISOR = 4294967296;

export const STATE_PLAYING = 'playing';
export const STATE_WON = 'won';
export const STATE_LOST = 'lost';

export const DIR_LEFT = 'left';
export const DIR_RIGHT = 'right';

export const AXIS_X = 'x';
export const AXIS_Y = 'y';

export const GAME_DIMENSIONS = {
  GAME_WIDTH,
  GAME_HEIGHT,
  PADDLE_WIDTH,
  PADDLE_SPEED,
  BALL_RADIUS,
  BALL_SPEED,
  DT_SECONDS,
  TICK_MS,
  BRICK_COUNT: BRICK_COLS * BRICK_ROWS,
};

function clamp(value, low, high) {
  if (value < low) return low;
  if (value > high) return high;
  return value;
}

function signOf(value) {
  return value < 0 ? -1 : 1;
}

/** Générateur pseudo-aléatoire mulberry32 : même seed => même suite, sans état global. */
export function makeRng(seed) {
  let state = Math.trunc(seed) >>> 0;
  return function next() {
    state = (state + RNG_STEP) >>> 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / RNG_DIVISOR;
  };
}

/** Contact cercle / rectangle aligné aux axes (point du rectangle le plus proche). */
function circleTouchesRect(cx, cy, radius, rect) {
  const closestX = clamp(cx, rect.x, rect.x + rect.width);
  const closestY = clamp(cy, rect.y, rect.y + rect.height);
  const dx = cx - closestX;
  const dy = cy - closestY;
  return dx * dx + dy * dy < radius * radius;
}

/** Hash textuel stable (djb2-like) : sert de signature d'état pour le déterminisme. */
function hashOf(value) {
  const str = JSON.stringify(value);
  let h = 0;
  for (let i = 0; i < str.length; i++) {
    h = ((h << 5) - h) + str.charCodeAt(i);
    h |= 0;
  }
  return (h >>> 0).toString(16);
}

export class Engine {
  constructor({ seed = 1 } = {}) {
    this.seed = seed;
    this.init();
  }

  init() {
    this.rng = makeRng(this.seed);
    this.paddle = {
      x: (GAME_WIDTH - PADDLE_WIDTH) / 2,
      y: PADDLE_Y,
      width: PADDLE_WIDTH,
      height: PADDLE_HEIGHT,
    };
    this.ball = this._initialBall();
    this.bricks = this._generateBricks();
    this.bricksRemaining = this.bricks.length;
    this.state = STATE_PLAYING;
    this.over = false;
    this.ticks = 0;
  }

  /** Balle de service : posée au-dessus de la raquette, direction tirée du RNG seedé. */
  _initialBall() {
    const ratio = BALL_MIN_VX_RATIO + this.rng() * (BALL_MAX_VX_RATIO - BALL_MIN_VX_RATIO);
    const sign = this.rng() < 0.5 ? -1 : 1;
    const vx = sign * BALL_SPEED * ratio;
    const vy = -Math.sqrt(BALL_SPEED * BALL_SPEED - vx * vx);
    return {
      x: this.paddle.x + PADDLE_WIDTH / 2,
      y: this.paddle.y - BALL_START_OFFSET,
      vx,
      vy,
    };
  }

  _generateBricks() {
    const bricks = [];
    const rowWidth = BRICK_COLS * (BRICK_WIDTH + BRICK_GAP) - BRICK_GAP;
    const offsetX = (GAME_WIDTH - rowWidth) / 2;
    for (let row = 0; row < BRICK_ROWS; row++) {
      for (let col = 0; col < BRICK_COLS; col++) {
        bricks.push({
          x: offsetX + col * (BRICK_WIDTH + BRICK_GAP),
          y: BRICK_TOP + row * (BRICK_HEIGHT + BRICK_GAP),
          width: BRICK_WIDTH,
          height: BRICK_HEIGHT,
          destroyed: false,
        });
      }
    }
    return bricks;
  }

  /** R2 — la raquette suit l'intention clavier, bornée à l'aire de jeu. */
  movePaddle(direction) {
    const step = PADDLE_SPEED * DT_SECONDS;
    if (direction === DIR_LEFT) {
      this.paddle.x = clamp(this.paddle.x - step, 0, GAME_WIDTH - PADDLE_WIDTH);
    } else if (direction === DIR_RIGHT) {
      this.paddle.x = clamp(this.paddle.x + step, 0, GAME_WIDTH - PADDLE_WIDTH);
    }
  }

  /** R3 — rebond conservatif : la composante concernée change de signe, |v| est conservée. */
  reflectBall(axis) {
    if (axis === AXIS_X) {
      this.ball.vx = -this.ball.vx;
    } else if (axis === AXIS_Y) {
      this.ball.vy = -this.ball.vy;
    }
  }

  /** R4 + R5 — une frappe détruit la brique et fait décroître le compteur d'exactement 1. */
  destroyBrick(brick) {
    brick.destroyed = true;
    this.bricksRemaining -= 1;
  }

  /** R6 — victoire terminale : mur vidé, partie figée. */
  checkWin() {
    if (this.bricksRemaining === 0 && this.state === STATE_PLAYING) {
      this.state = STATE_WON;
      this.over = true;
    }
  }

  /** R7 — défaite terminale : balle perdue, partie figée. */
  checkLose() {
    if (this.state === STATE_PLAYING) {
      this.state = STATE_LOST;
      this.over = true;
    }
  }

  tick(inputDirection) {
    if (this.state !== STATE_PLAYING) return;
    this.ticks += 1;

    this.movePaddle(inputDirection);

    this.ball.x += this.ball.vx * DT_SECONDS;
    this.ball.y += this.ball.vy * DT_SECONDS;

    this._bounceWalls();
    this._bouncePaddle();
    this._hitBricks();

    if (this.ball.y - BALL_RADIUS > GAME_HEIGHT) {
      this.checkLose();
    }
    this.checkWin();
  }

  _bounceWalls() {
    if (this.ball.x - BALL_RADIUS < 0 || this.ball.x + BALL_RADIUS > GAME_WIDTH) {
      this.reflectBall(AXIS_X);
      this.ball.x = clamp(this.ball.x, BALL_RADIUS, GAME_WIDTH - BALL_RADIUS);
    }
    if (this.ball.y - BALL_RADIUS < 0) {
      this.reflectBall(AXIS_Y);
      this.ball.y = BALL_RADIUS;
    }
  }

  /** Rebond raquette : seulement en descente, puis on repose la balle au-dessus
   *  de la raquette — sinon un second contact au tick suivant la collerait. */
  _bouncePaddle() {
    if (this.ball.vy > 0 && this._ballTouches(this.paddle)) {
      this.reflectBall(AXIS_Y);
      this._steerFromPaddle();
      this.ball.y = this.paddle.y - BALL_RADIUS;
    }
  }

  /** Contrôle joueur : le point d'impact oriente le renvoi, |v| reste conservée.
   *  Une part horizontale minimale est imposée pour qu'une balle renvoyée au
   *  centre ne reste jamais prisonnière d'une colonne verticale. */
  _steerFromPaddle() {
    const half = PADDLE_WIDTH / 2;
    const offset = clamp((this.ball.x - (this.paddle.x + half)) / half, -1, 1);
    const steer = offset * PADDLE_STEER_MAX;
    const ratio = Math.abs(steer) < BALL_MIN_VX_RATIO
      ? signOf(this.ball.vx) * BALL_MIN_VX_RATIO
      : steer;
    this.ball.vx = BALL_SPEED * ratio;
    this.ball.vy = -Math.sqrt(BALL_SPEED * BALL_SPEED - this.ball.vx * this.ball.vx);
  }

  _hitBricks() {
    for (const brick of this.bricks) {
      if (brick.destroyed === false && this._ballTouches(brick)) {
        this.destroyBrick(brick);
        this.reflectBall(AXIS_Y);
        return;
      }
    }
  }

  _ballTouches(rect) {
    return circleTouchesRect(this.ball.x, this.ball.y, BALL_RADIUS, rect);
  }

  /** R9 — signature d'état : deux exécutions identiques rendent le même hash. */
  hashState() {
    return hashOf({
      paddle: this.paddle.x,
      ball: this.ball,
      bricksRemaining: this.bricksRemaining,
      destroyed: this.bricks.map((b) => b.destroyed),
      state: this.state,
    });
  }

  /** Vue de lecture seule de l'état (consommée par render/main, jamais mutée par eux). */
  snapshot() {
    return {
      paddle: { x: this.paddle.x },
      ball: { x: this.ball.x, y: this.ball.y, vx: this.ball.vx, vy: this.ball.vy },
      bricksRemaining: this.bricksRemaining,
      state: this.state,
      over: this.over,
      ticks: this.ticks,
    };
  }
}
