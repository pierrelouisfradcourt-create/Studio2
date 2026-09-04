// Orchestration — assemble moteur + entrées + rendu, expose l'état inspectable
// (window.__game / window.__game_debug, contrat de jouabilité) et pilote la boucle.
// L'environnement (window, document) est INJECTÉ : la partie est donc jouable en
// navigateur ET pilotable dans un test Node avec un DOM factice.

import { Engine, STATE_PLAYING } from './engine.mjs';
import { InputHandler } from './input.mjs';
import { Renderer, overlayTextFor, objectiveTextFor } from './render.mjs';

export const DEFAULT_SEED = 1;
const HIDDEN_CLASS = 'hidden';

/** Seed lue dans l'URL (?seed=888), sinon la seed par défaut. */
export function seedFromLocation(win) {
  const raw = new URLSearchParams(win?.location?.search ?? '').get('seed');
  const parsed = Number.parseInt(raw ?? '', 10);
  return Number.isNaN(parsed) ? DEFAULT_SEED : parsed;
}

/**
 * Construit une partie sur un environnement donné.
 * @param {{window: object, document: object, seed?: number}} env
 */
export function createGame(env) {
  const win = env.window;
  const doc = env.document;
  const seed = env.seed ?? DEFAULT_SEED;

  const canvas = doc.getElementById('gameCanvas');
  const overlay = doc.getElementById('overlay');
  const overlayText = doc.getElementById('overlayText');
  const objectiveNode = doc.getElementById('objectif');
  const restartButton = doc.getElementById('restart');

  const engine = new Engine({ seed });
  const input = new InputHandler(win);
  const renderer = new Renderer(canvas);

  let rafId = null;

  /** R1 — l'objectif du joueur est aussi écrit hors canvas, lisible par un bot. */
  function paintObjective() {
    if (objectiveNode) {
      objectiveNode.textContent = objectiveTextFor(engine);
    }
  }

  /** R10 — état inspectable, indépendant du rendu. */
  function updateGameWindow() {
    win.__game = {
      seed,
      paddle: { x: engine.paddle.x },
      ball: {
        x: engine.ball.x,
        y: engine.ball.y,
        vx: engine.ball.vx,
        vy: engine.ball.vy,
      },
      bricksRemaining: engine.bricksRemaining,
      state: engine.state,
      over: engine.over,
      ticks: engine.ticks,
      hash: engine.hashState(),
    };
    win.__game_debug = {
      hit: forceLose,
      forceLose,
      forceWin,
      step,
      reset,
      snapshot: () => engine.snapshot(),
    };
  }

  function paintOverlay() {
    if (engine.state === STATE_PLAYING) {
      overlay.classList.add(HIDDEN_CLASS);
      return;
    }
    overlayText.textContent = overlayTextFor(engine);
    renderer.renderOverlay(engine);
    overlay.classList.remove(HIDDEN_CLASS);
  }

  /** Un pas de simulation : intention clavier -> moteur -> rendu -> état publié. */
  function step() {
    engine.tick(input.getIntent());
    renderer.render(engine);
    paintOverlay();
    paintObjective();
    updateGameWindow();
  }

  function loop() {
    step();
    rafId = win.requestAnimationFrame(loop);
  }

  function start() {
    rafId = win.requestAnimationFrame(loop);
    return rafId;
  }

  function stop() {
    win.cancelAnimationFrame(rafId);
    rafId = null;
  }

  /** Rejouer : remet la partie à son état initial (bouton #restart). */
  function reset() {
    engine.init();
    input.reset();
    renderer.render(engine);
    paintOverlay();
    paintObjective();
    updateGameWindow();
  }

  /** Hook de test déterministe : force la défaite sans dépendre du timing réel. */
  function forceLose() {
    engine.ball.y = engine.paddle.y * 2;
    engine.checkLose();
    paintOverlay();
    paintObjective();
    updateGameWindow();
  }

  /** Hook de test déterministe : force la victoire (mur vidé). */
  function forceWin() {
    for (const brick of engine.bricks) {
      if (brick.destroyed === false) {
        engine.destroyBrick(brick);
      }
    }
    engine.checkWin();
    paintOverlay();
    paintObjective();
    updateGameWindow();
  }

  if (restartButton) {
    restartButton.addEventListener('click', reset);
  }

  renderer.render(engine);
  paintOverlay();
  paintObjective();
  updateGameWindow();

  return { engine, input, renderer, step, start, stop, reset, forceWin, forceLose, updateGameWindow };
}

/** Démarre une partie et lance la boucle d'animation. */
export function bootstrap(win, doc) {
  const game = createGame({ window: win, document: doc, seed: seedFromLocation(win) });
  game.start();
  return game;
}

/** Bootstrap différé si le document est encore en cours d'analyse. */
export function autoBootstrap(win, doc) {
  if (doc.readyState === 'loading') {
    win.addEventListener('DOMContentLoaded', () => bootstrap(win, doc));
    return null;
  }
  return bootstrap(win, doc);
}

if (typeof window !== 'undefined') {
  autoBootstrap(window, document);
}
