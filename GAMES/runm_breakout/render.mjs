// Adaptateur de rendu DOM.
// Reçoit un snapshot d'état et met à jour le DOM.
// Lecture seule : ne mute jamais l'état du jeu.

export class Renderer {
  constructor() {
    this.canvas = null;
    this.ctx = null;
    this.setup();
  }

  setup() {
    if (typeof document !== 'undefined') {
      this.canvas = document.getElementById('gameCanvas');
      if (this.canvas) {
        this.ctx = this.canvas.getContext('2d');
      }
    }
  }

  renderObjective() {
    const obj = document.getElementById('objective');
    if (obj && !obj.textContent) {
      obj.textContent = 'Détruire tous les blocs pour gagner';
    }
  }

  render(snapshot) {
    if (!this.ctx || !this.canvas) return;

    const { GAME_WIDTH, GAME_HEIGHT } = this._getDimensions();

    // Fond
    this.ctx.fillStyle = '#222';
    this.ctx.fillRect(0, 0, GAME_WIDTH, GAME_HEIGHT);

    // Raquette
    const p = snapshot.paddle;
    this.ctx.fillStyle = '#fff';
    this.ctx.fillRect(p.x, GAME_HEIGHT - 30, 80, 12);

    // Balle
    const b = snapshot.ball;
    this.ctx.beginPath();
    this.ctx.arc(b.x, b.y, 5, 0, Math.PI * 2);
    this.ctx.fill();

    // Briques
    for (const brick of snapshot.bricks) {
      if (!brick.destroyed) {
        this.ctx.fillStyle = '#f0f';
        this.ctx.fillRect(brick.x, brick.y, brick.width, brick.height);
      }
    }

    // Gestion de l'overlay
    const overlay = document.getElementById('overlay');
    if (overlay) {
      if (snapshot.over) {
        overlay.classList.remove('hidden');
        const overlayText = overlay.querySelector('h2');
        if (overlayText) {
          overlayText.textContent = snapshot.state === 'won' ? 'VICTOIRE!' : 'DÉFAITE';
        }
      } else {
        overlay.classList.add('hidden');
      }
    }
  }

  _getDimensions() {
    return { GAME_WIDTH: 800, GAME_HEIGHT: 600 };
  }
}
