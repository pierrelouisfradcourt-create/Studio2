// Survival Arena — INPUT uniquement. Traduit clavier -> {up,down,left,right} booléens.
// AUCUNE règle de jeu ici : ce module ne connaît ni PV, ni score, ni collisions.

const KEY_MAP = {
  ArrowUp: "up",
  ArrowDown: "down",
  ArrowLeft: "left",
  ArrowRight: "right",
  KeyW: "up",
  KeyS: "down",
  KeyA: "left",
  KeyD: "right",
  // fallback event.key pour les environnements qui ne fournissent pas .code
  Up: "up",
  Down: "down",
  Left: "left",
  Right: "right",
  w: "up",
  s: "down",
  a: "left",
  d: "right",
  W: "up",
  S: "down",
  A: "left",
  D: "right",
};

// Crée un tracker d'input branché sur `target` (par défaut window). Renvoie
// { input, destroy() } où `input` est un objet live {up,down,left,right}.
export function createInputTracker(target = typeof window !== "undefined" ? window : null) {
  const input = { up: false, down: false, left: false, right: false };
  if (!target) return { input, destroy() {} };

  function resolveDir(evt) {
    return KEY_MAP[evt.code] ?? KEY_MAP[evt.key];
  }

  function onKeyDown(evt) {
    const dir = resolveDir(evt);
    if (dir) {
      input[dir] = true;
      evt.preventDefault?.();
    }
  }

  function onKeyUp(evt) {
    const dir = resolveDir(evt);
    if (dir) {
      input[dir] = false;
      evt.preventDefault?.();
    }
  }

  // relâche tout (utile si la fenêtre perd le focus en plein mouvement)
  function onBlur() {
    input.up = input.down = input.left = input.right = false;
  }

  target.addEventListener("keydown", onKeyDown);
  target.addEventListener("keyup", onKeyUp);
  target.addEventListener("blur", onBlur);

  function destroy() {
    target.removeEventListener("keydown", onKeyDown);
    target.removeEventListener("keyup", onKeyUp);
    target.removeEventListener("blur", onBlur);
  }

  return { input, destroy };
}
