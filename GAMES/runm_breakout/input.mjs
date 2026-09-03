// Adaptateur d'entrée clavier.
// Capture les intentions (gauche/droite/aucune) et les expose.
// Indépendant du moteur et du rendu.

export class InputAdapter {
  constructor() {
    this.keys = {};
    this.setupListeners();
  }

  setupListeners() {
    if (typeof window !== 'undefined') {
      document.addEventListener('keydown', (e) => {
        const key = e.key;
        if (key === 'ArrowLeft') this.keys['left'] = true;
        if (key === 'ArrowRight') this.keys['right'] = true;
      });

      document.addEventListener('keyup', (e) => {
        const key = e.key;
        if (key === 'ArrowLeft') this.keys['left'] = false;
        if (key === 'ArrowRight') this.keys['right'] = false;
      });
    }
  }

  getIntent() {
    if (this.keys['left']) return 'left';
    if (this.keys['right']) return 'right';
    return null;
  }

  setKeyState(key, pressed) {
    this.keys[key] = pressed;
  }
}
