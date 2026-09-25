// Entrées — traduit clics et touches en INTENTIONS neutres, sans connaître ni le moteur ni le
// rendu. Les cibles d'écoute sont injectées : testable hors navigateur.

export const INTENT = Object.freeze({
  CLICK: 'click',
  CANCEL: 'cancel',
  END: 'end',
  ABILITY: 'ability',
  UNEQUIP: 'unequip',
  HAND: 'hand',
});

export const KEYS = Object.freeze({
  CANCEL: ['Escape'],
  END: ['e', 'E', 'Enter'],
  ABILITY: ['a', 'A'],
  UNEQUIP: ['u', 'U'],
});

export function defaultEventTarget() {
  return typeof window !== 'undefined' ? window : null;
}

/** Traduit une touche en intention, ou null. */
export function intentForKey(k) {
  if (KEYS.CANCEL.includes(k)) return { kind: INTENT.CANCEL };
  if (KEYS.END.includes(k)) return { kind: INTENT.END };
  if (KEYS.ABILITY.includes(k)) return { kind: INTENT.ABILITY };
  if (KEYS.UNEQUIP.includes(k)) return { kind: INTENT.UNEQUIP, index: 0 };
  if (/^[1-7]$/.test(k)) return { kind: INTENT.HAND, index: Number(k) - 1 };
  return null;
}

/** Coordonnées canvas d'un clic, en tenant compte de l'échelle CSS éventuelle. */
export function canvasPoint(canvas, event) {
  const rect = canvas.getBoundingClientRect ? canvas.getBoundingClientRect() : { left: 0, top: 0, width: canvas.width, height: canvas.height };
  const sx = rect.width > 0 ? canvas.width / rect.width : 1;
  const sy = rect.height > 0 ? canvas.height / rect.height : 1;
  return { px: (event.clientX - rect.left) * sx, py: (event.clientY - rect.top) * sy };
}

export class InputHandler {
  constructor(target = defaultEventTarget(), canvas = null) {
    this.queue = [];
    this.target = target;
    this.canvas = canvas;
    if (target) {
      target.addEventListener('keydown', (event) => {
        const intent = intentForKey(event.key);
        if (intent) this.queue.push(intent);
      });
    }
    if (canvas) {
      canvas.addEventListener('click', (event) => {
        const { px, py } = canvasPoint(canvas, event);
        this.queue.push({ kind: INTENT.CLICK, px, py });
      });
    }
  }

  push(intent) {
    this.queue.push(intent);
  }

  /** Vide la file et renvoie les intentions accumulées depuis le dernier appel. */
  drain() {
    const out = this.queue;
    this.queue = [];
    return out;
  }

  reset() {
    this.queue = [];
  }
}
