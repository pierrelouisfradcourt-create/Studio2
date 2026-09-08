import { GameState } from './logic.mjs';
import { Renderer } from './render.mjs';
import { InputHandler } from './input.mjs';

export class Game {
  constructor(seed = 12345) {
    this.gameState = new GameState(seed);
    this.renderer = new Renderer('game');
    this.inputHandler = new InputHandler(this.gameState, this.renderer);
    this.isRunning = false;
    this.frameTime = 16;
    this.lastFrameTime = Date.now();
    this.tickAccumulator = 0;
  }

  initialize() {
    this.renderer.render(this.gameState);
    this.inputHandler.brancherTout();
    window.__game = this;
    return this;
  }

  tick() {
    this.gameState.tick();
    this.renderer.afficherRonrons(this.gameState.ronrons);
    this.renderer.afficherProducteurs(this.gameState.producteurs);
    this.renderer.afficherPrestige(this.gameState.prestige);
    this.renderer.renderObjectif(this.gameState.objectifCourant());

    if (this.gameState.producteurs[0].count > 0) {
      const panierEl = document.getElementById('panier_chatons');
      if (panierEl) {
        panierEl.style.display = 'block';
      }
    }
  }

  start() {
    if (this.isRunning) return;
    this.isRunning = true;
    this.lastFrameTime = Date.now();
    this.tickAccumulator = 0;
    this._loop();
  }

  stop() {
    this.isRunning = false;
  }

  _loop = () => {
    if (!this.isRunning) return;

    const now = Date.now();
    const deltaTime = now - this.lastFrameTime;
    this.lastFrameTime = now;

    this.tickAccumulator += deltaTime;
    while (this.tickAccumulator >= this.frameTime) {
      this.tick();
      this.tickAccumulator -= this.frameTime;
    }

    requestAnimationFrame(() => this._loop());
  };
}

if (typeof window !== 'undefined') {
  window.Game = Game;
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => {
      if (!window.__game) {
        window.__game = new Game().initialize();
        window.__game.start();
      }
    });
  } else {
    if (!window.__game) {
      window.__game = new Game().initialize();
      window.__game.start();
    }
  }
}

export default Game;
