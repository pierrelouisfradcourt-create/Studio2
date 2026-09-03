// Render — rendu canvas de l'état de jeu (lecture seule)
export class Renderer {
  constructor(canvasElement) {
    this.canvas = canvasElement;
    this.ctx = this.canvas.getContext('2d');
  }

  draw(gameState, progressionState) {
    this.ctx.fillStyle = '#000';
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    this.drawPaddle(gameState);
    this.drawBall(gameState);
    this.drawBricks(gameState);
    this.drawEndGameOverlay(progressionState);
  }

  drawPaddle(gameState) {
    this.ctx.fillStyle = '#0f0';
    const p = gameState.paddle;
    this.ctx.fillRect(p.x, p.y, p.width, p.height);
  }

  drawBall(gameState) {
    this.ctx.fillStyle = '#fff';
    const b = gameState.ball;
    this.ctx.beginPath();
    this.ctx.arc(b.x, b.y, b.radius, 0, Math.PI * 2);
    this.ctx.fill();
  }

  drawBricks(gameState) {
    const screen = gameState.currentScreen === 1 ? gameState.screen1 : gameState.screen2;
    this.ctx.fillStyle = '#f80';
    for (const brick of screen) {
      if (brick.alive) {
        this.ctx.fillRect(brick.x, brick.y, brick.width, brick.height);
        this.ctx.strokeStyle = '#f00';
        this.ctx.lineWidth = 2;
        this.ctx.strokeRect(brick.x, brick.y, brick.width, brick.height);
      }
    }
  }

  drawEndGameOverlay(progressionState) {
    if (!progressionState.isGameOver()) return;

    this.ctx.fillStyle = 'rgba(0, 0, 0, 0.8)';
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);

    this.ctx.fillStyle = '#fff';
    this.ctx.font = '48px Arial';
    this.ctx.textAlign = 'center';
    this.ctx.textBaseline = 'middle';

    const text = progressionState.isWon() ? 'VICTOIRE !' : 'DÉFAITE !';
    this.ctx.fillText(text, this.canvas.width / 2, this.canvas.height / 2 - 40);

    this.ctx.font = '20px Arial';
    this.ctx.fillText('Appuyez sur R pour rejouer', this.canvas.width / 2, this.canvas.height / 2 + 40);
  }
}

export function makeRenderer(canvasElement) {
  return new Renderer(canvasElement);
}
