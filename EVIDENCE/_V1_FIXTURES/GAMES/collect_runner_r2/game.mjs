// game.mjs — Collect Runner core logic. PURE: no DOM, no window, no canvas, no Math.random().
// Deterministic RNG (xorshift32) drives level generation from a numeric seed.
// Physics convention: y <= 0, y === 0 is ground. Jumping sets vy negative (moving "up" on
// screen). Gravity is a positive constant added to vy each tick, pulling the player back
// toward y === 0. altitude = -y (>= 0) is how "high" the player currently is.

export const BASE_SPEED = 220; // px/s forward speed with no left/right held
export const LEFT_MULT = 0.4; // speed multiplier while holding left only
export const RIGHT_MULT = 1.8; // speed multiplier while holding right only
export const GRAVITY = 2000; // px/s^2, added to vy every tick
export const JUMP_VY = -700; // px/s, initial vertical velocity on jump (negative = up)

export const OBSTACLE_WIDTH = 20; // px, fixed width of every obstacle (and its coin's pickup zone)
export const OBSTACLE_MIN_H = 40; // px, min obstacle height (well under jump apex altitude)
export const OBSTACLE_MAX_H = 80; // px, max obstacle height
export const PLAYER_HALF_W = 10; // px, half-width of player's collision box

export const LEVEL_BASE_LENGTH = 1600; // px, length of level 0
export const LEVEL_LENGTH_STEP = 500; // px, extra length per level index
export const OBSTACLE_BASE_COUNT = 3; // obstacles in level 0
export const TOTAL_LEVELS = 3;

const OBSTACLE_MARGIN = 200; // px, keep obstacles away from the very start/end of a level
const OBSTACLE_JITTER = 40; // px, max jitter span applied to obstacle spacing (+/- 20)
const SUBSTEP_MS = 20; // ms, internal physics substep cap — avoids tunneling on large dt

/** Deterministic xorshift32 PRNG factory. Same seed => same sequence, always. */
export function makeRng(seed) {
  let s = (seed >>> 0) || 0x9e3779b9;
  return function rng() {
    s ^= s << 13;
    s >>>= 0;
    s ^= s >>> 17;
    s ^= s << 5;
    s >>>= 0;
    return s / 4294967296;
  };
}

/**
 * Generate the 3 deterministic levels for a given seed.
 * Every obstacle has a coin sitting directly above it (same x, same width):
 * clearing the obstacle with a jump collects the coin in the same step —
 * the level is solvable by construction, not by luck.
 */
export function generateLevels(seed) {
  const rng = makeRng(seed);
  const levels = [];
  for (let levelIndex = 0; levelIndex < TOTAL_LEVELS; levelIndex++) {
    const length = LEVEL_BASE_LENGTH + levelIndex * LEVEL_LENGTH_STEP;
    const count = OBSTACLE_BASE_COUNT + levelIndex;
    const gap = (length - 2 * OBSTACLE_MARGIN) / (count + 1);
    const obstacles = [];
    const coins = [];
    for (let i = 0; i < count; i++) {
      const jitter = (rng() - 0.5) * OBSTACLE_JITTER;
      const x = OBSTACLE_MARGIN + gap * (i + 1) + jitter;
      const height = OBSTACLE_MIN_H + rng() * (OBSTACLE_MAX_H - OBSTACLE_MIN_H);
      obstacles.push({ x, width: OBSTACLE_WIDTH, height });
      coins.push({ x, width: OBSTACLE_WIDTH, y: -(height + 20), collected: false });
    }
    levels.push({ length, obstacles, coins });
  }
  return levels;
}

function overlapsX(centerA, halfA, centerB, halfB) {
  return centerA + halfA > centerB - halfB && centerA - halfA < centerB + halfB;
}

export class CollectRunnerGame {
  constructor(options = {}) {
    const seed = options.seed !== undefined ? options.seed : 1;
    this.seed = seed;
    this.levels = generateLevels(seed);

    this.x = 0;
    this.y = 0; // <= 0 always; 0 === ground
    this.vy = 0;
    this.onGround = true;
    this.level = 0;
    this.coins = 0;
    this.over = false;
    this.won = false;

    // Deep-clone level 0's coin/obstacle arrays into "live" per-run state so collection
    // mutates a copy, not the shared level template (a fresh instance must start clean).
    this.coinsOnLevel = this.levels[0].coins.map((c) => ({ ...c }));
    this.obstaclesOnLevel = this.levels[0].obstacles.map((o) => ({ ...o }));
  }

  _loadLevel(levelIndex) {
    this.level = levelIndex;
    this.x = 0;
    this.y = 0;
    this.vy = 0;
    this.onGround = true;
    this.coinsOnLevel = this.levels[levelIndex].coins.map((c) => ({ ...c }));
    this.obstaclesOnLevel = this.levels[levelIndex].obstacles.map((o) => ({ ...o }));
  }

  _speedFor(input) {
    const left = !!(input && input.left);
    const right = !!(input && input.right);
    if (left && !right) return BASE_SPEED * LEFT_MULT;
    if (right && !left) return BASE_SPEED * RIGHT_MULT;
    return BASE_SPEED;
  }

  _tick(dtMs, input) {
    if (this.over) return;
    const dt = dtMs / 1000;

    // Horizontal movement
    const speed = this._speedFor(input);
    this.x += speed * dt;

    // Jump trigger (only from the ground; holding jump mid-air does nothing — no double jump)
    if (input && input.jump && this.onGround) {
      this.vy = JUMP_VY;
      this.onGround = false;
    }

    // Vertical physics
    if (!this.onGround) {
      this.vy += GRAVITY * dt;
      this.y += this.vy * dt;
      if (this.y >= 0) {
        this.y = 0;
        this.vy = 0;
        this.onGround = true;
      }
    }

    const altitude = -this.y;

    // Obstacle collision: contact while not high enough clears the obstacle => defeat.
    for (const obs of this.obstaclesOnLevel) {
      if (overlapsX(this.x, PLAYER_HALF_W, obs.x, obs.width / 2) && altitude < obs.height) {
        this.over = true;
        this.won = false;
        return;
      }
    }

    // Coin collection: same x-range as its obstacle. If we reach here without colliding,
    // we're either clear of every obstacle in this x-range or airborne above it — safe to collect.
    for (const coin of this.coinsOnLevel) {
      if (!coin.collected && overlapsX(this.x, PLAYER_HALF_W, coin.x, coin.width / 2)) {
        coin.collected = true;
        this.coins += 1;
      }
    }

    // Level completion
    const levelLength = this.levels[this.level].length;
    if (this.x >= levelLength) {
      if (this.level >= TOTAL_LEVELS - 1) {
        this.won = true;
        this.over = true;
      } else {
        this._loadLevel(this.level + 1);
      }
    }
  }

  /** Advance the simulation by dtMs milliseconds, applying `input` uniformly across
   * internal substeps. Substepping keeps collision/coin checks granular even if the
   * caller passes a large dtMs (e.g. after a slow frame or a backgrounded tab), which
   * would otherwise let the player tunnel straight through an obstacle or a coin. */
  step(dtMs, input) {
    if (this.over) return this.view();
    let remaining = Math.max(0, dtMs || 0);
    while (remaining > 0 && !this.over) {
      const d = Math.min(SUBSTEP_MS, remaining);
      this._tick(d, input);
      remaining -= d;
    }
    return this.view();
  }

  view() {
    return {
      x: this.x,
      y: this.y,
      vy: this.vy,
      onGround: this.onGround,
      level: this.level,
      coins: this.coins,
      over: this.over,
      won: this.won,
      coinsOnLevel: this.coinsOnLevel.map((c) => ({ ...c })),
      obstaclesOnLevel: this.obstaclesOnLevel.map((o) => ({ ...o })),
      levelLength: this.levels[this.level].length,
    };
  }
}
