// game.mjs — Collect Runner core logic. PURE: no DOM, no window, no canvas, no Math.random.
// Deterministic seeded RNG (xorshift32). All state is plain data readable via `view()`.

export const TOTAL_LEVELS = 3;

// --- physics / tuning constants (world units, dt in milliseconds) ---
export const GRAVITY = -0.0018; // units per ms^2 (negative = pulls player down)
export const JUMP_VELOCITY = 0.6; // units per ms, upward (positive) impulse on jump
export const BASE_SPEED = 0.15; // units per ms, forward auto-run speed
export const SPEED_MOD = 0.06; // left/right modulation applied to forward speed
export const MIN_SPEED = 0.05;
export const MAX_SPEED = 0.24;

export const PLAYER_WIDTH = 10;
export const OBSTACLE_WIDTH = 20;
export const COIN_WIDTH = 12;

// Level generation tuning — obstacles are spaced far apart relative to a full
// jump arc so a single well-timed jump always clears them (see solvability.mjs
// which measures the real jump arc instead of trusting these numbers blindly).
const OBSTACLE_START_MARGIN = 150;
const OBSTACLE_MIN_GAP = 150;
const OBSTACLE_GAP_JITTER = 60;
const LEVEL_BASE_LENGTH = 900;
const LEVEL_LENGTH_STEP = 250;
const MIN_OBSTACLES = 3;
const OBSTACLE_COUNT_JITTER = 3; // obstacleCount = MIN_OBSTACLES + [0, OBSTACLE_COUNT_JITTER)

/**
 * xorshift32 seeded PRNG. Returns a function producing floats in [0, 1).
 * Never use Math.random() in this module — determinism is a hard requirement.
 */
function xorshift32(seed) {
  let x = (seed >>> 0) || 0x9e3779b9;
  return function next() {
    x ^= x << 13;
    x >>>= 0;
    x ^= x >>> 17;
    x ^= x << 5;
    x >>>= 0;
    return x / 4294967296;
  };
}

function mixSeed(seed, levelIndex) {
  const mixed = (seed ^ Math.imul(levelIndex + 1, 0x9e3779b1)) >>> 0;
  return mixed || 1;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function overlaps1D(aX, aW, bX, bW) {
  return aX < bX + bW && aX + aW > bX;
}

/**
 * Generates one level deterministically from a seeded RNG stream.
 * Places one "elevated" coin directly above the midpoint of every obstacle:
 * the same jump that clears the obstacle collects the coin (solvable by
 * construction). Ground coins are sprinkled in the gaps between obstacles.
 */
function generateLevel(rng, levelIndex) {
  const obstacleCount = MIN_OBSTACLES + Math.floor(rng() * OBSTACLE_COUNT_JITTER);
  const obstacles = [];
  const coins = [];

  let x = OBSTACLE_START_MARGIN + Math.floor(rng() * 80);

  for (let i = 0; i < obstacleCount; i++) {
    obstacles.push({ x, width: OBSTACLE_WIDTH });
    coins.push({
      x: x + OBSTACLE_WIDTH / 2 - COIN_WIDTH / 2,
      width: COIN_WIDTH,
      elevated: true,
      collected: false,
    });

    const gap = OBSTACLE_MIN_GAP + Math.floor(rng() * OBSTACLE_GAP_JITTER);
    const groundCoinX = x + OBSTACLE_WIDTH + Math.floor(gap * 0.35);
    coins.push({
      x: groundCoinX,
      width: COIN_WIDTH,
      elevated: false,
      collected: false,
    });

    x += OBSTACLE_WIDTH + gap;
  }

  const minLength = LEVEL_BASE_LENGTH + levelIndex * LEVEL_LENGTH_STEP;
  const length = Math.max(minLength, x + 120);

  return { length, obstacles, coins };
}

export class CollectRunnerGame {
  /**
   * @param {number} seed - integer seed driving all level generation (deterministic).
   */
  constructor(seed = 1) {
    this.seed = (seed >>> 0) || 1;
    this.coins = 0;
    this.level = 1;
    this.over = false;
    this.won = false;
    this.x = 0;
    this.y = 0;
    this.vy = 0;
    this.onGround = true;
    this.elapsedMs = 0;
    this._loadLevel(this.level);
  }

  _loadLevel(levelIndex) {
    const rng = xorshift32(mixSeed(this.seed, levelIndex));
    const level = generateLevel(rng, levelIndex);
    this.levelLength = level.length;
    this.obstaclesOnLevel = level.obstacles;
    this.coinsOnLevel = level.coins;
    this.x = 0;
    this.y = 0;
    this.vy = 0;
    this.onGround = true;
  }

  /**
   * Advances the simulation by dtMs milliseconds given player input.
   * @param {number} dtMs
   * @param {{left?: boolean, right?: boolean, jump?: boolean}} input
   */
  step(dtMs, input = {}) {
    if (this.over) return this.view();
    if (!(dtMs > 0)) return this.view();

    const left = !!input.left;
    const right = !!input.right;
    const jump = !!input.jump;

    this.elapsedMs += dtMs;

    // Jump impulse resolves before gravity integration so a jump pressed
    // this frame is already airborne by the time collisions are checked.
    if (jump && this.onGround) {
      this.vy = JUMP_VELOCITY;
      this.onGround = false;
    }

    let speed = BASE_SPEED;
    if (right) speed += SPEED_MOD;
    if (left) speed -= SPEED_MOD;
    speed = clamp(speed, MIN_SPEED, MAX_SPEED);
    this.x += speed * dtMs;

    this.vy += GRAVITY * dtMs;
    this.y += this.vy * dtMs;
    if (this.y <= 0) {
      this.y = 0;
      this.vy = 0;
      this.onGround = true;
    } else {
      this.onGround = false;
    }

    // Obstacle collision: solid only when the player is on the ground —
    // any airborne pass over the obstacle's x-range is safe.
    for (const obstacle of this.obstaclesOnLevel) {
      if (this.onGround && overlaps1D(this.x, PLAYER_WIDTH, obstacle.x, obstacle.width)) {
        this.over = true;
        this.won = false;
        return this.view();
      }
    }

    // Coin collection: elevated coins require being airborne (the jump that
    // clears the obstacle above which they float); ground coins require
    // being on the ground.
    for (const coin of this.coinsOnLevel) {
      if (coin.collected) continue;
      if (!overlaps1D(this.x, PLAYER_WIDTH, coin.x, coin.width)) continue;
      if (coin.elevated ? !this.onGround : this.onGround) {
        coin.collected = true;
        this.coins += 1;
      }
    }

    if (this.x >= this.levelLength) {
      if (this.level >= TOTAL_LEVELS) {
        this.won = true;
        this.over = true;
      } else {
        this.level += 1;
        this._loadLevel(this.level);
      }
    }

    return this.view();
  }

  /** Read-only snapshot of the current state, safe to hand to a renderer. */
  view() {
    return {
      x: this.x,
      y: this.y,
      vy: this.vy,
      onGround: this.onGround,
      coins: this.coins,
      level: this.level,
      levelLength: this.levelLength,
      over: this.over,
      won: this.won,
      elapsedMs: this.elapsedMs,
      coinsOnLevel: this.coinsOnLevel.map((c) => ({ ...c })),
      obstaclesOnLevel: this.obstaclesOnLevel.map((o) => ({ ...o })),
    };
  }
}
