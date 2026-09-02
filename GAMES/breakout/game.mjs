// Breakout (Casse-briques) — moteur de jeu headless PUR. Aucun accès DOM, canvas, ou window.
// Toute la simulation vit ici : physique, collisions, briques, rebonds, vies, niveaux.
// render.mjs (dessin) et input.mjs (clavier) n'ont AUCUNE règle de jeu — ils lisent/pilotent
// uniquement l'état exposé par BreakoutGame.
//
// Déterminisme : le RNG de generateLevel est un xorshift32 seedé. Même seed + même séquence
// de step() => même déroulé. Les positions de brique et les angles de rebond sont déterministes.

import { generateLevel } from './level.mjs';

export const GAME_WIDTH = 800;
export const GAME_HEIGHT = 600;

const PADDLE_WIDTH = 80;
const PADDLE_HEIGHT = 12;
const PADDLE_SPEED = 300; // px/s
const PADDLE_Y = GAME_HEIGHT - 30; // y position de la raquette

const BALL_RADIUS = 5;
const BALL_SPEED = 250; // px/s initial

const BRICK_WIDTH = 60;
const BRICK_HEIGHT = 16;
const BRICK_GAP = 4; // gap entre les briques

const WALL_THICKNESS = 8;
const LEVEL_COUNT = 3;

function clamp(v, lo, hi) {
  return v < lo ? lo : v > hi ? hi : v;
}

// Détecte collision AABB (axis-aligned bounding box) entre deux rectangles
function aabbCollide(x1, y1, w1, h1, x2, y2, w2, h2) {
  return x1 < x2 + w2 && x1 + w1 > x2 && y1 < y2 + h2 && y1 + h1 > y2;
}

// Détecte collision cercle-AABB (pour la balle)
function circleAabbCollide(cx, cy, cr, bx, by, bw, bh) {
  const closestX = clamp(cx, bx, bx + bw);
  const closestY = clamp(cy, by, by + bh);
  const dx = cx - closestX;
  const dy = cy - closestY;
  return dx * dx + dy * dy < cr * cr;
}

// Détermine quelle face d'une AABB est touchée par un point
// Retourne : 'left', 'right', 'top', 'bottom'
function faceTouched(cx, cy, bx, by, bw, bh) {
  const midX = bx + bw / 2;
  const midY = by + bh / 2;
  const dx = cx - midX;
  const dy = cy - midY;
  const halfW = bw / 2;
  const halfH = bh / 2;

  // Normalise les distances
  const normX = Math.abs(dx) / halfW;
  const normY = Math.abs(dy) / halfH;

  // La face la plus proche
  if (normX > normY) return dx > 0 ? 'right' : 'left';
  return dy > 0 ? 'bottom' : 'top';
}

export class BreakoutGame {
  constructor({ seed = 1, width = GAME_WIDTH, height = GAME_HEIGHT } = {}) {
    this.width = width;
    this.height = height;
    this._init(seed);
  }

  // Initialise l'état interne pour une nouvelle partie
  _init(seed) {
    this.seed = seed;
    this.paddle = { x: this.width / 2 - PADDLE_WIDTH / 2, y: PADDLE_Y, width: PADDLE_WIDTH, height: PADDLE_HEIGHT };
    this.ball = { x: this.paddle.x + this.paddle.width / 2, y: this.paddle.y - 20, vx: 150, vy: -200 };
    this.bricks = [];
    this.levelIndex = 0;
    this.lives = 3;
    this.score = 0;
    this.status = 'ACTIVE'; // 'ACTIVE', 'LOST', 'WON', 'PAUSE'
    this._generateCurrentLevel();
  }

  // Génère le niveau courant
  _generateCurrentLevel() {
    const level = generateLevel(this.seed, this.levelIndex);
    this.bricks = level.bricks;
  }

  // Relance une nouvelle partie
  reset(seed) {
    this._init(seed !== undefined ? seed : Date.now() >>> 0);
    return this;
  }

  // Applique l'input du joueur à la raquette (booléens left/right)
  applyInput(input) {
    if (input.left) {
      this.paddle.x = clamp(this.paddle.x - PADDLE_SPEED * (16 / 1000), 0, this.width - this.paddle.width);
    }
    if (input.right) {
      this.paddle.x = clamp(this.paddle.x + PADDLE_SPEED * (16 / 1000), 0, this.width - this.paddle.width);
    }
  }

  // Avance la simulation d'un pas
  step(dtMs, input = {}) {
    if (this.status === 'ACTIVE') {
      this.applyInput(input);
      this._stepPhysics(dtMs);
      this._updatePhysics();
    }
  }

  _stepPhysics(dtMs) {
    const dt = dtMs / 1000; // Convertir en secondes

    // Avance la balle (R1 — la balle avance en continu)
    this.ball.x += this.ball.vx * dt;
    this.ball.y += this.ball.vy * dt;

    // Rebonds murs latéraux (R2)
    if (this.ball.x - BALL_RADIUS < 0) {
      this.ball.x = BALL_RADIUS;
      this.bounceWall();
    }
    if (this.ball.x + BALL_RADIUS > this.width) {
      this.ball.x = this.width - BALL_RADIUS;
      this.bounceWall();
    }

    // Rebond plafond (R3)
    if (this.ball.y - BALL_RADIUS < 0) {
      this.ball.y = BALL_RADIUS;
      this.bounceCeiling();
    }

    // Rebond raquette (R4 — angle selon point d'impact)
    if (this._ballTouches(this.paddle)) {
      this.bouncePaddle();
    }

    // Rebonds briques (R5)
    for (const brick of this.bricks) {
      if (brick.health > 0 && this._ballTouches(brick)) {
        this.bounceBrick(brick);
        this.breakBrick(brick);
        break; // Une seule brique par frame pour éviter le tunneling
      }
    }

    // Perte de vie (R11 — balle sous la raquette)
    if (this.ball.y > this.height) {
      this.loseLife();
    }
  }

  _updatePhysics() {
    // Vérifie les conditions de fin
    this.checkLose();
    this.checkWin();
  }

  // Rebond mur latéral (R2)
  bounceWall() {
    this.ball.vx = -this.ball.vx;
  }

  // Rebond plafond (R3)
  bounceCeiling() {
    this.ball.vy = -this.ball.vy;
  }

  // Rebond raquette avec angle selon point d'impact (R4)
  bouncePaddle() {
    // Inverse la vélocité verticale (la balle repart vers le haut)
    this.ball.vy = -Math.abs(this.ball.vy);

    // Calcule l'angle selon le point d'impact
    // Si la balle est à gauche du centre, angle négatif (déviation gauche)
    // Si la balle est à droite du centre, angle positif (déviation droite)
    const paddleCenter = this.paddle.x + this.paddle.width / 2;
    const relativeIntersectX = this.ball.x - paddleCenter;
    const normalizedRelativeIntersection = relativeIntersectX / (this.paddle.width / 2);
    // normalizedRelativeIntersection = -1 (bord gauche), 0 (centre), +1 (bord droit)

    // Formule déterministe d'angle : plus on frappe un bord, plus la balle dévie
    const maxAngle = 60 * (Math.PI / 180); // 60 degrés max
    const bounceAngle = normalizedRelativeIntersection * maxAngle;

    // Applique l'angle à la vélocité
    const speed = Math.hypot(this.ball.vx, this.ball.vy);
    this.ball.vx = speed * Math.sin(bounceAngle);
    this.ball.vy = -speed * Math.cos(bounceAngle);
  }

  // Rebond brique selon la face touchée (R5)
  bounceBrick(brick) {
    const face = faceTouched(this.ball.x, this.ball.y, brick.x, brick.y, brick.width, brick.height);
    if (face === 'left' || face === 'right') {
      this.ball.vx = -this.ball.vx;
    } else if (face === 'top' || face === 'bottom') {
      this.ball.vy = -this.ball.vy;
    }
  }

  // Détruit une brique et augmente le score (R8)
  breakBrick(brick) {
    if (brick.health > 0) {
      brick.health--;
      if (brick.health === 0) {
        this.score += brick.value;
      }
    }
  }

  // Perte de vie (R11)
  loseLife() {
    this.lives--;
    // Remet la balle au service
    this.ball.x = this.paddle.x + this.paddle.width / 2;
    this.ball.y = this.paddle.y - 20;
    this.ball.vx = 150;
    this.ball.vy = -200;
  }

  // Vérifie défaite (R12 — défaite ssi vies == 0)
  checkLose() {
    if (this.lives <= 0) {
      this.status = 'LOST';
    }
  }

  // Vérifie victoire de niveau (R13 — victoire ssi briques cassables restantes == 0)
  checkWin() {
    const remainingBricks = this.bricks.filter(b => b.health > 0).length;
    if (remainingBricks === 0 && this.status === 'ACTIVE') {
      this.nextLevel();
    }
  }

  // Progression de niveau (R14, R15)
  nextLevel() {
    if (this.levelIndex < LEVEL_COUNT - 1) {
      // Niveau suivant (R14)
      this.levelIndex++;
      this._generateCurrentLevel();
      // Remet la balle au service
      this.ball.x = this.paddle.x + this.paddle.width / 2;
      this.ball.y = this.paddle.y - 20;
      this.ball.vx = 150;
      this.ball.vy = -200;
    } else {
      // Dernier niveau nettoyé → victoire de partie (R15)
      this.status = 'WON';
    }
  }

  // Détecte collision balle-AABB
  _ballTouches(rect) {
    return circleAabbCollide(
      this.ball.x, this.ball.y, BALL_RADIUS,
      rect.x, rect.y, rect.width, rect.height
    );
  }

  // Retourne l'état lisible (R18 — hooks de jouabilité)
  readDebug() {
    const brickCount = this.bricks.filter(b => b.health > 0).length;
    return {
      lives: this.lives,
      score: this.score,
      levelIndex: this.levelIndex,
      ballX: this.ball.x,
      ballY: this.ball.y,
      paddleX: this.paddle.x,
      status: this.status,
      brickCount,
    };
  }

  // Pour les tests, expose l'état complet
  view() {
    return {
      width: this.width,
      height: this.height,
      paddle: { ...this.paddle },
      ball: { ...this.ball },
      bricks: this.bricks.map(b => ({ ...b })),
      lives: this.lives,
      score: this.score,
      levelIndex: this.levelIndex,
      status: this.status,
    };
  }
}
