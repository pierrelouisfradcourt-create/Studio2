// game.mjs -- Survival Arena core logic.
// PURE: no DOM, no window, no canvas, no Math.random(). Deterministic via seeded RNG.
// step(dtMs, input) advances the simulation by dtMs milliseconds given
// input = { up, down, left, right } (booleans). view() returns a plain-object
// snapshot of the current state, safe to serialize (JSON) or hand to a renderer.

export const ARENA_WIDTH = 800;
export const ARENA_HEIGHT = 600;

export const PLAYER_RADIUS = 12;
export const PLAYER_SPEED = 200; // px / s
export const PLAYER_MAX_HP = 100;

export const ENEMY_RADIUS = 10;
export const ENEMY_SPEED = 60; // px / s -- strictly slower than the player so kiting is possible
export const ENEMY_CONTACT_DPS = 20; // damage per second while an enemy overlaps the player

export const BULLET_RADIUS = 4;
export const BULLET_SPEED = 400; // px / s

export const FIRE_INTERVAL_MS = 400; // auto-fire cadence -- kills at most one enemy per interval
export const SPAWN_INTERVAL_INITIAL_MS = 2000;
export const SPAWN_INTERVAL_MIN_MS = 400;
export const SPAWN_RAMP_MS = 10000; // every N ms of game time, spawn cadence tightens
export const SPAWN_DECAY = 0.85; // multiplier applied to spawnInterval at each ramp tick

// Once spawnInterval bottoms out it matches FIRE_INTERVAL_MS 1:1, which would
// let a perfectly stationary "turret" camper kill every incoming enemy before
// it ever lands a hit -- i.e. the game would be unloseable by standing still.
// Wave size growth guarantees spawn throughput eventually outpaces the single
// kill-per-interval auto-fire, forcing real pressure that only movement (not
// turtling) can outlast. ENEMY_CAP bounds worst-case entity count.
export const SPAWN_WAVE_GROWTH_RAMPS = 4; // every N ramp ticks, enemies-per-spawn +1
export const SPAWN_WAVE_MAX = 4;
export const ENEMY_CAP = 60;

export const SCORE_PER_KILL = 10;

/**
 * Deterministic seeded PRNG (mulberry32). Same seed -> same sequence, always.
 * @param {number} seed
 * @returns {() => number} a function producing floats in [0, 1)
 */
function mulberry32(seed) {
  let a = seed >>> 0;
  return function rng() {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function clamp(v, min, max) {
  return Math.max(min, Math.min(max, v));
}

function dist(ax, ay, bx, by) {
  return Math.hypot(ax - bx, ay - by);
}

export class SurvivalGame {
  /**
   * @param {number} seed integer seed, defaults to 1 for reproducible demos
   */
  constructor(seed = 1) {
    this.reset(seed);
  }

  /** Reinitialize the game to its starting state with a (possibly new) seed. */
  reset(seed = 1) {
    this.seed = seed >>> 0;
    this._rng = mulberry32(this.seed);
    this._nextId = 1;

    this.time = 0;
    this.player = { x: ARENA_WIDTH / 2, y: ARENA_HEIGHT / 2 };
    this.hp = PLAYER_MAX_HP;
    this.score = 0;
    this.killCount = 0;
    this.enemies = [];
    this.bullets = [];
    this.over = false;

    this.spawnInterval = SPAWN_INTERVAL_INITIAL_MS;
    this.spawnWave = 1;
    this._spawnTimer = this.spawnInterval;
    this._rampTimer = SPAWN_RAMP_MS;
    this._rampTickCount = 0;
    this._fireTimer = FIRE_INTERVAL_MS;
  }

  _freshId() {
    return this._nextId++;
  }

  _spawnEnemy() {
    // Spawn just outside one of the four arena edges, at a random point along it.
    const side = Math.floor(this._rng() * 4);
    let x, y;
    if (side === 0) {
      x = this._rng() * ARENA_WIDTH;
      y = -ENEMY_RADIUS;
    } else if (side === 1) {
      x = ARENA_WIDTH + ENEMY_RADIUS;
      y = this._rng() * ARENA_HEIGHT;
    } else if (side === 2) {
      x = this._rng() * ARENA_WIDTH;
      y = ARENA_HEIGHT + ENEMY_RADIUS;
    } else {
      x = -ENEMY_RADIUS;
      y = this._rng() * ARENA_HEIGHT;
    }
    this.enemies.push({ id: this._freshId(), x, y });
  }

  _fireAt(target) {
    const dx = target.x - this.player.x;
    const dy = target.y - this.player.y;
    const d = Math.hypot(dx, dy) || 1;
    this.bullets.push({
      id: this._freshId(),
      x: this.player.x,
      y: this.player.y,
      vx: (dx / d) * BULLET_SPEED,
      vy: (dy / d) * BULLET_SPEED,
    });
  }

  _nearestEnemy() {
    if (this.enemies.length === 0) return null;
    let best = this.enemies[0];
    let bestDist = dist(best.x, best.y, this.player.x, this.player.y);
    for (let i = 1; i < this.enemies.length; i++) {
      const e = this.enemies[i];
      const d = dist(e.x, e.y, this.player.x, this.player.y);
      if (d < bestDist) {
        best = e;
        bestDist = d;
      }
    }
    return best;
  }

  /**
   * Advance the simulation by dtMs milliseconds.
   * @param {number} dtMs elapsed time in milliseconds (finite, >= 0)
   * @param {{up?:boolean,down?:boolean,left?:boolean,right?:boolean}} input
   * @returns {object} the new view()
   */
  step(dtMs, input = {}) {
    if (this.over) return this.view();
    if (!Number.isFinite(dtMs) || dtMs < 0) dtMs = 0;
    const dt = dtMs / 1000;
    this.time += dtMs;

    // --- player movement (normalized diagonal, clamped to arena) ---
    let mx = 0;
    let my = 0;
    if (input.up) my -= 1;
    if (input.down) my += 1;
    if (input.left) mx -= 1;
    if (input.right) mx += 1;
    if (mx !== 0 || my !== 0) {
      const len = Math.hypot(mx, my) || 1;
      this.player.x += (mx / len) * PLAYER_SPEED * dt;
      this.player.y += (my / len) * PLAYER_SPEED * dt;
    }
    this.player.x = clamp(this.player.x, PLAYER_RADIUS, ARENA_WIDTH - PLAYER_RADIUS);
    this.player.y = clamp(this.player.y, PLAYER_RADIUS, ARENA_HEIGHT - PLAYER_RADIUS);

    // --- difficulty ramp: spawn cadence tightens and wave size grows over time ---
    this._rampTimer -= dtMs;
    while (this._rampTimer <= 0) {
      this.spawnInterval = Math.max(SPAWN_INTERVAL_MIN_MS, this.spawnInterval * SPAWN_DECAY);
      this._rampTimer += SPAWN_RAMP_MS;
      this._rampTickCount += 1;
      if (this._rampTickCount % SPAWN_WAVE_GROWTH_RAMPS === 0) {
        this.spawnWave = Math.min(SPAWN_WAVE_MAX, this.spawnWave + 1);
      }
    }

    // --- spawn enemies on cadence (capped, for both balance and performance) ---
    this._spawnTimer -= dtMs;
    while (this._spawnTimer <= 0) {
      for (let i = 0; i < this.spawnWave && this.enemies.length < ENEMY_CAP; i++) {
        this._spawnEnemy();
      }
      this._spawnTimer += this.spawnInterval;
    }

    // --- enemies pursue the player ---
    for (const e of this.enemies) {
      const dx = this.player.x - e.x;
      const dy = this.player.y - e.y;
      const d = Math.hypot(dx, dy) || 1;
      e.x += (dx / d) * ENEMY_SPEED * dt;
      e.y += (dy / d) * ENEMY_SPEED * dt;
    }

    // --- auto-fire at the nearest enemy on cadence ---
    if (this.enemies.length > 0) {
      this._fireTimer -= dtMs;
      while (this._fireTimer <= 0 && this.enemies.length > 0) {
        this._fireAt(this._nearestEnemy());
        this._fireTimer += FIRE_INTERVAL_MS;
      }
    } else {
      this._fireTimer = FIRE_INTERVAL_MS;
    }

    // --- bullets travel, then get culled once well off-arena ---
    for (const b of this.bullets) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
    }
    const margin = 50;
    this.bullets = this.bullets.filter(
      (b) => b.x > -margin && b.x < ARENA_WIDTH + margin && b.y > -margin && b.y < ARENA_HEIGHT + margin
    );

    // --- bullet vs enemy collisions: strict kill, no partial credit ---
    const deadEnemyIds = new Set();
    const deadBulletIds = new Set();
    for (const b of this.bullets) {
      if (deadBulletIds.has(b.id)) continue;
      for (const e of this.enemies) {
        if (deadEnemyIds.has(e.id)) continue;
        if (dist(b.x, b.y, e.x, e.y) < BULLET_RADIUS + ENEMY_RADIUS) {
          deadEnemyIds.add(e.id);
          deadBulletIds.add(b.id);
          this.score += SCORE_PER_KILL;
          this.killCount += 1;
          break;
        }
      }
    }
    if (deadEnemyIds.size > 0) {
      this.enemies = this.enemies.filter((e) => !deadEnemyIds.has(e.id));
    }
    if (deadBulletIds.size > 0) {
      this.bullets = this.bullets.filter((b) => !deadBulletIds.has(b.id));
    }

    // --- enemy vs player contact damage ---
    let damage = 0;
    for (const e of this.enemies) {
      if (dist(e.x, e.y, this.player.x, this.player.y) < PLAYER_RADIUS + ENEMY_RADIUS) {
        damage += ENEMY_CONTACT_DPS * dt;
      }
    }
    if (damage > 0) {
      this.hp = clamp(this.hp - damage, 0, PLAYER_MAX_HP);
    }

    if (this.hp <= 0) {
      this.hp = 0;
      this.over = true;
    }

    return this.view();
  }

  /** Plain-object, serializable snapshot of the current state. */
  view() {
    return {
      time: this.time,
      player: { x: this.player.x, y: this.player.y },
      hp: this.hp,
      maxHp: PLAYER_MAX_HP,
      score: this.score,
      killCount: this.killCount,
      enemies: this.enemies.map((e) => ({ id: e.id, x: e.x, y: e.y })),
      bullets: this.bullets.map((b) => ({ id: b.id, x: b.x, y: b.y })),
      over: this.over,
      arenaWidth: ARENA_WIDTH,
      arenaHeight: ARENA_HEIGHT,
    };
  }
}
