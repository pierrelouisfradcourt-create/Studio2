// Survival Arena — moteur de jeu headless PUR. Aucun accès DOM, aucun canvas, aucun window.
// Toute la simulation vit ici. render.mjs (dessin) et input.mjs (clavier) n'ont AUCUNE règle
// de jeu — ils lisent/pilotent uniquement l'état exposé par SurvivalGame.
//
// Déterminisme : le RNG est un xorshift32 seedé. Même seed + même séquence de step() =>
// même déroulé, à chaque fois. C'est la base de l'oracle logic.test.mjs.

export const ARENA_WIDTH = 800;
export const ARENA_HEIGHT = 600;

const PLAYER_RADIUS = 14;
const PLAYER_SPEED = 220; // px/s
const PLAYER_MAX_HP = 100;
const CONTACT_DAMAGE = 10;
const CONTACT_COOLDOWN_MS = 500;

const ENEMY_RADIUS = 12;
const ENEMY_SPEED_MIN = 60;
const ENEMY_SPEED_MAX = 100;
const ENEMY_HP = 3;
const ENEMY_KILL_SCORE = 10;

const SPAWN_INTERVAL_START_MS = 2000;
const SPAWN_INTERVAL_FLOOR_MS = 300;
const SPAWN_RAMP_PER_MS = 0.03; // plus timeAlive monte, plus l'intervalle baisse

const FIRE_INTERVAL_MS = 400;
const BULLET_SPEED = 400; // px/s
const BULLET_RADIUS = 4;

const SURVIVAL_SCORE_PER_MS = 1 / 50; // score passif de survie (accumulé en fractionnaire, cf. _scoreAccum)

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

function dist(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

export class SurvivalGame {
  constructor({ seed = 1, width = ARENA_WIDTH, height = ARENA_HEIGHT } = {}) {
    this.width = width;
    this.height = height;
    this._init(seed);
  }

  // (Ré)initialise tout l'état interne pour une nouvelle partie avec la seed donnée.
  _init(seed) {
    this._rngState = (seed >>> 0) || 1;
    this.player = { x: this.width / 2, y: this.height / 2, r: PLAYER_RADIUS };
    this.hp = PLAYER_MAX_HP;
    this.maxHp = PLAYER_MAX_HP;
    this.score = 0;
    this.timeAlive = 0;
    this.over = false;
    this.enemies = [];
    this.bullets = [];
    this._spawnTimer = 0;
    this._fireTimer = 0;
    this._hitCooldowns = new Map(); // enemy id -> ms restants avant prochain dégât possible
    this._nextEnemyId = 1;
    this._nextBulletId = 1;
    this._scoreAccum = 0; // reste fractionnaire du score de survie (voir step())
  }

  // Relance une nouvelle partie (bouton "Rejouer"). Réutilise la même instance.
  reset(seed = Date.now() >>> 0) {
    this._init(seed);
    return this;
  }

  // xorshift32 — RNG déterministe, aucune dépendance à Math.random().
  _rand() {
    let x = this._rngState;
    x ^= x << 13;
    x >>>= 0;
    x ^= x >>> 17;
    x ^= x << 5;
    x >>>= 0;
    this._rngState = x >>> 0;
    return this._rngState / 4294967296;
  }

  _spawnInterval() {
    const raw = SPAWN_INTERVAL_START_MS - this.timeAlive * SPAWN_RAMP_PER_MS;
    return Math.max(SPAWN_INTERVAL_FLOOR_MS, raw);
  }

  _spawnEnemy() {
    const edge = Math.floor(this._rand() * 4);
    let x, y;
    if (edge === 0) { x = this._rand() * this.width; y = 0; }
    else if (edge === 1) { x = this.width; y = this._rand() * this.height; }
    else if (edge === 2) { x = this._rand() * this.width; y = this.height; }
    else { x = 0; y = this._rand() * this.height; }
    const speed = ENEMY_SPEED_MIN + this._rand() * (ENEMY_SPEED_MAX - ENEMY_SPEED_MIN);
    this.enemies.push({ id: this._nextEnemyId++, x, y, r: ENEMY_RADIUS, speed, hp: ENEMY_HP });
  }

  _nearestEnemy() {
    let best = null;
    let bestD = Infinity;
    for (const e of this.enemies) {
      const d = dist(this.player, e);
      if (d < bestD) { bestD = d; best = e; }
    }
    return best;
  }

  // Avance la simulation de dtMs millisecondes. input = {up,down,left,right} booléens.
  step(dtMs, input = {}) {
    if (this.over) return;
    if (!(dtMs > 0)) return;
    const dt = dtMs / 1000;
    this.timeAlive += dtMs;

    // --- déplacement joueur ---
    let dx = 0;
    let dy = 0;
    if (input.up) dy -= 1;
    if (input.down) dy += 1;
    if (input.left) dx -= 1;
    if (input.right) dx += 1;
    if (dx !== 0 || dy !== 0) {
      const len = Math.hypot(dx, dy);
      dx /= len;
      dy /= len;
      this.player.x = clamp(this.player.x + dx * PLAYER_SPEED * dt, this.player.r, this.width - this.player.r);
      this.player.y = clamp(this.player.y + dy * PLAYER_SPEED * dt, this.player.r, this.height - this.player.r);
    }

    // --- spawn ennemis (fréquence croît avec le temps) ---
    this._spawnTimer += dtMs;
    const interval = this._spawnInterval();
    while (this._spawnTimer >= interval) {
      this._spawnTimer -= interval;
      this._spawnEnemy();
    }

    // --- IA ennemis : foncent vers le joueur ---
    for (const e of this.enemies) {
      const ex = this.player.x - e.x;
      const ey = this.player.y - e.y;
      const d = Math.hypot(ex, ey) || 1;
      e.x += (ex / d) * e.speed * dt;
      e.y += (ey / d) * e.speed * dt;
    }

    // --- tir automatique sur l'ennemi le plus proche ---
    this._fireTimer += dtMs;
    if (this._fireTimer >= FIRE_INTERVAL_MS && this.enemies.length > 0) {
      this._fireTimer = 0;
      const target = this._nearestEnemy();
      if (target) {
        const ex = target.x - this.player.x;
        const ey = target.y - this.player.y;
        const d = Math.hypot(ex, ey) || 1;
        this.bullets.push({
          id: this._nextBulletId++,
          x: this.player.x,
          y: this.player.y,
          vx: (ex / d) * BULLET_SPEED,
          vy: (ey / d) * BULLET_SPEED,
          r: BULLET_RADIUS,
        });
      }
    }

    // --- déplacement + collisions balles/ennemis ---
    for (const b of this.bullets) {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
    }
    this.bullets = this.bullets.filter(
      (b) => b.x >= -20 && b.x <= this.width + 20 && b.y >= -20 && b.y <= this.height + 20
    );
    const hitBulletIds = new Set();
    for (const b of this.bullets) {
      for (const e of this.enemies) {
        if (e.hp > 0 && dist(b, e) < b.r + e.r) {
          e.hp -= 1;
          hitBulletIds.add(b.id);
          break;
        }
      }
    }
    if (hitBulletIds.size > 0) {
      this.bullets = this.bullets.filter((b) => !hitBulletIds.has(b.id));
    }
    const killed = this.enemies.filter((e) => e.hp <= 0);
    if (killed.length > 0) {
      this.score += killed.length * ENEMY_KILL_SCORE;
      for (const e of killed) this._hitCooldowns.delete(e.id);
      this.enemies = this.enemies.filter((e) => e.hp > 0);
    }

    // --- dégâts de contact ennemi -> joueur (avec cooldown par ennemi) ---
    for (const e of this.enemies) {
      const cd = this._hitCooldowns.get(e.id) || 0;
      if (cd <= 0 && dist(this.player, e) < this.player.r + e.r) {
        this.hp = Math.max(0, this.hp - CONTACT_DAMAGE);
        this._hitCooldowns.set(e.id, CONTACT_COOLDOWN_MS);
      }
    }
    for (const [id, cd] of this._hitCooldowns) {
      const nv = cd - dtMs;
      if (nv <= 0) this._hitCooldowns.delete(id);
      else this._hitCooldowns.set(id, nv);
    }

    // --- score passif de survie (accumulateur fractionnaire pour rester exact quel que soit dt) ---
    this._scoreAccum += dtMs * SURVIVAL_SCORE_PER_MS;
    const wholePoints = Math.floor(this._scoreAccum);
    if (wholePoints > 0) {
      this.score += wholePoints;
      this._scoreAccum -= wholePoints;
    }

    if (this.hp <= 0) {
      this.hp = 0;
      this.over = true;
    }
  }

  // Hook de debug : inflige des dégâts instantanés (utilisé par l'e2e pour forcer
  // l'écran de défaite sans attendre une vraie collision). Ce n'est PAS de la triche
  // gameplay exposée au joueur — seul index.html le branche derrière window.__game_debug.
  debugHit(amount = 999) {
    if (this.over) return;
    this.hp = Math.max(0, this.hp - amount);
    if (this.hp <= 0) {
      this.hp = 0;
      this.over = true;
    }
  }

  // Vue sérialisable minimaliste (utile pour exposer via window.__game côté navigateur).
  view() {
    return {
      width: this.width,
      height: this.height,
      player: { x: this.player.x, y: this.player.y, r: this.player.r },
      hp: this.hp,
      maxHp: this.maxHp,
      score: this.score,
      timeAlive: this.timeAlive,
      over: this.over,
      enemies: this.enemies.map((e) => ({ id: e.id, x: e.x, y: e.y, r: e.r, hp: e.hp })),
      bullets: this.bullets.map((b) => ({ id: b.id, x: b.x, y: b.y, r: b.r })),
    };
  }
}
