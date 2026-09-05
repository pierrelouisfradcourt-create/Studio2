// input.mjs — UI only. Keyboard -> input state {left,right,jump}. No game rules here.

const KEY_MAP = {
  ArrowLeft: 'left',
  KeyA: 'left',
  ArrowRight: 'right',
  KeyD: 'right',
  ArrowUp: 'jump',
  Space: 'jump',
  KeyW: 'jump',
};

/** Attaches keyboard listeners to `target` and returns a live input-state object plus
 * a `dispose()` function to remove the listeners. */
export function createKeyboardInput(target = window) {
  const state = { left: false, right: false, jump: false };

  function onKeyDown(e) {
    const action = KEY_MAP[e.code];
    if (!action) return;
    state[action] = true;
    e.preventDefault();
  }

  function onKeyUp(e) {
    const action = KEY_MAP[e.code];
    if (!action) return;
    state[action] = false;
    e.preventDefault();
  }

  target.addEventListener('keydown', onKeyDown);
  target.addEventListener('keyup', onKeyUp);

  return {
    state,
    dispose() {
      target.removeEventListener('keydown', onKeyDown);
      target.removeEventListener('keyup', onKeyUp);
    },
  };
}
