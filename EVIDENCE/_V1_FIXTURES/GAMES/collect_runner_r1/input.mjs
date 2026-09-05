// input.mjs — UI-only keyboard input handling. No game rules here: this
// module only tracks which keys are currently held and exposes the same
// {left, right, jump} shape the pure engine's step() expects.

const KEYS_LEFT = new Set(['ArrowLeft', 'a', 'A']);
const KEYS_RIGHT = new Set(['ArrowRight', 'd', 'D']);
const KEYS_JUMP = new Set(['Space', ' ', 'ArrowUp', 'w', 'W']);

export function createInputState(target = window) {
  const held = new Set();

  function keyName(e) {
    // Space bar reports code 'Space' but key ' ' — normalize to code when present.
    return e.code === 'Space' ? 'Space' : e.key;
  }

  function onKeyDown(e) {
    held.add(keyName(e));
    if (KEYS_JUMP.has(keyName(e))) e.preventDefault();
  }

  function onKeyUp(e) {
    held.delete(keyName(e));
  }

  // Reconnection/robustness: if the tab loses focus mid-press, held keys
  // must be released so input never gets "stuck" pressed forever.
  function onBlur() {
    held.clear();
  }

  target.addEventListener('keydown', onKeyDown);
  target.addEventListener('keyup', onKeyUp);
  target.addEventListener('blur', onBlur);

  return {
    read() {
      let left = false;
      let right = false;
      let jump = false;
      for (const k of held) {
        if (KEYS_LEFT.has(k)) left = true;
        if (KEYS_RIGHT.has(k)) right = true;
        if (KEYS_JUMP.has(k)) jump = true;
      }
      return { left, right, jump };
    },
    destroy() {
      target.removeEventListener('keydown', onKeyDown);
      target.removeEventListener('keyup', onKeyUp);
      target.removeEventListener('blur', onBlur);
      held.clear();
    },
  };
}
