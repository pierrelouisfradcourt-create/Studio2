// main.mjs — racine de composition (module `main`, blueprint.json). Bootstrap depuis
// index.html, câble logic+render+input, expose window.__game et pilote le tick
// déterministe (un pas logique fixe par frame d'affichage — jamais de Date.now()).
import { GameState } from './logic.mjs';
import { Renderer } from './render.mjs';
import { InputHandler } from './input.mjs';

export const DEFAULT_SEED = 12345;

/** Graine reproductible depuis l'URL (?seed=NNN), retombe sur DEFAULT_SEED sinon. */
export function seedFromLocation(win) {
  const search = win && win.location ? win.location.search : '';
  const match = /[?&]seed=(\d+)/.exec(search || '');
  if (!match) return DEFAULT_SEED;
  const n = Number.parseInt(match[1], 10);
  return Number.isFinite(n) ? n : DEFAULT_SEED;
}

/**
 * Compose une partie complète. `window`/`document` injectables (tests hors navigateur) ;
 * par défaut les globals du navigateur.
 */
export function createGame({ window: win, document: doc, seed = DEFAULT_SEED } = {}) {
  const gameState = new GameState(seed);
  const renderer = new Renderer(doc, 'game');

  function render() {
    renderer.render(gameState);
  }

  const input = new InputHandler(gameState, doc, (kind) => {
    if (kind === 'caresse') renderer.reagirCaresse();
    render();
  });

  render();
  input.brancherTout();

  let frameId = null;

  /** Un pas logique fixe — R7 : la production passive avance sans clic. */
  function step() {
    gameState.tick();
    render();
    return gameState;
  }

  function start() {
    if (frameId !== null) return frameId;
    const loop = () => {
      step();
      frameId = win.requestAnimationFrame(loop);
    };
    frameId = win.requestAnimationFrame(loop);
    return frameId;
  }

  function stop() {
    if (frameId !== null) win.cancelAnimationFrame(frameId);
    frameId = null;
  }

  win.__game = gameState;
  // Hooks de test déterministes RÉSERVÉS à e2e.mjs (forcer un état sans dépendre du
  // timing réel — cf. forge/contracts/PLAYABLE_CONTRACT.md). solvability.mjs ne les
  // utilise JAMAIS : le brief exige un bot-joueur DOM-only (clics + lecture DOM), jamais
  // un appel direct à l'économie interne (leçon V1 kitten_clicker).
  win.__game_debug = {
    donnerRonrons(n) {
      gameState.ronrons += n;
      render();
      return gameState.ronrons;
    },
  };

  return { gameState, renderer, input, render, step, start, stop };
}

/** Démarre au chargement du document — no-op si window/document absents (tests). */
export function autoBootstrap(win, doc) {
  if (!win || !doc) return null;
  const boot = () => createGame({ window: win, document: doc, seed: seedFromLocation(win) }).start();
  if (doc.readyState === 'loading') {
    win.addEventListener('DOMContentLoaded', boot);
    return null;
  }
  return boot();
}

if (typeof window !== 'undefined') {
  autoBootstrap(window, document);
}
