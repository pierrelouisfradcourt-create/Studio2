// HUD — affichage DOM (objectif, score, vies)
export class HUD {
  constructor() {
    this.objectiveEl = null;
    this.scoreEl = null;
    this.livesEl = null;
    this.overlayEl = null;
    this.restartEl = null;
  }

  setupDOM() {
    this.objectiveEl = document.getElementById('objective');
    this.scoreEl = document.getElementById('score');
    this.livesEl = document.getElementById('lives');
    this.overlayEl = document.getElementById('overlay');
    this.restartEl = document.getElementById('restart');
  }

  update(gameState, progressionState) {
    if (this.objectiveEl) {
      this.objectiveEl.textContent = progressionState.currentObjective();
    }
    if (this.scoreEl) {
      this.scoreEl.textContent = `Score: ${gameState.score}`;
    }
    if (this.livesEl) {
      this.livesEl.textContent = `Vies: ${gameState.lives}`;
    }

    if (progressionState.isGameOver()) {
      if (this.overlayEl) {
        this.overlayEl.classList.remove('hidden');
      }
    } else {
      if (this.overlayEl) {
        this.overlayEl.classList.add('hidden');
      }
    }
  }
}

export function makeHUD() {
  return new HUD();
}
