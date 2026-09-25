// Orchestration — assemble moteur + contrôleur + entrées + rendu + bot adverse, expose l'état
// inspectable (window.__game / window.__game_debug, contrat de jouabilité) et pilote la boucle.
// L'environnement (window, document) est INJECTÉ : jouable en navigateur ET pilotable en test.

import { Engine, STATE_PLAYING, PLAYER_ONE, PLAYER_TWO } from './engine.mjs';
import { Controller } from './controller.mjs';
import { InputHandler, INTENT } from './input.mjs';
import { Renderer, overlayTextFor, objectiveTextFor } from './render.mjs';
import { cellAt, handIndexAt } from './layout.mjs';
import { chooseAction } from './ai.mjs';

export const DEFAULT_SEED = 1;
export const AI_STEP_MS = 260;
const HIDDEN_CLASS = 'hidden';
const HUMAN = PLAYER_ONE;
const AI = PLAYER_TWO;

/** Seed lue dans l'URL (?seed=42), sinon la seed par défaut. */
export function seedFromLocation(win) {
  const raw = new URLSearchParams(win?.location?.search ?? '').get('seed');
  const parsed = Number.parseInt(raw ?? '', 10);
  return Number.isNaN(parsed) ? DEFAULT_SEED : parsed;
}

/**
 * Construit une partie sur un environnement donné.
 * @param {{window: object, document: object, seed?: number, aiStepMs?: number}} env
 */
export function createGame(env) {
  const win = env.window;
  const doc = env.document;
  const seed = env.seed ?? DEFAULT_SEED;
  const aiStepMs = env.aiStepMs ?? AI_STEP_MS;

  const canvas = doc.getElementById('gameCanvas');
  const overlay = doc.getElementById('overlay');
  const overlayText = doc.getElementById('overlayText');
  const objectiveNode = doc.getElementById('objectif');
  const logNode = doc.getElementById('log');
  const restartButton = doc.getElementById('restart');
  const endTurnButton = doc.getElementById('endTurn');
  const abilityButton = doc.getElementById('ability');
  const unequipButton = doc.getElementById('unequip');
  const cancelButton = doc.getElementById('cancel');

  const engine = new Engine({ seed });
  const controller = new Controller(engine, { human: HUMAN });
  const input = new InputHandler(win, canvas);
  const renderer = new Renderer(canvas);

  let rafId = null;
  let aiPending = false;
  let aiActions = 0;

  function paintObjective() {
    if (objectiveNode) objectiveNode.textContent = objectiveTextFor(engine);
  }

  function paintLog() {
    if (!logNode) return;
    logNode.textContent = '';
    for (const line of engine.log.slice(-12)) {
      const li = doc.createElement('li');
      li.textContent = line;
      logNode.appendChild(li);
    }
  }

  function paintOverlay() {
    if (!overlay) return;
    if (engine.state === STATE_PLAYING) {
      overlay.classList.add(HIDDEN_CLASS);
      return;
    }
    if (overlayText) overlayText.textContent = overlayTextFor(engine);
    renderer.renderOverlay(engine);
    overlay.classList.remove(HIDDEN_CLASS);
  }

  /** État inspectable, indépendant du rendu (contrat de jouabilité). */
  function updateGameWindow() {
    const p = engine.players[HUMAN];
    win.__game = {
      seed,
      map: engine.mapName,
      round: engine.round,
      ply: engine.ply,
      current: engine.current,
      level: engine.round,
      mana: p.mana,
      manaMax: p.manaMax,
      hand: p.hand.slice(),
      deck: p.deck.length,
      towerHp: engine.towerOf(HUMAN).hp,
      enemyTowerHp: engine.towerOf(AI).hp,
      units: engine.units.size,
      myUnits: engine.unitsOf(HUMAN).length,
      enemyUnits: engine.unitsOf(AI).length,
      selected: controller.sel,
      message: controller.message,
      state: engine.state,
      over: engine.over,
      aiActions,
      hash: engine.hashState(),
    };
    win.__game_debug = {
      hit: forceLose,
      forceLose,
      forceWin,
      step,
      reset,
      apply,
      aiTurn,
      snapshot: () => engine.snapshot(),
      legalActions: () => engine.legalActions(),
    };
  }

  function refresh() {
    renderer.render(engine, controller, HUMAN);
    paintOverlay();
    paintObjective();
    paintLog();
    updateGameWindow();
  }

  /** Le bot joue une action par pas de temps, pour que l'humain voie son tour se dérouler. */
  function scheduleAi() {
    if (aiPending || engine.over || engine.current !== AI) return;
    aiPending = true;
    win.setTimeout(() => {
      aiPending = false;
      if (engine.over || engine.current !== AI) return;
      const action = chooseAction(engine, AI);
      const res = engine.apply(action);
      if (!res.ok) engine.apply({ type: 'end' });
      if (action.type !== 'end') aiActions += 1;
      refresh();
      scheduleAi();
    }, aiStepMs);
  }

  /** Tour complet du bot, synchrone (tests, solvabilité). */
  function aiTurn() {
    let guard = 0;
    while (!engine.over && engine.current === AI && guard < 300) {
      const action = chooseAction(engine, AI);
      const res = engine.apply(action);
      if (!res.ok) engine.apply({ type: 'end' });
      if (action.type !== 'end') aiActions += 1;
      guard += 1;
    }
    refresh();
  }

  /** Applique une action au nom de l'humain (hook de test) puis relance le bot si besoin. */
  function apply(action) {
    const res = engine.apply(action);
    refresh();
    scheduleAi();
    return res;
  }

  function handleIntent(intent) {
    switch (intent.kind) {
      case INTENT.CLICK: {
        const cell = cellAt(intent.px, intent.py);
        if (cell) return controller.clickCell(cell.x, cell.y);
        const hand = handIndexAt(intent.px, intent.py);
        if (hand !== null) return controller.clickHand(hand);
        return false;
      }
      case INTENT.HAND: return controller.clickHand(intent.index);
      case INTENT.CANCEL: return controller.cancel();
      case INTENT.END: return controller.endTurn();
      case INTENT.ABILITY: return controller.useAbility();
      case INTENT.UNEQUIP: return controller.unequip(intent.index ?? 0);
      default: return false;
    }
  }

  /** Un pas : intentions → contrôleur → moteur → rendu → état publié. */
  function step() {
    for (const intent of input.drain()) handleIntent(intent);
    refresh();
    scheduleAi();
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

  function reset() {
    engine.init();
    controller.reset();
    input.reset();
    aiActions = 0;
    refresh();
  }

  function forceLose() {
    engine.towerOf(HUMAN).hp = 0;
    engine.checkWin();
    refresh();
  }

  function forceWin() {
    engine.towerOf(AI).hp = 0;
    engine.checkWin();
    refresh();
  }

  if (restartButton) restartButton.addEventListener('click', reset);
  if (endTurnButton) endTurnButton.addEventListener('click', () => input.push({ kind: INTENT.END }));
  if (abilityButton) abilityButton.addEventListener('click', () => input.push({ kind: INTENT.ABILITY }));
  if (unequipButton) unequipButton.addEventListener('click', () => input.push({ kind: INTENT.UNEQUIP, index: 0 }));
  if (cancelButton) cancelButton.addEventListener('click', () => input.push({ kind: INTENT.CANCEL }));

  refresh();

  return {
    engine, controller, input, renderer, step, start, stop, reset, forceWin, forceLose, apply, aiTurn,
    handleIntent, updateGameWindow,
  };
}

export function bootstrap(win, doc) {
  const game = createGame({ window: win, document: doc, seed: seedFromLocation(win) });
  game.start();
  return game;
}

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
