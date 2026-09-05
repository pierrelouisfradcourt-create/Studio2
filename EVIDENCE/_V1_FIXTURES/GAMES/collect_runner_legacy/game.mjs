// Collect Runner — moteur de jeu headless PUR. Aucun accès DOM, aucun canvas, aucun window.
// Toute la simulation vit ici. render.mjs (dessin) et input.mjs (clavier) n'ont AUCUNE règle
// de jeu — ils lisent/pilotent uniquement l'état exposé par CollectRunnerGame.
//
// Déterminisme : le RNG est un xorshift32 seedé. Même seed + même séquence de step() =>
// même déroulé, à chaque fois. C'est la base de l'oracle logic.test.mjs.

export const GAME_WIDTH = 800;
export const GAME_HEIGHT = 600;

const PLAYER_WIDTH = 16;
const PLAYER_HEIGHT = 20;
const AUTO_SPEED = 120; // px/s — avance auto (baissée : timing plus indulgent, jeu solvable)
const PLAYER_SPEED_MOD = 200; // fix: > AUTO_SPEED => gauche fait vraiment RECULER (vx négatif)
const GRAVITY = 600; // px/s²
const JUMP_POWER = -380; // fix: portée ~120px pour couvrir les pièces atteignables
const GROUND_LEVEL = GAME_HEIGHT - 40; // y où le joueur touche le sol

const COIN_RADIUS = 10; // fix: collecte un peu plus généreuse (arc rapide) — reste équitable
const OBSTACLE_WIDTH = 20;
const OBSTACLE_HEIGHT = 20;

const LEVEL_COUNT = 3; // 3 niveaux au total
const COINS_PER_LEVEL = 3; // chaque niveau a 3 pièces

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

function dist(ax, ay, bx, by) {
  return Math.hypot(ax - bx, ay - by);
}

export class CollectRunnerGame {
  constructor({ seed = 1, width = GAME_WIDTH, height = GAME_HEIGHT } = {}) {
    this.width = width;
    this.height = height;
    this._init(seed);
  }

  // (Ré)initialise tout l'état interne pour une nouvelle partie avec la seed donnée.
  _init(seed) {
    this._rngState = (seed >>> 0) || 1;
    this.player = { x: 50, y: GROUND_LEVEL, width: PLAYER_WIDTH, height: PLAYER_HEIGHT };
    this.vx = AUTO_SPEED; // vitesse horizontale (auto-advance)
    this.vy = 0; // vitesse verticale (gravité/saut)
    this.onGround = true;
    this.coins = 0; // total coins collectées dans toute la partie
    this.level = 1;
    this.levelCoins = 0; // coins du niveau actuel
    this.over = false;
    this.won = false;
    this.coinsOnLevel = []; // {x, y, collected} de coins du niveau courant
    this.obstaclesOnLevel = []; // {x, y, width, height} obstacles du niveau
    this._generateCurrentLevel();
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
    x >>>= 0; // mutation:skip (équivalent : masque 32-bit redondant, re-converti en aval)
    x ^= x >>> 17;
    x ^= x << 5;
    x >>>= 0; // mutation:skip (équivalent : masque 32-bit redondant, re-converti en aval)
    this._rngState = x >>> 0;
    return this._rngState / 4294967296;
  }

  // Génère le niveau courant (pièces et obstacles)
  _generateCurrentLevel() {
    this.coinsOnLevel = [];
    this.obstaclesOnLevel = [];
    this.levelCoins = 0;

    // Conception SOLVABLE PAR CONSTRUCTION (fix) : chaque « unité » = un obstacle au
    // sol + une pièce juste AU-DESSUS. Un seul saut, bien timé, franchit l'obstacle
    // ET récupère la pièce à l'apex. Unités espacées de 220px => runway pour retomber
    // et re-sauter. Les niveaux supérieurs ajoutent de la vitesse, pas des pièges.
    const UNIT_SPACING = 220;
    for (let i = 0; i < COINS_PER_LEVEL; i++) {
      const baseX = 220 + i * UNIT_SPACING + this._rand() * 20;
      // obstacle au sol
      this.obstaclesOnLevel.push({
        x: baseX, y: GROUND_LEVEL - OBSTACLE_HEIGHT,
        width: OBSTACLE_WIDTH, height: OBSTACLE_HEIGHT,
      });
      // pièce au-dessus de l'obstacle, dans l'enveloppe de saut (~75-95px au-dessus du sol)
      const coinY = GROUND_LEVEL - 75 - this._rand() * 20;
      this.coinsOnLevel.push({ x: baseX + OBSTACLE_WIDTH / 2, y: coinY, collected: false });
    }
  }

  // Applique l'input du joueur à la vitesse horizontale
  applyInput(input = {}) {
    let speedMod = 0;
    if (input.left) speedMod -= PLAYER_SPEED_MOD;
    if (input.right) speedMod += PLAYER_SPEED_MOD;
    this.vx = AUTO_SPEED + speedMod;
  }

  // Effectue un saut si le joueur est au sol
  jump() {
    if (this.onGround && !this.over) {
      this.vy = JUMP_POWER;
      this.onGround = false;
    }
  }

  // Applique la gravité et met à jour la position y
  applyGravity(dtMs) {
    if (this.over || this.won) return;
    const dt = dtMs / 1000;
    this.vy += GRAVITY * dt;
    this.player.y += this.vy * dt;

    // Collision sol
    if (this.player.y >= GROUND_LEVEL) {
      this.player.y = GROUND_LEVEL;
      this.vy = 0;
      this.onGround = true;
    }
  }

  // Vérifie et consomme une pièce si le joueur la touche
  collectCoin() {
    for (const coin of this.coinsOnLevel) {
      if (!coin.collected) {
        const coinCenterX = coin.x;
        const coinCenterY = coin.y;
        const playerCenterX = this.player.x + this.player.width / 2;
        const playerCenterY = this.player.y + this.player.height / 2;
        const d = dist(playerCenterX, playerCenterY, coinCenterX, coinCenterY);
        if (d < COIN_RADIUS + this.player.width / 2) {
          coin.collected = true;
          this.coins += 1;
          this.levelCoins += 1;
        }
      }
    }
  }

  // Vérifie une collision avec les obstacles
  hitObstacle() {
    for (const obs of this.obstaclesOnLevel) {
      if (this._rectsOverlap(this.player, obs)) {
        this.over = true;
      }
    }
  }

  // Utilitaire : vérifie chevauchement AABB
  _rectsOverlap(rect1, rect2) {
    return !(
      rect1.x + rect1.width < rect2.x ||
      rect2.x + rect2.width < rect1.x ||
      rect1.y + rect1.height < rect2.y ||
      rect2.y + rect2.height < rect1.y
    );
  }

  // Avance au niveau suivant si la pièce finale du niveau a été ramassée
  nextLevel() {
    if (this.over || this.won) return;

    // Vérifie si toutes les pièces du niveau ont été collectées
    const allCoinsCollected = this.coinsOnLevel.every(c => c.collected);
    if (!allCoinsCollected) return;

    // Si c'est le dernier niveau, marquer comme gagné
    if (this.level >= LEVEL_COUNT) {
      this.won = true;
      return;
    }

    // Sinon, passer au niveau suivant
    this.level += 1;
    this.levelCoins = 0;
    this._generateCurrentLevel();
    // Repositionne le joueur au début du niveau
    this.player.x = 50;
    this.player.y = GROUND_LEVEL;
    this.vy = 0;
    this.onGround = true;
  }

  // Avance la simulation de dtMs millisecondes. input = {left,right,jump} booléens.
  step(dtMs, input = {}) {
    if (this.over || this.won) return;
    if (!(dtMs > 0)) return;
    const dt = dtMs / 1000;

    // --- application de l'input à la vitesse (gauche/droite modulent vx) ---
    this.applyInput(input);

    // --- saut (détection du input "jump", puis changement de l'état onGround) ---
    if (input.jump) {
      this.jump();
    }

    // --- déplacement horizontal et vertical ---
    this.player.x += this.vx * dt;
    this.applyGravity(dtMs);

    // --- limites horizontales ---
    this.player.x = clamp(this.player.x, 0, this.width - this.player.width);

    // --- collecte de pièces ---
    this.collectCoin();

    // --- collision obstacles ---
    this.hitObstacle();

    // --- passage de niveau (gated par collecte des pièces) ---
    this.nextLevel();
  }

  // Hook de debug : force la défaite instantanée
  debugHit() {
    if (this.over || this.won) return;
    this.over = true;
  }

  // Vue sérialisable minimaliste (utile pour exposer via window.__game côté navigateur).
  view() {
    return {
      width: this.width,
      height: this.height,
      player: { x: this.player.x, y: this.player.y, width: this.player.width, height: this.player.height },
      coins: this.coins,
      level: this.level,
      levelCoins: this.levelCoins,
      vy: this.vy,
      onGround: this.onGround,
      over: this.over,
      won: this.won,
      coinsOnLevel: this.coinsOnLevel.map(c => ({ x: c.x, y: c.y, collected: c.collected })),
      obstaclesOnLevel: this.obstaclesOnLevel.map(o => ({ x: o.x, y: o.y, width: o.width, height: o.height })),
    };
  }
}
