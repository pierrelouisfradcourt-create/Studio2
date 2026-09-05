// input.mjs -- Keyboard handling ONLY (arrows + WASD). No game logic here.
// Tracks currently-held movement keys and exposes a plain input object
// compatible with SurvivalGame#step(dtMs, input).

const KEY_MAP = {
  ArrowUp: 'up',
  ArrowDown: 'down',
  ArrowLeft: 'left',
  ArrowRight: 'right',
  KeyW: 'up',
  KeyS: 'down',
  KeyA: 'left',
  KeyD: 'right',
  w: 'up',
  s: 'down',
  a: 'left',
  d: 'right',
};

/**
 * Attaches keydown/keyup listeners to `target` and returns:
 *  - `state`: a live { up, down, left, right } object to pass to step()
 *  - `dispose()`: removes the listeners
 * @param {EventTarget} target usually `window`
 * @param {(code: string) => void} [onKeyDown] extra hook, e.g. for "R = restart"
 */
export function createInputTracker(target, onKeyDown) {
  const state = { up: false, down: false, left: false, right: false };

  function resolveDirection(evt) {
    return KEY_MAP[evt.code] ?? KEY_MAP[evt.key];
  }

  function handleKeyDown(evt) {
    const dir = resolveDirection(evt);
    if (dir) {
      state[dir] = true;
      evt.preventDefault();
    }
    if (typeof onKeyDown === 'function') onKeyDown(evt.code || evt.key);
  }

  function handleKeyUp(evt) {
    const dir = resolveDirection(evt);
    if (dir) {
      state[dir] = false;
      evt.preventDefault();
    }
  }

  function handleBlur() {
    state.up = state.down = state.left = state.right = false;
  }

  target.addEventListener('keydown', handleKeyDown);
  target.addEventListener('keyup', handleKeyUp);
  target.addEventListener('blur', handleBlur);

  function dispose() {
    target.removeEventListener('keydown', handleKeyDown);
    target.removeEventListener('keyup', handleKeyUp);
    target.removeEventListener('blur', handleBlur);
  }

  return { state, dispose };
}
