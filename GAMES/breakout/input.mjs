// Breakout — INPUT uniquement. Traduit clavier -> {left,right} booléens.
// AUCUNE règle de jeu ici : ce module ne connaît ni positions, ni briques, ni collisions.

const KEY_MAP = {
  ArrowLeft: "left",
  ArrowRight: "right",
  KeyA: "left",
  KeyD: "right",
  // fallback event.key pour les environnements qui ne fournissent pas .code
  Left: "left",
  Right: "right",
  a: "left",
  d: "right",
  A: "left",
  D: "right",
};

// Crée un tracker d'input branché sur `target` (par défaut window). Retourne
// { input, destroy() } où `input` est un objet live {left,right}.
export function createInput(target = typeof window !== "undefined" ? window : null) {
  const input = { left: false, right: false };
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
    input.left = input.right = false;
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
