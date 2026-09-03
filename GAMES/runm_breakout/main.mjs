// Main — racine de composition et boucle de jeu.
// Seul module autorisé à dépendre d'engine, input, render.

import { Engine } from './engine.mjs';
import { InputAdapter } from './input.mjs';
import { Renderer } from './render.mjs';

let gameEngine = null;
let inputAdapter = null;
let renderer = null;
let animationId = null;

export function initGame(seed = 1) {
  gameEngine = new Engine({ seed });
  inputAdapter = new InputAdapter();
  renderer = new Renderer();

  renderer.renderObjective();
  exposeGame();

  startGameLoop();
}

// Publier l'état demande DEUX choses : un global `window` (on tourne dans un
// navigateur) et un moteur instancié. La condition vivait en double, mot pour mot,
// dans `exposeGame` et `updateGameWindow` ; l'exemplaire d'`updateGameWindow` n'était
// atteignable qu'à travers celui d'`exposeGame`, donc jamais exerçable seul — un
// mutant y survivait sans qu'aucun test puisse le tuer. Une seule définition, un seul
// point à couvrir.
function canPublish() {
  return typeof window !== 'undefined' && gameEngine !== null;
}

export function exposeGame() {
  if (!canPublish()) return;
  updateGameWindow();
  window.__game_debug = {
    loseGame: () => {
      gameEngine.checkLose();
      updateGameWindow();
    },
    winGame: () => {
      gameEngine.bricksRemaining = 0;
      gameEngine.checkWin();
      updateGameWindow();
    },
  };
}

function updateGameWindow() {
  if (!canPublish()) return;
  window.__game = {
    paddle: { x: gameEngine.paddle.x },
    ball: {
      x: gameEngine.ball.x,
      y: gameEngine.ball.y,
      vx: gameEngine.ball.vx,
      vy: gameEngine.ball.vy,
    },
    bricksRemaining: gameEngine.bricksRemaining,
    state: gameEngine.state,
    over: gameEngine.over,
    level: gameEngine.level,
  };
}

export function resetGame(seed = 1) {
  gameEngine = new Engine({ seed });
  exposeGame();
  if (renderer) {
    const overlay = document.getElementById('overlay');
    if (overlay) overlay.classList.add('hidden');
  }
}

function startGameLoop() {
  const tick = () => {
    const intent = inputAdapter.getIntent();
    gameEngine.tick(intent);
    updateGameWindow();

    const snapshot = gameEngine.snapshot();
    renderer.render(snapshot);

    animationId = requestAnimationFrame(tick);
  };

  if (typeof requestAnimationFrame !== 'undefined') {
    animationId = requestAnimationFrame(tick);
  }
}

export function stopGameLoop() {
  if (animationId !== null && typeof cancelAnimationFrame !== 'undefined') {
    cancelAnimationFrame(animationId);
    animationId = null;
  }
}

// Auto-init when DOM is ready
if (typeof window !== 'undefined') {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      initGame(1);
    });
  } else {
    initGame(1);
  }
}
