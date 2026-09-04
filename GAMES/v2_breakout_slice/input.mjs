// Entrées clavier — traduit des touches en INTENTION de déplacement.
// Ne dépend NI de engine, NI de render, NI de main (architecture_contract) :
// la cible d'écoute est injectée, ce qui rend le module testable hors navigateur.

export const INTENT_LEFT = 'left';
export const INTENT_RIGHT = 'right';
export const KEY_LEFT = 'ArrowLeft';
export const KEY_RIGHT = 'ArrowRight';

/** Cible d'écoute par défaut : la fenêtre du navigateur, ou rien hors navigateur. */
export function defaultEventTarget() {
  return typeof window !== 'undefined' ? window : null;
}

export class InputHandler {
  constructor(target = defaultEventTarget()) {
    this.keys = new Set();
    this.target = target;
    if (target) {
      target.addEventListener('keydown', (event) => this.keys.add(event.key));
      target.addEventListener('keyup', (event) => this.keys.delete(event.key));
    }
  }

  /** Intention courante : gauche prioritaire, null si aucune touche de direction. */
  getIntent() {
    if (this.keys.has(KEY_LEFT)) return INTENT_LEFT;
    if (this.keys.has(KEY_RIGHT)) return INTENT_RIGHT;
    return null;
  }

  reset() {
    this.keys.clear();
  }
}
