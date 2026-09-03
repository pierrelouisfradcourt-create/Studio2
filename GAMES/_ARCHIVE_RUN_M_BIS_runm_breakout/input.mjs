// Capture clavier → intents neutres (adaptateur pur, sans logique de jeu)
export class InputCapture {
  constructor() {
    this.keys = {};
  }

  attachListeners(window) {
    window.addEventListener('keydown', (e) => {
      this.keys[e.key.toLowerCase()] = true;
    });
    window.addEventListener('keyup', (e) => {
      this.keys[e.key.toLowerCase()] = false;
    });
  }

  getIntents() {
    return {
      paddleLeft: this.keys['arrowleft'] || this.keys['a'],
      paddleRight: this.keys['arrowright'] || this.keys['d'],
    };
  }
}

export function makeInputCapture() {
  return new InputCapture();
}
