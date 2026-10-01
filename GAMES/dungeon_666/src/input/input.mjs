// Entrées : tactile (joystick flottant + boutons à la Brawl Stars), clavier/souris, manette.
// Produit un InputFrame par pas de simulation (voir src/sim/player.mjs). Les fronts
// (pressed) s'accumulent jusqu'à être consommés par le prochain pas : aucun tap perdu,
// même à 120 Hz d'affichage ou pendant un gel d'impact.
//
// Ce module ne connaît ni la simulation ni le rendu : il expose son état (touchUI) en
// données, que main transmet au HUD.

const STICK_RADIUS = 58; // px CSS — course du joystick de déplacement
const STICK_DEAD = 0.12; // fraction du rayon ignorée
const STICK_FULL = 0.7; // fraction du rayon où la vitesse est maximale (nervosité)
const AIM_DRAG_MIN = 18; // px : en deçà, un relâcher = tap (visée assistée)
const AIM_CANCEL = 12; // px : après une visée manuelle, revenir au centre ANNULE la compétence
const MOVE_ZONE = 0.48; // moitié gauche (fraction de la largeur) réservée au déplacement
const MOUSE_IDLE_MS = 2500; // sans mouvement souris, on repasse en visée assistée
const PAD_DEAD = 0.22;
const PAD_AIM_MIN = 0.35;

// Disposition des boutons autour du bouton d'attaque (angles en degrés, y vers le bas).
// Le dash est le plus gros et le plus proche du pouce : c'est le geste le plus important.
const BUTTONS = [
  { id: 'attack', r: 48, angle: 0, dist: 0, drag: true },
  { id: 'dash', r: 40, angle: 186, dist: 112, drag: false },
  { id: 'skill', r: 33, angle: 228, dist: 112, drag: true },
  { id: 'super', r: 35, angle: 268, dist: 116, drag: false },
  { id: 'gadget', r: 27, angle: 318, dist: 98, drag: false },
];
const ATTACK_MARGIN_X = 118;
const ATTACK_MARGIN_Y = 112;

const KEY_MOVE = {
  KeyW: [0, -1], ArrowUp: [0, -1], KeyS: [0, 1], ArrowDown: [0, 1],
  KeyA: [-1, 0], ArrowLeft: [-1, 0], KeyD: [1, 0], ArrowRight: [1, 0],
};
const KEY_ACTION = {
  Space: 'dash', ShiftLeft: 'dash', ShiftRight: 'dash', KeyK: 'dash',
  KeyJ: 'attack', KeyL: 'skill', KeyE: 'gadget', KeyF: 'super', KeyR: 'super',
};

export function createInput(target, { onGesture } = {}) {
  const st = {
    usingTouch: typeof matchMedia === 'function' && matchMedia('(pointer: coarse)').matches,
    width: 1,
    height: 1,
    safe: { top: 0, right: 0, bottom: 0, left: 0 },
    keys: new Set(),
    mouse: { x: 0, y: 0, down: false, right: false, lastMove: -1e9, inside: false },
    stick: { id: null, baseX: 0, baseY: 0, knobX: 0, knobY: 0, x: 0, y: 0 },
    buttons: BUTTONS.map((b) => ({ ...b, x: 0, y: 0, pointer: null, dx: 0, dy: 0, dragging: false, wasManual: false })),
    edges: { attack: false, dash: false, skill: false, gadget: false, super: false, pause: false },
    skillAim: { x: 0, y: 0 },
    touchAttackAim: { x: 0, y: 0 },
    padPrev: [],
    enabled: true,
  };

  const gesture = () => onGesture?.();

  function layout(width, height, safe) {
    st.width = width;
    st.height = height;
    if (safe) st.safe = safe;
    const ax = width - ATTACK_MARGIN_X - st.safe.right;
    const ay = height - ATTACK_MARGIN_Y - st.safe.bottom;
    for (const b of st.buttons) {
      const a = (b.angle * Math.PI) / 180;
      b.x = ax + Math.cos(a) * b.dist;
      b.y = ay + Math.sin(a) * b.dist;
    }
  }

  function buttonAt(x, y) {
    let best = null;
    let bestD = Infinity;
    for (const b of st.buttons) {
      const d = Math.hypot(x - b.x, y - b.y);
      // Zone de toucher plus large que le dessin (tolérance du pouce).
      if (d < b.r * 1.35 && d < bestD) {
        best = b;
        bestD = d;
      }
    }
    return best;
  }

  function press(action) {
    st.edges[action] = true;
  }

  // ------------------------------------------------------------ tactile (Pointer Events)

  function onPointerDown(ev) {
    if (!st.enabled) return;
    gesture();
    if (ev.pointerType === 'mouse') {
      onMouseDown(ev);
      return;
    }
    st.usingTouch = true;
    ev.preventDefault();
    const x = ev.clientX;
    const y = ev.clientY;
    let b = buttonAt(x, y);
    // Un toucher dans la moitié droite hors de tout bouton = attaque, visée depuis ce point.
    if (!b && x >= st.width * MOVE_ZONE && st.buttons[0].pointer === null) b = st.buttons[0];
    if (b && !b.pointer) {
      b.pointer = ev.pointerId;
      b.ox = b.id === 'attack' && buttonAt(x, y) !== b ? x : b.x;
      b.oy = b.id === 'attack' && buttonAt(x, y) !== b ? y : b.y;
      b.dx = 0;
      b.dy = 0;
      b.dragging = false;
      if (b.id === 'attack') press('attack');
      else if (b.id !== 'skill') press(b.id);
      return;
    }
    if (x < st.width * MOVE_ZONE && st.stick.id === null) {
      const s = st.stick;
      s.id = ev.pointerId;
      // Le joystick naît sous le pouce, mais jamais collé au bord.
      s.baseX = Math.max(STICK_RADIUS + 12 + st.safe.left, Math.min(x, st.width * MOVE_ZONE - STICK_RADIUS));
      s.baseY = Math.max(STICK_RADIUS + 12, Math.min(y, st.height - STICK_RADIUS - 12 - st.safe.bottom));
      updateStick(x, y);
    }
  }

  function updateStick(x, y) {
    const s = st.stick;
    let dx = x - s.baseX;
    let dy = y - s.baseY;
    const d = Math.hypot(dx, dy);
    if (d > STICK_RADIUS) {
      // Joystick « suiveur » : la base glisse derrière le pouce au-delà de la course.
      s.baseX += (dx / d) * (d - STICK_RADIUS);
      s.baseY += (dy / d) * (d - STICK_RADIUS);
      dx = x - s.baseX;
      dy = y - s.baseY;
    }
    s.knobX = s.baseX + dx;
    s.knobY = s.baseY + dy;
    const n = Math.min(1, Math.hypot(dx, dy) / STICK_RADIUS);
    const mag = n < STICK_DEAD ? 0 : Math.min(1, (n - STICK_DEAD) / (STICK_FULL - STICK_DEAD));
    const l = Math.hypot(dx, dy) || 1;
    s.x = (dx / l) * mag;
    s.y = (dy / l) * mag;
  }

  function onPointerMove(ev) {
    if (ev.pointerType === 'mouse') {
      onMouseMove(ev);
      return;
    }
    if (st.stick.id === ev.pointerId) {
      ev.preventDefault();
      updateStick(ev.clientX, ev.clientY);
      return;
    }
    for (const b of st.buttons) {
      if (b.pointer !== ev.pointerId) continue;
      ev.preventDefault();
      b.dx = ev.clientX - (b.ox ?? b.x);
      b.dy = ev.clientY - (b.oy ?? b.y);
      const d = Math.hypot(b.dx, b.dy);
      if (b.drag && d > AIM_DRAG_MIN) {
        b.dragging = true;
        b.wasManual = true;
      } else if (b.wasManual && d < AIM_CANCEL) {
        b.dragging = false; // retour au centre : la compétence est annulée au relâcher
      }
    }
  }

  function onPointerUp(ev) {
    if (ev.pointerType === 'mouse') {
      onMouseUp(ev);
      return;
    }
    if (st.stick.id === ev.pointerId) {
      st.stick.id = null;
      st.stick.x = 0;
      st.stick.y = 0;
      return;
    }
    for (const b of st.buttons) {
      if (b.pointer !== ev.pointerId) continue;
      const cancelled = ev.type === 'pointercancel' || (b.wasManual && !b.dragging);
      if (b.id === 'skill' && !cancelled) {
        // Compétence : part au RELÂCHER, dans la direction glissée (ou assistée sur un tap).
        const l = Math.hypot(b.dx, b.dy);
        st.skillAim.x = b.dragging && l > 0 ? b.dx / l : 0;
        st.skillAim.y = b.dragging && l > 0 ? b.dy / l : 0;
        press('skill');
      }
      b.pointer = null;
      b.dragging = false;
      b.wasManual = false;
      b.dx = 0;
      b.dy = 0;
    }
  }

  // ------------------------------------------------------------ souris et clavier

  function onMouseDown(ev) {
    st.usingTouch = false;
    st.mouse.lastMove = performance.now();
    if (ev.button === 0) {
      st.mouse.down = true;
      press('attack');
    } else if (ev.button === 2) {
      st.mouse.right = true;
      st.skillAim.x = 0;
      st.skillAim.y = 0;
      press('skill');
    }
  }

  function onMouseMove(ev) {
    st.mouse.x = ev.clientX;
    st.mouse.y = ev.clientY;
    st.mouse.lastMove = performance.now();
    st.mouse.inside = true;
  }

  function onMouseUp(ev) {
    if (ev.button === 0) st.mouse.down = false;
    if (ev.button === 2) st.mouse.right = false;
  }

  function onKeyDown(ev) {
    if (!st.enabled) return;
    gesture();
    if (ev.code === 'Escape' || ev.code === 'KeyP') {
      press('pause');
      return;
    }
    if (KEY_MOVE[ev.code] || KEY_ACTION[ev.code]) ev.preventDefault();
    if (ev.repeat) return;
    st.usingTouch = false;
    st.keys.add(ev.code);
    const action = KEY_ACTION[ev.code];
    if (action) press(action);
  }

  function onKeyUp(ev) {
    st.keys.delete(ev.code);
  }

  function onBlur() {
    st.keys.clear();
    st.mouse.down = false;
    st.stick.id = null;
    st.stick.x = 0;
    st.stick.y = 0;
    for (const b of st.buttons) {
      b.pointer = null;
      b.dragging = false;
    }
  }

  target.addEventListener('pointerdown', onPointerDown, { passive: false });
  // Un tap sur un menu compte aussi : les contrôles tactiles doivent être là au premier pas.
  window.addEventListener('pointerdown', (ev) => {
    if (ev.pointerType === 'touch' || ev.pointerType === 'pen') st.usingTouch = true;
    else if (ev.pointerType === 'mouse') st.usingTouch = false;
  }, { capture: true });
  window.addEventListener('pointermove', onPointerMove, { passive: false });
  window.addEventListener('pointerup', onPointerUp);
  window.addEventListener('pointercancel', onPointerUp);
  window.addEventListener('keydown', onKeyDown);
  window.addEventListener('keyup', onKeyUp);
  window.addEventListener('blur', onBlur);
  target.addEventListener('contextmenu', (ev) => ev.preventDefault());
  // iOS : sans ceci, double-tap = zoom, appui long = loupe/menu. Les Pointer Events restent émis.
  const noDefault = (ev) => ev.preventDefault();
  target.addEventListener('touchstart', noDefault, { passive: false });
  target.addEventListener('touchmove', noDefault, { passive: false });
  document.addEventListener('gesturestart', noDefault);
  // Activation utilisateur : sur iOS, seuls pointerup/touchend (tactile) débloquent l'audio.
  window.addEventListener('pointerup', gesture, { capture: true });
  window.addEventListener('touchend', gesture, { capture: true });

  // ------------------------------------------------------------ manette (Gamepad API)

  function readPad(frame) {
    const pads = navigator.getGamepads ? navigator.getGamepads() : [];
    const pad = pads && [...pads].find((p) => p && p.connected);
    if (!pad) return false;
    const ax = pad.axes;
    const lx = Math.abs(ax[0]) > PAD_DEAD ? ax[0] : 0;
    const ly = Math.abs(ax[1]) > PAD_DEAD ? ax[1] : 0;
    if (lx || ly) {
      frame.moveX = lx;
      frame.moveY = ly;
    }
    const rx = ax[2] ?? 0;
    const ry = ax[3] ?? 0;
    if (Math.hypot(rx, ry) > PAD_AIM_MIN) {
      frame.aimX = rx;
      frame.aimY = ry;
    }
    const btn = (i) => !!pad.buttons[i]?.pressed;
    const edge = (i) => btn(i) && !st.padPrev[i];
    // A=0 dash, B=1 compétence, X=2 attaque, Y=3 gadget, LB=4 dash, RB=5 Super, RT=7 attaque.
    if (btn(2) || btn(7)) frame.attack = true;
    if (edge(2) || edge(7)) frame.attackPressed = true;
    if (edge(0) || edge(4)) frame.dashPressed = true;
    if (edge(1)) frame.skillPressed = true;
    if (edge(3)) frame.gadgetPressed = true;
    if (edge(5)) frame.superPressed = true;
    if (edge(9)) st.edges.pause = true;
    st.padPrev = pad.buttons.map((b) => b.pressed);
    return true;
  }

  // ------------------------------------------------------------ InputFrame

  /**
   * Rend l'InputFrame du prochain pas et consomme les fronts. `playerScreen` {x, y} : position
   * écran du héros, pour convertir la souris en direction de visée.
   */
  function frame(playerScreen) {
    const f = {
      moveX: 0, moveY: 0, aimX: 0, aimY: 0,
      attack: false, attackPressed: st.edges.attack, dashPressed: st.edges.dash,
      skillPressed: st.edges.skill, skillAimX: st.skillAim.x, skillAimY: st.skillAim.y,
      gadgetPressed: st.edges.gadget, superPressed: st.edges.super,
    };
    // Clavier.
    let kx = 0;
    let ky = 0;
    for (const code of st.keys) {
      const m = KEY_MOVE[code];
      if (m) {
        kx += m[0];
        ky += m[1];
      }
    }
    if (kx || ky) {
      const l = Math.hypot(kx, ky);
      f.moveX = kx / l;
      f.moveY = ky / l;
    }
    if (st.keys.has('KeyJ')) f.attack = true;
    // Tactile.
    if (st.stick.id !== null) {
      f.moveX = st.stick.x;
      f.moveY = st.stick.y;
    }
    const atk = st.buttons[0];
    if (atk.pointer !== null) {
      f.attack = true;
      if (atk.dragging) {
        const l = Math.hypot(atk.dx, atk.dy) || 1;
        f.aimX = atk.dx / l;
        f.aimY = atk.dy / l;
      }
    }
    // Souris : visée manuelle vers le curseur tant qu'elle est utilisée.
    const mouseFresh = !st.usingTouch && st.mouse.inside && performance.now() - st.mouse.lastMove < MOUSE_IDLE_MS;
    if (st.mouse.down) f.attack = true;
    if ((mouseFresh || st.mouse.down) && playerScreen) {
      const dx = st.mouse.x - playerScreen.x;
      const dy = st.mouse.y - playerScreen.y;
      const l = Math.hypot(dx, dy);
      if (l > 8) {
        f.aimX = dx / l;
        f.aimY = dy / l;
        if (f.skillPressed && !st.usingTouch && f.skillAimX === 0 && f.skillAimY === 0) {
          f.skillAimX = f.aimX;
          f.skillAimY = f.aimY;
        }
      }
    }
    readPad(f);
    for (const k of Object.keys(st.edges)) if (k !== 'pause') st.edges[k] = false;
    st.skillAim.x = 0;
    st.skillAim.y = 0;
    return f;
  }

  function consumePause() {
    const p = st.edges.pause;
    st.edges.pause = false;
    return p;
  }

  /** État des contrôles tactiles pour le HUD (données, pas de dessin ici). */
  function touchUI() {
    return { visible: st.usingTouch, stick: st.stick, buttons: st.buttons };
  }

  function setEnabled(v) {
    st.enabled = v;
    if (!v) onBlur();
  }

  return {
    layout,
    frame,
    touchUI,
    consumePause,
    setEnabled,
    get usingTouch() {
      return st.usingTouch;
    },
    set usingTouch(v) {
      st.usingTouch = v;
    },
  };
}
