// Point d'entrée navigateur : boucle à pas fixe (60 Hz) découplée de l'affichage, câblage
// sim <-> entrées <-> rendu <-> audio <-> menus, persistance locale, outils de test.
//
// Paramètres d'URL (playtest) : ?seed=123  ?floor=6  ?god=1  ?autostart=1  ?tune=0

import { createGame, stepGame, applyCommand, DT } from './sim/game.mjs';
import { DEFAULT_TUNING } from './sim/config.mjs';
import { createInput } from './input/input.mjs';
import { createCamera, fitCamera, updateCamera, applyCamera, worldToScreen, resetCamera } from './render/camera.mjs';
import { createFx, handleFxEvents, updateFx, clearFx } from './render/fx.mjs';
import { drawWorld } from './render/render.mjs';
import { drawHud, pauseButtonRect } from './render/hud.mjs';
import { createAudio } from './audio/sfx.mjs';
import { createUI } from './ui/menus.mjs';
import { buildTuningPanel, loadTuningOverrides, applyOverrides } from './ui/tuning.mjs';

const MAX_STEPS_PER_FRAME = 5;
const MAX_DPR = 2;
const FPS_LOW = 48;
const FPS_WINDOW = 2; // s d'observation avant de baisser la qualité
const META_KEY = 'dungeon666.meta.v1';
const SETTINGS_KEY = 'dungeon666.settings.v1';
const SLOWMO = {
  roomClear: { scale: 0.3, dur: 0.45 },
  bossKill: { scale: 0.2, dur: 1.1 },
  playerDeath: { scale: 0.35, dur: 1.2 },
  dodge: { scale: 0.55, dur: 0.1 },
};

const params = new URLSearchParams(location.search);

// ------------------------------------------------------------------ persistance (tolérante)

function load(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? { ...fallback, ...JSON.parse(raw) } : { ...fallback };
  } catch {
    return { ...fallback };
  }
}

function save(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    // navigation privée, stockage bloqué : la partie continue sans persistance
  }
}

// ------------------------------------------------------------------ état de l'application

const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d', { alpha: false });
const uiRoot = document.getElementById('ui');
const safeProbe = document.getElementById('safe');

const app = {
  screen: 'title', // title | game | tuning
  paused: false,
  meta: load(META_KEY, { checkpoints: [1], bestFloor: 1, items: null, snapshots: {} }),
  settings: load(SETTINGS_KEY, { sound: true, haptics: true, shake: 1 }),
  game: null,
  view: { w: 1, h: 1, dpr: 1, safe: { top: 0, right: 0, bottom: 0, left: 0 } },
  quality: 1,
  slowmo: { scale: 1, t: 0, last: -99 },
};

const camera = createCamera();
const fx = createFx();
const audio = createAudio();
audio.setMuted(!app.settings.sound);
audio.setHaptics?.(app.settings.haptics);
camera.shakeScale = app.settings.shake;

let audioSessionSet = false;
const input = createInput(canvas, {
  onGesture: () => {
    // iOS 17+ : sans « playback », le bouton silencieux coupe tout le son du jeu.
    if (!audioSessionSet && navigator.audioSession) {
      try {
        navigator.audioSession.type = 'playback';
      } catch {
        // non pris en charge
      }
      audioSessionSet = true;
    }
    audio.unlock();
  },
});

/** Plein écran + paysage sur Android (refusé sans bruit sur iOS, ordinateur, iframe). */
async function enterImmersive() {
  if (!matchMedia('(pointer: coarse)').matches) return;
  try {
    const el = document.documentElement;
    if (document.fullscreenEnabled && !document.fullscreenElement) await el.requestFullscreen({ navigationUI: 'hide' });
    await screen.orientation?.lock?.('landscape');
  } catch {
    // plein écran ou verrouillage indisponible : le jeu reste jouable tel quel
  }
}

const ui = createUI(uiRoot, {
  isTouch: () => input.usingTouch || matchMedia('(pointer: coarse)').matches,
  start: (floor, sandbox = false) => {
    enterImmersive();
    startRun(floor, sandbox);
  },
  command: (cmd) => {
    if (app.game) {
      applyCommand(app.game, cmd);
      afterCommand();
    }
  },
  resume: () => {
    app.paused = false;
  },
  quit: () => {
    app.paused = false;
    app.screen = 'title';
    app.game = null;
  },
  setSetting: (k, v) => {
    app.settings[k] = v;
    save(SETTINGS_KEY, app.settings);
    audio.setMuted(!app.settings.sound);
    audio.setHaptics?.(app.settings.haptics);
    camera.shakeScale = app.settings.shake;
  },
  openTuning: () => {
    app.screen = 'tuning';
  },
  buildTuning: (p) => buildTuningPanel(p, {
    getTuning: () => app.game?.tuning ?? DEFAULT_TUNING,
    defaults: DEFAULT_TUNING,
    onClose: () => {
      app.screen = app.game ? 'game' : 'title';
    },
  }),
});

// ------------------------------------------------------------------ partie

function startRun(floor, sandbox = false) {
  const seed = params.has('seed') ? Number(params.get('seed')) : (Math.random() * 2 ** 31) >>> 0;
  const startFloor = params.has('floor') ? Number(params.get('floor')) : floor;
  const meta = { checkpoints: app.meta.checkpoints, bestFloor: app.meta.bestFloor, snapshots: app.meta.snapshots ?? {} };
  const tune = params.get('tune') === '0' ? {} : loadTuningOverrides();
  app.game = createGame({ seed, startFloor: sandbox ? 1 : startFloor, meta, godMode: params.get('god') === '1', items: app.meta.items ?? undefined, sandbox });
  applyOverrides(app.game.tuning, tune);
  app.screen = 'game';
  app.paused = false;
  clearFx(fx);
  resetCamera(camera);
  // Les événements d'entrée dans le premier étage déclenchent bannière et sons.
  flushEvents();
  requestWakeLock();
}

function persistMeta() {
  const g = app.game;
  if (!g) return;
  app.meta = { checkpoints: g.meta.checkpoints.slice(), bestFloor: g.meta.bestFloor, items: g.run.items, snapshots: g.meta.snapshots };
  save(META_KEY, app.meta);
}

function afterCommand() {
  flushEvents();
  persistMeta();
}

function flushEvents() {
  const g = app.game;
  if (!g || g.events.length === 0) return;
  if (g.events.some((e) => e.type === 'floorEnter')) {
    resetCamera(camera);
    clearFx(fx);
  }
  handleFxEvents(fx, camera, g.events, g);
  audio.handleEvents(g.events, g);
  for (const ev of g.events) {
    if (ev.type === 'roomClear') setSlowmo(ev.boss ? SLOWMO.bossKill : SLOWMO.roomClear);
    else if (ev.type === 'playerDeath') setSlowmo(SLOWMO.playerDeath);
    else if (ev.type === 'dodge') setSlowmo(SLOWMO.dodge);
    if (ev.type === 'checkpoint' || ev.type === 'equip' || ev.type === 'gameOver' || ev.type === 'floorEnter') persistMeta();
  }
  g.events.length = 0;
}

const SLOWMO_COOLDOWN = 3; // s réelles entre deux ralentis (sauf boss et mort)

function setSlowmo(s) {
  const urgent = s === SLOWMO.bossKill || s === SLOWMO.playerDeath;
  if (!urgent && time - app.slowmo.last < SLOWMO_COOLDOWN) return;
  if (s.scale <= app.slowmo.scale || app.slowmo.t <= 0) {
    app.slowmo.scale = s.scale;
    app.slowmo.t = s.dur;
    app.slowmo.last = time;
  }
}

// ------------------------------------------------------------------ écran

function readSafe() {
  const cs = getComputedStyle(safeProbe);
  return {
    top: parseFloat(cs.paddingTop) || 0,
    right: parseFloat(cs.paddingRight) || 0,
    bottom: parseFloat(cs.paddingBottom) || 0,
    left: parseFloat(cs.paddingLeft) || 0,
  };
}

function resize() {
  const w = Math.max(1, window.innerWidth);
  const h = Math.max(1, window.innerHeight);
  const dpr = Math.min(MAX_DPR, window.devicePixelRatio || 1) * app.quality;
  app.view = { w, h, dpr, safe: readSafe() };
  canvas.width = Math.round(w * dpr);
  canvas.height = Math.round(h * dpr);
  canvas.style.width = `${w}px`;
  canvas.style.height = `${h}px`;
  fitCamera(camera, w, h);
  input.layout(w, h, app.view.safe);
}

window.addEventListener('resize', resize);
window.addEventListener('orientationchange', () => setTimeout(resize, 150));
document.addEventListener('visibilitychange', () => {
  if (document.hidden && app.screen === 'game' && app.game?.mode === 'play') app.paused = true;
});

// Bouton pause du HUD (tactile et souris).
canvas.addEventListener('pointerdown', (ev) => {
  if (app.screen !== 'game' || !app.game) return;
  const r = pauseButtonRect(app.view.w, app.view.safe);
  if (Math.hypot(ev.clientX - r.x, ev.clientY - r.y) < r.r) {
    app.paused = true;
    ev.stopImmediatePropagation();
  }
}, { capture: true });

async function requestWakeLock() {
  try {
    await navigator.wakeLock?.request('screen');
  } catch {
    // refusé ou indisponible : sans importance
  }
}

// ------------------------------------------------------------------ boucle

let last = performance.now();
let lastDt = 1 / 60;
let acc = 0;
let time = 0;
const fpsMeter = { frames: 0, t: 0, low: 0, fps: 60 };
const playerScreen = { x: 0, y: 0 };

function frame(now) {
  requestAnimationFrame(frame);
  const realDt = Math.min(0.1, (now - last) / 1000);
  last = now;
  lastDt = realDt;
  time += realDt;
  measureFps(realDt);
  const g = app.game;
  if (input.consumePause() && app.screen === 'game' && g && g.mode === 'play') app.paused = !app.paused;

  let simSteps = 0;
  if (app.screen === 'game' && g && !app.paused && g.mode === 'play') {
    app.slowmo.t -= realDt;
    const scale = app.slowmo.t > 0 ? app.slowmo.scale : 1;
    acc += realDt * scale;
    let steps = 0;
    while (acc >= DT && steps < MAX_STEPS_PER_FRAME) {
      worldToScreen(camera, app.view.w, app.view.h, g.player.x, g.player.y, playerScreen);
      const pilot = window.__d666.autopilot;
      stepGame(g, pilot ? pilot(g) : input.frame(playerScreen));
      acc -= DT;
      steps++;
      if (g.mode !== 'play') break;
    }
    if (steps === MAX_STEPS_PER_FRAME) acc = 0;
    simSteps = steps;
  } else {
    input.frame(null); // vide les fronts accumulés pendant un menu
    acc = 0;
    if (g && g.mode === 'choice' && window.__d666.autopilotChoice) {
      window.__d666.autopilotChoice(g);
      afterCommand();
    }
  }
  if (g) {
    flushEvents();
    if (g.mode === 'play' || g.mode === 'dead') {
      // En jeu, la caméra avance au rythme des pas de simulation (60 Hz) : sur un écran
      // 120 Hz, héros et décor bougent ensemble, sans tremblotement relatif.
      const camDt = g.mode === 'play' && !app.paused ? simSteps * DT : realDt;
      if (camDt > 0) updateCamera(camera, g, camDt);
      updateFx(fx, realDt, g);
    }
  }
  render();
  ui.sync(app.screen === 'game' ? g : null, app);
}

function measureFps(dt) {
  fpsMeter.frames++;
  fpsMeter.t += dt;
  if (fpsMeter.t < 0.5) return;
  fpsMeter.fps = fpsMeter.frames / fpsMeter.t;
  fpsMeter.frames = 0;
  fpsMeter.t = 0;
  // Qualité adaptative : si le téléphone peine, on réduit la définition et les particules.
  if (app.screen === 'game' && fpsMeter.fps < FPS_LOW) fpsMeter.low += 0.5;
  else fpsMeter.low = 0;
  if (fpsMeter.low >= FPS_WINDOW && app.quality > 0.6) {
    app.quality = Math.max(0.6, app.quality - 0.2);
    fx.quality = Math.max(0.4, fx.quality - 0.3);
    fpsMeter.low = 0;
    resize();
  }
}

function render() {
  const { w, h, dpr } = app.view;
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.fillStyle = '#07040a';
  ctx.fillRect(0, 0, w, h);
  const g = app.game;
  if (!g || app.screen === 'title') {
    drawTitleBackdrop(w, h);
    return;
  }
  ctx.save();
  applyCamera(ctx, camera, w, h);
  drawWorld(ctx, g, fx, time, input.touchUI());
  ctx.restore();
  drawHud(ctx, g, fx, camera, input.touchUI(), app.view, time, lastDt);
}

function drawTitleBackdrop(w, h) {
  const grad = ctx.createRadialGradient(w / 2, h * 1.1, 10, w / 2, h * 1.1, Math.max(w, h));
  grad.addColorStop(0, 'rgba(255, 90, 31, 0.35)');
  grad.addColorStop(0.5, 'rgba(120, 20, 30, 0.15)');
  grad.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = grad;
  ctx.fillRect(0, 0, w, h);
  ctx.fillStyle = 'rgba(255, 140, 60, 0.6)';
  for (let i = 0; i < 40; i++) {
    const x = ((i * 97.3 + time * (12 + (i % 5) * 6)) % (w + 40)) - 20;
    const y = h - ((time * (30 + (i % 7) * 9) + i * 53) % (h + 20));
    ctx.fillRect(x, y, 2, 2);
  }
}

// ------------------------------------------------------------------ outils de test (e2e)

// Observation conforme au PLAYABLE_CONTRACT du studio (forge/contracts/PLAYABLE_CONTRACT.md) :
// position du héros, score (démons abattus), fin de partie, niveau (étage).
Object.defineProperty(window, '__game', {
  configurable: true,
  get() {
    const g = app.game;
    if (!g) return null;
    return {
      player: { x: g.player.x, y: g.player.y, hp: g.player.hp, maxHp: g.player.maxHp, state: g.player.state },
      score: g.telemetry.kills,
      gold: g.run.gold,
      over: g.mode === 'dead' || g.mode === 'victory',
      level: g.run.floor,
      mode: g.mode,
      tick: g.tick,
    };
  },
});

// Raccourcis de TEST uniquement (e2e, playtest) : ils forcent un état, ils ne jouent pas.
window.__d666 = {
  get game() {
    return app.game;
  },
  get app() {
    return app;
  },
  start: (floor = 1) => startRun(floor),
  fps: () => fpsMeter.fps,
  // Pilote automatique (playtest/captures) : (game) => InputFrame ; null = joueur humain.
  autopilot: null,
  autopilotChoice: null,
  killAll() {
    const g = app.game;
    if (!g) return;
    g.room.waveIndex = g.room.waves.length - 1;
    g.spawns.length = 0;
    for (const e of g.enemies) e.dead = true;
  },
  hurt(amount) {
    const g = app.game;
    if (!g) return;
    g.player.iframes = 0;
    g.player.hp = Math.max(0, g.player.hp - amount);
    if (g.player.hp <= 0) {
      g.player.hp = 0;
      g.player.state = 'dead';
      g.player.stateTime = 0;
    }
  },
  teleport(x, y) {
    const g = app.game;
    if (!g) return;
    g.player.x = x;
    g.player.y = y;
  },
};
window.__game_debug = {
  hit: () => window.__d666.hurt(99999), // défaite forcée
  forceWin: () => window.__d666.killAll(), // salle (ou Gardien) vaincue d'office
  start: (floor = 1) => startRun(floor),
};

resize();
if (params.get('autostart') === '1') startRun(Number(params.get('floor') ?? 1), params.get('arena') === '1');
requestAnimationFrame(frame);
