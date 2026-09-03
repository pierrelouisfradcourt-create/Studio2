// Progression — machine d'état inter-écrans et fin de partie
export class ProgressionState {
  constructor() {
    this.state = 'playing';
    this.objective = 'Vider l\'écran 1';
  }

  update(engineState) {
    if (engineState.gameWon) {
      this.state = 'won';
      this.objective = 'Victoire !';
    } else if (engineState.gameOver) {
      this.state = 'lost';
      this.objective = 'Défaite !';
    } else if (engineState.currentScreen === 2) {
      this.objective = 'Vider l\'écran 2';
    }
  }

  currentObjective() {
    return this.objective;
  }

  isGameOver() {
    return this.state === 'won' || this.state === 'lost';
  }

  isWon() {
    return this.state === 'won';
  }
}

export function makeProgression() {
  return new ProgressionState();
}
