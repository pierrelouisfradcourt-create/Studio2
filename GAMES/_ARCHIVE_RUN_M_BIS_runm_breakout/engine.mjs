// Engine — simulation déterministe d'une frame (raquette, balle, briques, score, vies)
export class GameState {
  constructor() {
    this.width = 800;
    this.height = 600;

    this.paddle = {
      x: this.width / 2 - 40,
      y: this.height - 20,
      width: 80,
      height: 10,
    };

    this.ball = {
      x: this.width / 2,
      y: this.height - 40,
      vx: 300,
      vy: -300,
      radius: 5,
    };

    this.score = 0;
    this.lives = 3;

    this.screen1 = this.createBrickScreen();
    this.screen2 = this.createBrickScreen();
    this.currentScreen = 1;

    this.gameOver = false;
    this.gameWon = false;
  }

  createBrickScreen() {
    const rows = 3;
    const cols = 8;
    const bricks = [];
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        bricks.push({
          x: 50 + c * 90,
          y: 50 + r * 40,
          width: 80,
          height: 30,
          alive: true,
        });
      }
    }
    return bricks;
  }

  step(dt, intents) {
    if (this.gameOver || this.gameWon) return;

    dt = dt / 1000;

    // Mouvement raquette
    if (intents.paddleLeft) {
      this.paddle.x = Math.max(0, this.paddle.x - 400 * dt);
    }
    if (intents.paddleRight) {
      this.paddle.x = Math.min(this.width - this.paddle.width, this.paddle.x + 400 * dt);
    }

    // Mouvement balle
    this.ball.x += this.ball.vx * dt;
    this.ball.y += this.ball.vy * dt;

    // Rebond sur murs latéraux
    if (this.ball.x - this.ball.radius < 0 || this.ball.x + this.ball.radius > this.width) {
      this.ball.vx *= -1;
      this.ball.x = Math.max(this.ball.radius, Math.min(this.width - this.ball.radius, this.ball.x));
    }

    // Rebond sur le haut
    if (this.ball.y - this.ball.radius < 0) {
      this.ball.vy *= -1;
      this.ball.y = this.ball.radius;
    }

    // Chute de la balle (perte de vie)
    if (this.ball.y - this.ball.radius > this.height) {
      this.lives--;
      if (this.lives <= 0) {
        this.gameOver = true;
      } else {
        this.resetBall();
      }
      return;
    }

    // Rebond sur raquette
    if (this.collideCircleRect(this.ball, this.paddle)) {
      this.ball.vy *= -1;
      this.ball.y = this.paddle.y - this.ball.radius;
      this.reflectBallAngle();
    }

    // Collision avec briques
    const screen = this.currentScreen === 1 ? this.screen1 : this.screen2;
    for (const brick of screen) {
      if (!brick.alive) continue;
      if (this.collideCircleRect(this.ball, brick)) {
        brick.alive = false;
        this.ball.vy *= -1;
        this.score += 10;
        break;
      }
    }

    // Vérifier victoire
    const activeBricks = screen.filter(b => b.alive).length;
    if (activeBricks === 0) {
      if (this.currentScreen === 1) {
        this.currentScreen = 2;
        this.resetBall();
      } else {
        this.gameWon = true;
      }
    }
  }

  collideCircleRect(circle, rect) {
    const closestX = Math.max(rect.x, Math.min(circle.x, rect.x + rect.width));
    const closestY = Math.max(rect.y, Math.min(circle.y, rect.y + rect.height));
    const dx = circle.x - closestX;
    const dy = circle.y - closestY;
    return dx * dx + dy * dy < circle.radius * circle.radius;
  }

  reflectBallAngle() {
    const paddleCenter = this.paddle.x + this.paddle.width / 2;
    const hitPos = (this.ball.x - this.paddle.x) / this.paddle.width;
    const angle = (hitPos - 0.5) * Math.PI * 0.5;
    const speed = Math.sqrt(this.ball.vx ** 2 + this.ball.vy ** 2);
    this.ball.vx = Math.sin(angle) * speed;
    this.ball.vy = -Math.cos(angle) * speed;
  }

  resetBall() {
    this.ball.x = this.width / 2;
    this.ball.y = this.height - 40;
    this.ball.vx = 300;
    this.ball.vy = -300;
  }

  hash() {
    const parts = [
      this.score,
      this.lives,
      Math.round(this.ball.x * 1000),
      Math.round(this.ball.y * 1000),
      Math.round(this.ball.vx * 1000),
      Math.round(this.ball.vy * 1000),
      Math.round(this.paddle.x * 1000),
      this.currentScreen,
    ];
    return parts.join(':');
  }

  view() {
    return {
      paddle: { ...this.paddle },
      ball: { ...this.ball },
      score: this.score,
      lives: this.lives,
      screen1: this.screen1.map(b => ({ ...b })),
      screen2: this.screen2.map(b => ({ ...b })),
      currentScreen: this.currentScreen,
      gameOver: this.gameOver,
      gameWon: this.gameWon,
    };
  }
}

export function makeEngine() {
  return new GameState();
}
