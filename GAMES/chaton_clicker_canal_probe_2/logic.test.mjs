// Tests unitaires — un test par règle, exécutables hors navigateur (node --test).
// Couvre P02-P13 (cf. EVIDENCE/runs/chaton_clicker/wiremap.json). Inclut aussi render.mjs,
// input.mjs et main.mjs (doublures de DOM injectées, aucune dépendance navigateur) : ce
// fichier est celui que le gate mutation (forge/mutation_proof.py, DEFAULT_TEST_ARGV)
// exécute réellement — sans couverture ici, une mutation dans ces 3 modules ne serait
// JAMAIS détectée (le baseline ne les exerce pas).
import { test } from 'node:test';
import assert from 'node:assert';

import { GameState, makeRng, PRODUCER_DEFS } from './logic.mjs';
import { Renderer } from './render.mjs';
import { InputHandler } from './input.mjs';
import { createGame, autoBootstrap, seedFromLocation, DEFAULT_SEED } from './main.mjs';

// --- doublures d'environnement (aucune dépendance navigateur) ---------------------------

function makeElement(tag) {
  const attrs = new Map();
  const classes = new Set();
  const listeners = new Map();
  const el = {
    tagName: tag,
    textContent: '',
    disabled: false,
    hidden: false,
    children: [],
    classList: {
      add: (c) => classes.add(c),
      remove: (c) => classes.delete(c),
      contains: (c) => classes.has(c),
    },
    setAttribute(k, v) { attrs.set(k, String(v)); },
    getAttribute(k) { return attrs.has(k) ? attrs.get(k) : null; },
    appendChild(child) { el.children.push(child); return child; },
    addEventListener(type, fn) {
      const list = listeners.get(type) ?? [];
      list.push(fn);
      listeners.set(type, list);
    },
    dispatch(type, evt) {
      for (const fn of (listeners.get(type) ?? [])) fn(evt);
    },
  };
  return el;
}

function makeDocument() {
  const byId = new Map();
  const doc = {
    readyState: 'complete',
    body: makeElement('body'),
    createElement(tag) {
      const el = makeElement(tag);
      let currentId = '';
      Object.defineProperty(el, 'id', {
        get() { return currentId; },
        set(v) {
          if (currentId) byId.delete(currentId);
          currentId = v;
          if (v) byId.set(v, el);
        },
      });
      return el;
    },
    getElementById(id) { return byId.get(id) || null; },
    querySelector(sel) {
      const m = /^\[data-testid="([^"]+)"\]$/.exec(sel);
      if (m) {
        for (const el of byId.values()) {
          if (el.getAttribute('data-testid') === m[1]) return el;
        }
        return null;
      }
      if (sel.startsWith('#')) return byId.get(sel.slice(1)) || null;
      return null;
    },
  };
  return doc;
}

function makeWindow(doc, search = '') {
  const listeners = new Map();
  const frames = [];
  const win = {
    location: { search },
    cancelled: null,
    frames,
    addEventListener(type, fn) {
      const list = listeners.get(type) ?? [];
      list.push(fn);
      listeners.set(type, list);
    },
    fire(type) { for (const fn of (listeners.get(type) ?? [])) fn(); },
    listenerCount: (type) => (listeners.get(type) ?? []).length,
    requestAnimationFrame(fn) { frames.push(fn); return frames.length; },
    cancelAnimationFrame(id) { win.cancelled = id; },
  };
  return win;
}

// --- R3 (P02 gain) ---------------------------------------------------------------

test('caresser: ronrons augmente après une caresse', () => {
  const state = new GameState(1);
  const before = state.ronrons;
  state.caresser();
  assert.ok(state.ronrons > before);
  assert.strictEqual(state.caressesCount, 1);
});

test('caresser: le gain de base vaut 1 sans prestige (hors critique)', () => {
  const state = new GameState(2); // seed 2 ne tire pas de critique au 1er appel
  const before = state.ronrons;
  const { gain, critique } = state.caresser();
  const attendu = critique ? 2 : 1;
  assert.strictEqual(gain, attendu);
  assert.strictEqual(state.ronrons, before + gain);
});

// --- R5 (P04) ---------------------------------------------------------------------

test('producteurAbordable: faux sous le coût, vrai au coût exact', () => {
  const state = new GameState(3);
  state.ronrons = state.coutProducteur(0) - 1;
  assert.strictEqual(state.producteurAbordable(0), false);
  state.ronrons = state.coutProducteur(0);
  assert.strictEqual(state.producteurAbordable(0), true);
});

// --- R6/R7 (P06) --------------------------------------------------------------------

test('acheterProducteur: refuse l\'achat si trop cher, accepte sinon', () => {
  const state = new GameState(4);
  state.ronrons = 5;
  assert.strictEqual(state.acheterProducteur(0), false);
  state.ronrons = state.coutProducteur(0);
  assert.strictEqual(state.acheterProducteur(0), true);
  assert.strictEqual(state.producteurs[0].count, 1);
  assert.strictEqual(state.ronrons, 0, 'le coût exact doit être DÉDUIT, pas ajouté');
  assert.strictEqual(state.achatsCount, 1);
});

test('acheterProducteur: idx hors bornes (négatif ou == longueur) refusé sans accès invalide', () => {
  const state = new GameState(4);
  state.ronrons = 1_000_000;
  assert.strictEqual(state.acheterProducteur(-1), false);
  assert.strictEqual(state.acheterProducteur(state.producteurs.length), false);
});

test('tick: après achat, la production passive augmente ronrons sans caresse', () => {
  const state = new GameState(5);
  state.ronrons = state.coutProducteur(0);
  state.acheterProducteur(0);
  const before = state.ronrons;
  state.tick();
  assert.ok(state.ronrons > before);
});

// --- R8 (P12) ------------------------------------------------------------------------

test('coutProducteur: le coût croît strictement après chaque achat du même producteur', () => {
  const state = new GameState(6);
  state.ronrons = 10000;
  const cost1 = state.coutProducteur(0);
  state.acheterProducteur(0);
  const cost2 = state.coutProducteur(0);
  assert.ok(cost2 > cost1);
});

// --- R9 (P05) --------------------------------------------------------------------------

test('comparerPolitiques: la politique active dépasse la politique passive sur 300 frames', () => {
  const state = new GameState(7);
  const { passif, actif, diff } = state.comparerPolitiques(300);
  assert.ok(diff > 0);
  assert.ok(actif > passif);
});

test('comparerPolitiques: caresse exactement 1 frame sur 5, ni plus ni moins', () => {
  const state = new GameState(43);
  const frames = 300;
  let attendu = 0;
  for (let i = 0; i < frames; i++) if (i % 5 === 0) attendu++;
  const { caressesActif } = state.comparerPolitiques(frames);
  assert.strictEqual(caressesActif, attendu);
});

// --- R10/R11 (P07/P08) -------------------------------------------------------------------

test('objectifCourant: trois textes distincts au fil de la progression', () => {
  const state = new GameState(8);
  const obj0 = state.objectifCourant();
  state.ronrons = state.coutProducteur(0);
  state.acheterProducteur(0);
  const obj1 = state.objectifCourant();
  assert.notStrictEqual(obj1, obj0);

  state.ronrons = state.coutProducteur(1);
  state.acheterProducteur(1);
  const obj2 = state.objectifCourant();
  assert.notStrictEqual(obj2, obj1);
  assert.notStrictEqual(obj2, obj0);
});

test('objectifCourant: texte exact à chaque palier (pas seulement distinct)', () => {
  const state = new GameState(44);
  assert.strictEqual(
    state.objectifCourant(),
    'Caresse le chaton pour acheter ton premier panier de chatons'
  );
  state.ronrons = state.coutProducteur(0);
  state.acheterProducteur(0);
  assert.strictEqual(
    state.objectifCourant(),
    'Achète un arbre à chats pour accélérer la production'
  );
  state.ronrons = state.coutProducteur(1);
  state.acheterProducteur(1);
  assert.strictEqual(
    state.objectifCourant(),
    'Renouvelle ta portée pour un bonus permanent'
  );
});

// --- R12 (P09) -----------------------------------------------------------------------------

test('rejouerBoucle: rejoue caresse/achat/tick dans l\'état post-achat et progresse', () => {
  const state = new GameState(9);
  state.ronrons = state.coutProducteur(0);
  state.acheterProducteur(0);
  const { ronronsApres, producteursAchetes } = state.rejouerBoucle(50);
  assert.ok(ronronsApres > 0);
  assert.ok(producteursAchetes >= 1);
});

// --- R14 (P10 effet) -------------------------------------------------------------------------

test('renouveauPortee: remet ronrons et producteurs à zéro', () => {
  const state = new GameState(10);
  state.ronrons = 500;
  state.producteurs[0].count = 3;
  state.renouveauPortee();
  assert.strictEqual(state.ronrons, 0);
  assert.strictEqual(state.producteurs[0].count, 0);
  assert.strictEqual(state.producteurs[0].cost, PRODUCER_DEFS[0].baseCost);
  assert.strictEqual(state.prestigeCount, 1);
});

test('renouveauPortee: aucun effet sans ronrons (rien à convertir)', () => {
  const state = new GameState(11);
  const gained = state.renouveauPortee();
  assert.strictEqual(gained, 0);
  assert.strictEqual(state.prestige, 0);
});

// --- R15 (P11) -----------------------------------------------------------------------------

test('gainParCaresse: strictement supérieur après un renouveau', () => {
  const state = new GameState(12);
  const gainAvant = state.gainParCaresse;
  state.ronrons = 500;
  state.renouveauPortee();
  const gainApres = state.gainParCaresse;
  assert.ok(gainApres > gainAvant);
});

// --- R16 (P13) -----------------------------------------------------------------------------

test('hashEtat: même seed + même suite d\'actions => même hash', () => {
  const a = new GameState(42);
  const b = new GameState(42);
  const jouer = (s) => {
    for (let i = 0; i < 10; i++) s.caresser();
    s.ronrons = s.coutProducteur(0);
    s.acheterProducteur(0);
    for (let i = 0; i < 5; i++) s.tick();
  };
  jouer(a);
  jouer(b);
  assert.strictEqual(a.hashEtat(), b.hashEtat());
});

test('hashEtat: change quand l\'état change', () => {
  const state = new GameState(13);
  const before = state.hashEtat();
  state.caresser();
  assert.notStrictEqual(state.hashEtat(), before);
});

// --- RNG (socle technique) -------------------------------------------------------------------

test('makeRng: ne dépend que de sa graine', () => {
  const draw = (seed) => Array.from({ length: 5 }, makeRng(seed));
  assert.deepStrictEqual(draw(42), draw(42));
  assert.notDeepStrictEqual(draw(42), draw(43));
  for (const value of draw(7)) {
    assert.ok(value >= 0 && value < 1);
  }
});

test('clone: les flux RNG de deux clones sont indépendants (pas de partage d\'état)', () => {
  const state = new GameState(14);
  const a = state.clone();
  const b = state.clone();
  const drawsA = Array.from({ length: 5 }, () => a._rng());
  const drawsB = Array.from({ length: 5 }, () => b._rng());
  assert.notDeepStrictEqual(drawsA, drawsB);
});

test('clone: incrémente le sel de clonage à chaque appel (jamais décrémenté)', () => {
  const state = new GameState(50);
  assert.strictEqual(state._cloneSalt, 0);
  state.clone();
  assert.strictEqual(state._cloneSalt, 1);
  state.clone();
  assert.strictEqual(state._cloneSalt, 2);
});

// === render.mjs (module `render`) =============================================================

test('Renderer.renderObjectif: écrit un texte non vide dans #objectif', () => {
  const doc = makeDocument();
  const renderer = new Renderer(doc, 'game');
  renderer.renderObjectif('Va caresser le chaton');
  assert.strictEqual(doc.getElementById('objectif').textContent, 'Va caresser le chaton');
});

test('Renderer.dessinerChaton: crée un chaton cliquable identifiable', () => {
  const doc = makeDocument();
  const renderer = new Renderer(doc, 'game');
  const chaton = renderer.dessinerChaton();
  assert.strictEqual(chaton.getAttribute('data-testid'), 'caresser_chaton');
  assert.ok(chaton.textContent.length > 0);
  // idempotent : un second appel ne crée pas un doublon
  const chaton2 = renderer.dessinerChaton();
  assert.strictEqual(chaton, chaton2);
});

test('Renderer.reagirCaresse: ajoute la classe de réaction visuelle sur le chaton', () => {
  const doc = makeDocument();
  const renderer = new Renderer(doc, 'game');
  renderer.dessinerChaton();
  renderer.reagirCaresse();
  assert.ok(doc.getElementById('chaton').classList.contains('caresse-feedback'));
});

test('Renderer.afficherRonrons: expose le nombre en attribut ET en texte', () => {
  const doc = makeDocument();
  const renderer = new Renderer(doc, 'game');
  renderer.afficherRonrons(12.34);
  const el = doc.getElementById('compteur-ronrons');
  assert.strictEqual(el.getAttribute('data-ronrons'), '12.3');
  assert.ok(el.textContent.includes('12.3'));
});

test('Renderer.afficherProducteurs: bouton désactivé sous le coût, activé au coût atteint', () => {
  const doc = makeDocument();
  const renderer = new Renderer(doc, 'game');
  const producteurs = [{ id: 0, count: 0, cost: 10 }];
  renderer.afficherProducteurs(5, producteurs);
  const btn = doc.querySelector('[data-testid="acheter_producteur_0"]');
  assert.strictEqual(btn.disabled, true);
  renderer.afficherProducteurs(10, producteurs);
  assert.strictEqual(btn.disabled, false);
});

test('Renderer.afficherProducteurs: panier_chatons apparaît seulement après un premier achat', () => {
  const doc = makeDocument();
  const renderer = new Renderer(doc, 'game');
  const producteurs = [{ id: 0, count: 0, cost: 10 }];
  renderer.afficherProducteurs(10, producteurs);
  const panierAvant = doc.getElementById('panier_chatons');
  assert.ok(!panierAvant || panierAvant.hidden === true);

  producteurs[0].count = 1;
  renderer.afficherProducteurs(10, producteurs);
  const panierApres = doc.getElementById('panier_chatons');
  assert.ok(panierApres && panierApres.hidden === false);
});

test('Renderer.afficherProducteurs: panier_chatons se recache si tous les producteurs retombent à 0', () => {
  const doc = makeDocument();
  const renderer = new Renderer(doc, 'game');
  const producteurs = [{ id: 0, count: 1, cost: 10 }];
  renderer.afficherProducteurs(10, producteurs);
  assert.strictEqual(doc.getElementById('panier_chatons').hidden, false);

  producteurs[0].count = 0;
  renderer.afficherProducteurs(10, producteurs);
  assert.strictEqual(doc.getElementById('panier_chatons').hidden, true);
});

test('Renderer.afficherBoutonRenouveau: désactivé à 0 ronron, actif sinon', () => {
  const doc = makeDocument();
  const renderer = new Renderer(doc, 'game');
  renderer.afficherBoutonRenouveau(0);
  assert.strictEqual(doc.getElementById('renouveau_portee').disabled, true);
  renderer.afficherBoutonRenouveau(5);
  assert.strictEqual(doc.getElementById('renouveau_portee').disabled, false);
});

test('Renderer.render: compose un rendu complet cohérent avec l\'état', () => {
  const doc = makeDocument();
  const renderer = new Renderer(doc, 'game');
  const state = new GameState(20);
  renderer.render(state);
  assert.strictEqual(doc.getElementById('objectif').textContent, state.objectifCourant());
  assert.ok(doc.getElementById('chaton'));
  assert.strictEqual(doc.getElementById('prestige').getAttribute('data-prestige'), '0');
});

// === input.mjs (module `input`) ================================================================

test('InputHandler.brancherCaresse: un clic déclenche logic.caresser() et notifie', () => {
  const doc = makeDocument();
  const renderer = new Renderer(doc, 'game');
  const state = new GameState(21);
  renderer.render(state);
  const appels = [];
  const input = new InputHandler(state, doc, (kind) => appels.push(kind));
  input.brancherCaresse();

  const before = state.ronrons;
  doc.getElementById('chaton').dispatch('click');
  assert.ok(state.ronrons > before);
  assert.deepStrictEqual(appels, ['caresse']);
});

test('InputHandler.brancherAchat: un clic déclenche logic.acheterProducteur(idx)', () => {
  const doc = makeDocument();
  const renderer = new Renderer(doc, 'game');
  const state = new GameState(22);
  state.ronrons = state.coutProducteur(0);
  renderer.render(state);
  const appels = [];
  const input = new InputHandler(state, doc, (kind, payload) => appels.push({ kind, payload }));
  input.brancherAchat(0);

  doc.querySelector('[data-testid="acheter_producteur_0"]').dispatch('click');
  assert.strictEqual(state.producteurs[0].count, 1);
  assert.deepStrictEqual(appels, [{ kind: 'achat', payload: { idx: 0, achete: true } }]);
});

test('InputHandler.brancherRenouveau: un clic déclenche logic.renouveauPortee()', () => {
  const doc = makeDocument();
  const renderer = new Renderer(doc, 'game');
  const state = new GameState(23);
  state.ronrons = 500;
  renderer.render(state);
  const appels = [];
  const input = new InputHandler(state, doc, (kind) => appels.push(kind));
  input.brancherRenouveau();

  doc.getElementById('renouveau_portee').dispatch('click');
  assert.strictEqual(state.ronrons, 0);
  assert.ok(state.prestige > 0);
  assert.deepStrictEqual(appels, ['renouveau']);
});

test('InputHandler.brancherTout: câble les 3 producteurs et les 2 autres affordances', () => {
  const doc = makeDocument();
  const renderer = new Renderer(doc, 'game');
  const state = new GameState(24);
  renderer.render(state);
  const input = new InputHandler(state, doc);
  input.brancherTout();

  assert.ok(doc.querySelector('[data-testid="caresser_chaton"]'));
  for (let i = 0; i < state.producteurs.length; i++) {
    assert.ok(doc.querySelector(`[data-testid="acheter_producteur_${i}"]`));
  }
  assert.ok(doc.getElementById('renouveau_portee'));
});

// === main.mjs (module `main`) ==================================================================

test('createGame: expose window.__game et window.__game_debug au chargement', () => {
  const doc = makeDocument();
  const win = makeWindow(doc);
  const game = createGame({ window: win, document: doc, seed: 30 });

  assert.strictEqual(win.__game, game.gameState);
  assert.strictEqual(typeof win.__game_debug.donnerRonrons, 'function');
  assert.strictEqual(win.__game.tickCount, 0);
});

test('createGame: le HUD objectif est déjà rendu au premier appel (pas de clic requis)', () => {
  const doc = makeDocument();
  const win = makeWindow(doc);
  createGame({ window: win, document: doc, seed: 31 });
  const objectif = doc.getElementById('objectif');
  assert.ok(objectif && objectif.textContent.length > 0);
});

test('createGame: le câblage interne ne réagit visuellement que sur une caresse, jamais sur un achat', () => {
  const doc = makeDocument();
  const win = makeWindow(doc);
  const game = createGame({ window: win, document: doc, seed: 35 });
  let reagitCount = 0;
  const original = game.renderer.reagirCaresse.bind(game.renderer);
  game.renderer.reagirCaresse = () => { reagitCount++; original(); };

  game.gameState.ronrons = game.gameState.coutProducteur(0);
  doc.querySelector('[data-testid="acheter_producteur_0"]').dispatch('click');
  assert.strictEqual(reagitCount, 0);

  doc.querySelector('[data-testid="caresser_chaton"]').dispatch('click');
  assert.strictEqual(reagitCount, 1);
});

test('main.step: fait avancer le tick déterministe et re-rend le compteur', () => {
  const doc = makeDocument();
  const win = makeWindow(doc);
  const game = createGame({ window: win, document: doc, seed: 32 });
  game.gameState.producteurs[0].count = 1;
  const before = game.gameState.tickCount;
  game.step();
  assert.strictEqual(game.gameState.tickCount, before + 1);
  assert.ok(Number(doc.getElementById('compteur-ronrons').getAttribute('data-ronrons')) > 0);
});

test('main.start/stop: pilotent une frame via window.requestAnimationFrame, jamais Date.now', () => {
  const doc = makeDocument();
  const win = makeWindow(doc);
  const game = createGame({ window: win, document: doc, seed: 33 });
  const id = game.start();
  assert.strictEqual(win.frames.length, 1);
  game.stop();
  assert.strictEqual(win.cancelled, id);
});

test('__game_debug.donnerRonrons: ajoute des ronrons et re-rend (réservé à e2e.mjs)', () => {
  const doc = makeDocument();
  const win = makeWindow(doc);
  createGame({ window: win, document: doc, seed: 34 });
  win.__game_debug.donnerRonrons(42);
  assert.strictEqual(win.__game.ronrons, 42);
  assert.strictEqual(doc.getElementById('compteur-ronrons').getAttribute('data-ronrons'), '42');
});

test('autoBootstrap: diffère au DOMContentLoaded si le document est en cours de chargement', () => {
  const doc = makeDocument();
  doc.readyState = 'loading';
  const win = makeWindow(doc);
  const result = autoBootstrap(win, doc);
  assert.strictEqual(result, null);
  assert.strictEqual(win.listenerCount('DOMContentLoaded'), 1);
  assert.strictEqual(win.__game, undefined);

  win.fire('DOMContentLoaded');
  assert.ok(win.__game);
});

test('autoBootstrap: démarre immédiatement si le document est déjà prêt', () => {
  const doc = makeDocument();
  doc.readyState = 'complete';
  const win = makeWindow(doc);
  autoBootstrap(win, doc);
  assert.ok(win.__game);
});

test('autoBootstrap: retourne null si le document est absent (même si window présente)', () => {
  const win = makeWindow(makeDocument());
  assert.strictEqual(autoBootstrap(win, null), null);
});

test('autoBootstrap: retourne null si la fenêtre est absente (même si document présent)', () => {
  const doc = makeDocument();
  assert.strictEqual(autoBootstrap(null, doc), null);
});

test('seedFromLocation: lit ?seed= dans l\'URL, retombe sur DEFAULT_SEED sinon', () => {
  assert.strictEqual(seedFromLocation({ location: { search: '?seed=888' } }), 888);
  assert.strictEqual(seedFromLocation({ location: { search: '' } }), DEFAULT_SEED);
  assert.strictEqual(seedFromLocation({ location: { search: '?seed=abc' } }), DEFAULT_SEED);
  assert.strictEqual(seedFromLocation(null), DEFAULT_SEED);
});
