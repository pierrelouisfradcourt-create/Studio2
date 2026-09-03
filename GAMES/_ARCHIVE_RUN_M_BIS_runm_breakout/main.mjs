// Main — orchestration : boucle RAF, application input->engine, progression, render, hud
import { makeEngine } from './engine.mjs';
import { makeProgression } from './progression.mjs';
import { makeInputCapture } from './input.mjs';
import { makeRenderer } from './render.mjs';
import { makeHUD } from './hud.mjs';
import { makeRng } from './rng.mjs';

let gameEngine = null;
let progression = null;
let inputCapture = null;
let renderer = null;
let hud = null;
let running = false;
let rng = null;

const DT = 16;

export function initializeGame(seed = 1) {
  rng = makeRng(seed);
  gameEngine = makeEngine();
  progression = makeProgression();
  inputCapture = makeInputCapture();

  const canvas = document.getElementById('gameCanvas');
  renderer = makeRenderer(canvas);

  hud = makeHUD();
  hud.setupDOM();

  inputCapture.attachListeners(window);
  attachRestartHandler();

  running = true;
  loop();

  window.__game = {
    get paddle() { return gameEngine.paddle; },
    get ball() { return gameEngine.ball; },
    get score() { return gameEngine.score; },
    get lives() { return gameEngine.lives; },
    get over() { return progression.isGameOver(); },
    get won() { return progression.isWon(); },
    get level() { return gameEngine.currentScreen; },
  };

  window.__game_debug = {
    loseLife: () => { gameEngine.lives = 0; gameEngine.gameOver = true; },
  };
}

function attachRestartHandler() {
  const restartBtn = document.getElementById('restart');
  if (restartBtn) {
    restartBtn.addEventListener('click', () => {
      initializeGame(1);
    });
  }
}

function loop() {
  if (!running) return;

  const intents = inputCapture.getIntents();
  gameEngine.step(DT, intents);
  progression.update(gameEngine.view());

  renderer.draw(gameEngine.view(), progression);
  hud.update(gameEngine.view(), progression);

  if (!progression.isGameOver()) {
    requestAnimationFrame(loop);
  }
}

if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', () => {
    initializeGame(1);
  });
}

export { gameEngine, progression, inputCapture, renderer, hud };
