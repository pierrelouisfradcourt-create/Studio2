// Tests unitaires — une règle, un test, exécutables hors navigateur (node --test).
// Les modules DOM (input/render/main) sont exercés avec un environnement factice injecté.

import { test } from 'node:test';
import assert from 'node:assert';

import {
  Engine, RULES, TERRAIN, STATE_PLAYING, STATE_WON, STATE_LOST, makeRng, manhattan, key,
  neighbors4, inBounds, fnv1a, COLS, ROWS,
} from './engine.mjs';
import { CARDS, DECK_LIST, TYPE, KW, cardById } from './cards.mjs';
import { MAP_TEMPLATES, buildBoard, isRotationSymmetric } from './maps.mjs';
import { chooseAction, playTurn } from './ai.mjs';
import { Controller, HL } from './controller.mjs';
import { InputHandler, intentForKey, INTENT, canvasPoint } from './input.mjs';
import { cellAt, cellRect, handIndexAt, handRect, HAND } from './layout.mjs';
import { Renderer, overlayTextFor, objectiveTextFor, wrapText, WIN_TEXT, LOSE_TEXT, GLYPHS } from './render.mjs';
import { createGame, seedFromLocation, DEFAULT_SEED } from './main.mjs';
import { routeFor, typeFor } from './server.mjs';

// --- outillage -----------------------------------------------------------------------------

const VALLEE_SEED = 3; // seed % 3 === 0 -> « La Vallée »

/** Moteur sans unités, mana réglable : un plateau nu pour poser des situations. */
function fresh(seed = VALLEE_SEED) {
  const e = new Engine({ seed });
  e.units.clear();
  return e;
}

function put(e, cardId, owner, x, y, ready = true) {
  const u = e.spawn(cardId, owner, x, y);
  if (ready) u.summonedPly = 0;
  return u;
}

function setMana(e, owner, n) {
  e.players[owner].mana = n;
  e.players[owner].manaMax = Math.max(n, e.players[owner].manaMax);
}

function setHand(e, owner, cards) {
  e.players[owner].hand = cards.slice();
}

function ok(res) {
  assert.strictEqual(res.ok, true, `action refusée : ${res.error}`);
  return res;
}

function ko(res, fragment) {
  assert.strictEqual(res.ok, false, 'l\'action aurait dû être refusée');
  if (fragment) assert.ok(res.error.includes(fragment), `erreur inattendue : ${res.error}`);
  return res;
}

// --- cartes & plateau -----------------------------------------------------------------------

test('catalogue : 30 cartes de deck, toutes définies, coûts entiers >= 0', () => {
  assert.strictEqual(DECK_LIST.length, 30);
  for (const id of DECK_LIST) {
    const card = cardById(id);
    assert.ok(Number.isInteger(card.cost) && card.cost >= 0, `${id} : coût invalide`);
    assert.ok(Object.values(TYPE).includes(card.type));
  }
  assert.throws(() => cardById('inconnue'));
});

test('gabarits : 7×8, symétriques par rotation 180°, symboles connus', () => {
  for (let i = 0; i < MAP_TEMPLATES.length; i++) {
    const board = buildBoard(i);
    assert.strictEqual(board.length, ROWS);
    assert.ok(board.every((row) => row.length === COLS));
    assert.ok(isRotationSymmetric(MAP_TEMPLATES[i]), `${MAP_TEMPLATES[i].name} n'est pas symétrique`);
  }
});

test('gabarits : les deux tours sont reliées par un chemin praticable à pied', () => {
  for (let i = 0; i < MAP_TEMPLATES.length; i++) {
    const e = new Engine({ seed: i });
    e.units.clear();
    const start = { x: 3, y: 6 };
    const goal = { x: 3, y: 1 };
    const seen = new Set([key(start.x, start.y)]);
    const queue = [start];
    let found = false;
    while (queue.length && !found) {
      const c = queue.shift();
      for (const n of neighbors4(c.x, c.y)) {
        const k = key(n.x, n.y);
        if (seen.has(k) || e.isTowerCell(n.x, n.y) || e.cell(n.x, n.y).terrain === TERRAIN.ROCHER) continue;
        seen.add(k);
        if (n.x === goal.x && n.y === goal.y) found = true;
        queue.push(n);
      }
    }
    assert.ok(found, `${e.mapName} : tours non reliées`);
  }
});

test('géométrie : manhattan, inBounds, neighbors4, fnv1a déterministe', () => {
  assert.strictEqual(manhattan({ x: 0, y: 0 }, { x: 2, y: 3 }), 5);
  assert.ok(inBounds(0, 0) && inBounds(6, 7) && !inBounds(7, 0) && !inBounds(0, -1));
  assert.strictEqual(neighbors4(0, 0).length, 2);
  assert.strictEqual(neighbors4(3, 3).length, 4);
  assert.strictEqual(fnv1a('abc'), fnv1a('abc'));
  assert.notStrictEqual(fnv1a('abc'), fnv1a('abd'));
});

test('rng : même seed => même suite, dans [0,1)', () => {
  const a = makeRng(42);
  const b = makeRng(42);
  for (let i = 0; i < 50; i++) {
    const v = a();
    assert.strictEqual(v, b());
    assert.ok(v >= 0 && v < 1);
  }
});

// --- début de partie, mana, pioche --------------------------------------------------------------

test('init : J1 commence avec 1 mana et 4 cartes, J2 en a 4 en attendant son tour, tours à 20 PV', () => {
  const e = new Engine({ seed: 7 });
  assert.strictEqual(e.current, 0);
  assert.strictEqual(e.players[0].mana, 1);
  assert.strictEqual(e.players[0].manaMax, 1);
  assert.strictEqual(e.players[0].hand.length, RULES.START_HAND + 1);
  assert.strictEqual(e.players[1].hand.length, RULES.START_HAND + 1);
  assert.strictEqual(e.players[0].deck.length, 30 - RULES.START_HAND - 1);
  assert.strictEqual(e.towers[0].hp, RULES.TOWER_HP);
  assert.strictEqual(e.state, STATE_PLAYING);
  assert.strictEqual(e.units.size, 0);
});

test('mana : +1 par tour jusqu\'à 10, rechargé à chaque début de tour', () => {
  const e = new Engine({ seed: 1 });
  for (let i = 0; i < 30; i++) ok(e.apply({ type: 'end' }));
  assert.strictEqual(e.players[0].manaMax, RULES.MAX_MANA);
  assert.strictEqual(e.players[1].manaMax, RULES.MAX_MANA);
  e.players[0].mana = 0;
  ok(e.apply({ type: 'end' }));
  ok(e.apply({ type: 'end' }));
  assert.strictEqual(e.players[0].mana, RULES.MAX_MANA);
});

test('pioche : deck vide => fatigue croissante sur la tour', () => {
  const e = fresh();
  e.players[0].deck = [];
  e.players[0].hand = [];
  e.draw(0);
  e.draw(0);
  assert.strictEqual(e.players[0].fatigue, 2);
  assert.strictEqual(e.towers[0].hp, RULES.TOWER_HP - 3);
});

test('pioche : main pleine => la carte est brûlée', () => {
  const e = fresh();
  e.players[0].hand = new Array(RULES.HAND_MAX).fill('gobelin');
  const deckBefore = e.players[0].deck.length;
  assert.strictEqual(e.draw(0), null);
  assert.strictEqual(e.players[0].hand.length, RULES.HAND_MAX);
  assert.strictEqual(e.players[0].deck.length, deckBefore - 1);
});

test('la partie se termine toujours : fatigue seule, sans aucune action, désigne un vainqueur', () => {
  const e = new Engine({ seed: 5 });
  let plies = 0;
  while (!e.over && plies < 500) {
    ok(e.apply({ type: 'end' }));
    plies++;
  }
  assert.ok(e.over, 'la fatigue doit finir la partie');
  assert.ok(e.winner === 0 || e.winner === 1);
  ko(e.apply({ type: 'end' }), 'terminée');
});

// --- déploiement ----------------------------------------------------------------------------------

test('déploiement : cases à distance <= 2 de sa tour, libres et hors rocher', () => {
  const e = fresh();
  const cells = e.deployCells(0);
  assert.ok(cells.every((c) => manhattan(c, e.towerOf(0)) <= RULES.DEPLOY_RADIUS));
  assert.ok(cells.some((c) => c.x === 3 && c.y === 5));
  assert.ok(!cells.some((c) => c.x === 3 && c.y === 7), 'la case de la tour est exclue');
  put(e, 'gobelin', 0, 3, 6);
  assert.ok(!e.deployCells(0).some((c) => c.x === 3 && c.y === 6), 'case occupée exclue');
});

test('déploiement : un héros allié étend la zone autour de lui', () => {
  const e = fresh();
  put(e, 'paladin', 0, 3, 2);
  const cells = e.deployCells(0);
  assert.ok(cells.some((c) => c.x === 3 && c.y === 1));
  assert.ok(cells.some((c) => c.x === 2 && c.y === 2));
  assert.ok(!cells.some((c) => c.x === 3 && c.y === 4), 'pas à distance 2 du héros');
});

test('jouer une créature : coût payé, carte retirée, unité malade d\'invocation', () => {
  const e = fresh();
  setMana(e, 0, 3);
  setHand(e, 0, ['chevalier', 'gobelin']);
  ok(e.apply({ type: 'play', hand: 0, x: 3, y: 5 }));
  assert.strictEqual(e.players[0].mana, 0);
  assert.deepStrictEqual(e.players[0].hand, ['gobelin']);
  const u = e.unitAt(3, 5);
  assert.strictEqual(u.name, 'Chevalier');
  assert.ok(e.isSummonSick(u));
  assert.strictEqual(e.reachable(u).size, 0);
  assert.deepStrictEqual(e.attackTargets(u), []);
  ko(e.apply({ type: 'play', hand: 0, x: 2, y: 6 }), 'mana');
  ko(e.apply({ type: 'play', hand: 5, x: 2, y: 6 }), 'introuvable');
});

test('jouer une créature hors zone de déploiement est refusé', () => {
  const e = fresh();
  setMana(e, 0, 1);
  setHand(e, 0, ['gobelin']);
  ko(e.apply({ type: 'play', hand: 0, x: 3, y: 1 }), 'déploiement');
  assert.strictEqual(e.players[0].mana, 1);
});

test('Recruteur Gobelin amène 2 Gobelins sur les cases adjacentes libres', () => {
  const e = fresh();
  setMana(e, 0, 2);
  setHand(e, 0, ['recruteur_gobelin']);
  ok(e.apply({ type: 'play', hand: 0, x: 3, y: 5 }));
  const mine = e.unitsOf(0);
  assert.strictEqual(mine.length, 3);
  assert.strictEqual(mine.filter((u) => u.cardId === 'gobelin').length, 2);
  assert.ok(mine.every((u) => manhattan(u, { x: 3, y: 5 }) <= 1));
});

test('Célérité : l\'Assassin agit le tour où il arrive', () => {
  const e = fresh();
  setMana(e, 0, 3);
  setHand(e, 0, ['assassin']);
  ok(e.apply({ type: 'play', hand: 0, x: 3, y: 5 }));
  const u = e.unitAt(3, 5);
  assert.ok(!e.isSummonSick(u));
  assert.ok(e.reachable(u).size > 0);
});

// --- déplacement ----------------------------------------------------------------------------------

test('déplacement : BFS à distance <= MOV, rochers et tours exclus, coût = distance', () => {
  const e = fresh();
  const u = put(e, 'gobelin', 0, 3, 5); // MOV 3
  const cells = e.reachable(u);
  assert.ok(cells.has(key(3, 2)), 'trois cases tout droit');
  assert.strictEqual(cells.get(key(3, 2)).cost, 3);
  assert.ok(!cells.has(key(3, 7)), 'la tour alliée est infranchissable');
  assert.ok(!cells.has(key(0, 5)), 'rocher exclu');
  assert.ok(!cells.has(key(3, 5)), 'la case de départ n\'est pas une destination');
  ok(e.apply({ type: 'move', unit: u.id, x: 3, y: 3 }));
  assert.strictEqual(u.movLeft, 1);
  ko(e.apply({ type: 'move', unit: u.id, x: 3, y: 0 }), 'inaccessible');
});

test('marais : y entrer arrête le déplacement (sauf Vol)', () => {
  const e = fresh();
  const g = put(e, 'gobelin', 0, 1, 5);
  const cells = e.reachable(g);
  assert.ok(cells.has(key(1, 4)), 'entrer dans le marais est possible');
  assert.ok(!cells.has(key(1, 3)), 'mais on ne le traverse pas');
  const d = put(e, 'dragon', 0, 5, 5);
  assert.ok(e.reachable(d).has(key(5, 3)), 'le dragon survole le marais');
});

test('zone de contrôle : entrer au contact d\'un ennemi arrête le déplacement', () => {
  const e = fresh();
  const g = put(e, 'gobelin', 0, 3, 5);
  put(e, 'gobelin', 1, 2, 3);
  const cells = e.reachable(g);
  assert.ok(cells.has(key(3, 3)), 'la case adjacente à l\'ennemi reste atteignable');
  assert.ok(!cells.has(key(3, 2)), 'mais on ne continue pas au-delà');
  assert.ok(cells.has(key(4, 3)) === false || cells.get(key(4, 3)).cost === 3);
});

test('Vol / Piétinement ignorent la zone de contrôle ; Vol survole rochers et unités sans s\'y poser', () => {
  const e = fresh();
  put(e, 'gobelin', 1, 2, 3);
  const d = put(e, 'dragon', 0, 3, 5);
  assert.ok(e.reachable(d).has(key(3, 2)), 'le dragon traverse la ZoC');
  const e1 = fresh();
  put(e1, 'gobelin', 1, 2, 3);
  const g = put(e1, 'gobelin', 0, 3, 5);
  assert.ok(!e1.reachable(g).has(key(3, 2)), 'sans Piétinement, la ZoC arrête en (3,3)');
  g.equips.push('epee_du_titan');
  assert.ok(e1.reachable(g).has(key(3, 2)), 'Piétinement traverse la ZoC');
  const e2 = fresh();
  const d2 = put(e2, 'dragon', 0, 1, 6);
  put(e2, 'gobelin', 0, 1, 5);
  const cells = e2.reachable(d2);
  assert.ok(!cells.has(key(1, 5)), 'ne se pose pas sur un allié');
  assert.ok(cells.has(key(1, 4)), 'mais passe au-dessus');
  const d3 = put(e2, 'dragon', 0, 0, 6);
  const c3 = e2.reachable(d3);
  assert.ok(!c3.has(key(0, 5)), 'ne se pose pas sur un rocher');
  assert.ok(c3.has(key(0, 4)), 'mais le survole');
});

test('une unité ne peut agir que pendant le tour de son camp', () => {
  const e = fresh();
  const enemy = put(e, 'gobelin', 1, 3, 2);
  assert.strictEqual(e.reachable(enemy).size, 0);
  ko(e.apply({ type: 'move', unit: enemy.id, x: 3, y: 3 }), 'allié');
});

// --- combat ---------------------------------------------------------------------------------------

test('attaque au corps à corps : dégâts, riposte, l\'attaque clôt l\'activation', () => {
  const e = fresh();
  const a = put(e, 'chevalier', 0, 3, 5); // 3/3
  const b = put(e, 'golem', 1, 3, 4);     // 2/7
  ok(e.apply({ type: 'attack', unit: a.id, target: { unit: b.id } }));
  assert.strictEqual(b.hp, 4);
  assert.strictEqual(a.hp, 1, 'riposte du golem');
  assert.ok(a.attacked);
  assert.strictEqual(a.movLeft, 0);
  assert.strictEqual(e.reachable(a).size, 0);
  ko(e.apply({ type: 'attack', unit: a.id, target: { unit: b.id } }), 'illégale');
});

test('attaque à distance : pas de riposte hors de portée du défenseur', () => {
  const e = fresh();
  const a = put(e, 'archer', 0, 3, 5);   // 2/2 portée 2
  const b = put(e, 'chevalier', 1, 3, 3);
  ok(e.apply({ type: 'attack', unit: a.id, target: { unit: b.id } }));
  assert.strictEqual(b.hp, 1);
  assert.strictEqual(a.hp, 2, 'le chevalier ne riposte pas à distance 2');
  const e2 = fresh();
  const a2 = put(e2, 'archer', 0, 3, 5);            // 2/2 portée 2
  const b2 = put(e2, 'elementaire_de_feu', 1, 3, 3); // 2/3 portée 2
  ok(e2.apply({ type: 'attack', unit: a2.id, target: { unit: b2.id } }));
  assert.strictEqual(b2.hp, 1);
  assert.ok(!e2.units.has(a2.id), 'un défenseur à portée 2 riposte à distance 2 : l\'archer meurt');
});

test('mort : l\'unité disparaît, l\'attaquant ne subit pas de riposte', () => {
  const e = fresh();
  const a = put(e, 'ogre', 0, 3, 5); // 5/7
  const b = put(e, 'loup', 1, 3, 4); // 2/1
  ok(e.apply({ type: 'attack', unit: a.id, target: { unit: b.id } }));
  assert.ok(!e.units.has(b.id));
  assert.strictEqual(a.hp, 7);
});

test('Provocation : si un Golem est à portée, il est la seule cible possible', () => {
  const e = fresh();
  const a = put(e, 'chevalier', 0, 3, 5);
  const golem = put(e, 'golem', 1, 2, 5);
  const wolf = put(e, 'loup', 1, 4, 5);
  const targets = e.attackTargets(a);
  assert.deepStrictEqual(targets, [{ unit: golem.id }]);
  ko(e.apply({ type: 'attack', unit: a.id, target: { unit: wolf.id } }), 'illégale');
});

test('plancher de dégâts (brique KB) : la forêt réduit de 1 mais jamais sous 1', () => {
  const e = fresh();
  const a = put(e, 'archer', 0, 1, 4);  // ATQ 2
  const b = put(e, 'golem', 1, 1, 6);   // forêt en (1,6)
  assert.strictEqual(e.armorOf(b), 1);
  assert.strictEqual(e.cell(1, 6).terrain, TERRAIN.FORET);
  ok(e.apply({ type: 'attack', unit: a.id, target: { unit: b.id } }));
  assert.strictEqual(b.hp, 6, '2 - 1 armure = 1');
  const g = put(e, 'gobelin', 0, 2, 6); // ATQ 1
  ok(e.apply({ type: 'attack', unit: g.id, target: { unit: b.id } }));
  assert.strictEqual(b.hp, 5, 'plancher : 1 dégât malgré l\'armure');
});

test('tour ennemie : attaquable à portée, sa chute donne la victoire', () => {
  const e = fresh();
  const a = put(e, 'ogre', 0, 3, 1);
  assert.ok(e.attackTargets(a).some((t) => t.tower));
  e.towerOf(1).hp = 5;
  ok(e.apply({ type: 'attack', unit: a.id, target: { tower: true } }));
  assert.strictEqual(e.towerOf(1).hp, 0);
  assert.strictEqual(e.state, STATE_WON);
  assert.strictEqual(e.winner, 0);
});

test('défaite : la tour de J1 tombe => état lost', () => {
  const e = fresh();
  e.towerOf(0).hp = 0;
  e.checkWin();
  assert.strictEqual(e.state, STATE_LOST);
  assert.strictEqual(e.winner, 1);
});

test('la tour tire au début du tour de son camp sur l\'ennemi adjacent le plus fort', () => {
  const e = fresh();
  const weak = put(e, 'gobelin', 0, 2, 0);
  const strong = put(e, 'chevalier', 0, 4, 0);
  ok(e.apply({ type: 'end' }));
  assert.strictEqual(strong.hp, 3 - RULES.TOWER_ATK);
  assert.strictEqual(weak.hp, 1);
});

// --- sorts -------------------------------------------------------------------------------------------

test('Boule de Feu : 3 dégâts en 3×3, alliés et tour compris, la case devient un Brasier 4 tours', () => {
  const e = fresh();
  setMana(e, 0, 4);
  setHand(e, 0, ['boule_de_feu']);
  const ally = put(e, 'golem', 0, 3, 2);
  const foe = put(e, 'chevalier', 1, 4, 1);
  const far = put(e, 'chevalier', 1, 3, 4);
  ok(e.apply({ type: 'play', hand: 0, x: 3, y: 1 }));
  assert.strictEqual(ally.hp, 4);
  assert.ok(!e.units.has(foe.id), 'le chevalier (3 PV) meurt');
  assert.strictEqual(far.hp, 3, 'hors de la zone');
  assert.strictEqual(e.towerOf(1).hp, RULES.TOWER_HP - 3);
  assert.strictEqual(e.cell(3, 1).terrain, TERRAIN.BRASIER);
  assert.strictEqual(e.cell(3, 1).ttl, 4);
  for (let i = 0; i < 4; i++) ok(e.apply({ type: 'end' }));
  assert.strictEqual(e.cell(3, 1).terrain, TERRAIN.PLAINE, 'le brasier s\'éteint');
});

test('Brasier : 2 dégâts en fin de tour au propriétaire non volant ; le Vol y échappe', () => {
  const e = fresh(1); // Col de Lave : lave permanente en (0,3)
  assert.strictEqual(e.cell(0, 3).terrain, TERRAIN.BRASIER);
  const g = put(e, 'golem', 0, 0, 3);
  const d = put(e, 'dragon', 0, 6, 3);
  assert.strictEqual(e.cell(6, 3).terrain, TERRAIN.BRASIER);
  ok(e.apply({ type: 'end' }));
  assert.strictEqual(g.hp, 5);
  assert.strictEqual(d.hp, 5);
});

test('Éclair : 3 dégâts, ennemi uniquement', () => {
  const e = fresh();
  setMana(e, 0, 2);
  setHand(e, 0, ['eclair']);
  const foe = put(e, 'golem', 1, 3, 2);
  const ally = put(e, 'golem', 0, 3, 5);
  ko(e.apply({ type: 'play', hand: 0, unit: ally.id }), 'ennemi');
  ok(e.apply({ type: 'play', hand: 0, unit: foe.id }));
  assert.strictEqual(foe.hp, 4);
});

test('Portail : téléporte un allié sur une case libre à 3 cases ou moins', () => {
  const e = fresh();
  setMana(e, 0, 2);
  setHand(e, 0, ['portail', 'portail']);
  const u = put(e, 'golem', 0, 3, 5);
  ko(e.apply({ type: 'play', hand: 0, unit: u.id, toX: 3, toY: 1 }), 'portail');
  ko(e.apply({ type: 'play', hand: 0, unit: u.id, toX: 0, toY: 5 }), 'portail');
  ok(e.apply({ type: 'play', hand: 0, unit: u.id, toX: 3, toY: 2 }));
  assert.deepStrictEqual([u.x, u.y], [3, 2]);
});

test('Bouclier Temporel : absorbe entièrement les prochains dégâts, une fois', () => {
  const e = fresh();
  setMana(e, 0, 1);
  setHand(e, 0, ['bouclier_temporel']);
  const a = put(e, 'chevalier', 0, 3, 5);
  const b = put(e, 'ogre', 1, 3, 4);
  ok(e.apply({ type: 'play', hand: 0, unit: a.id }));
  assert.ok(a.shield);
  ok(e.apply({ type: 'attack', unit: a.id, target: { unit: b.id } }));
  assert.strictEqual(a.hp, 3, 'la riposte de l\'ogre est absorbée');
  assert.ok(!a.shield);
});

test('Mur de Pierre : une case libre devient un rocher 6 tours, qui bloque le passage', () => {
  const e = fresh();
  setMana(e, 0, 2);
  setHand(e, 0, ['mur_de_pierre']);
  const g = put(e, 'gobelin', 0, 3, 5);
  ko(e.apply({ type: 'play', hand: 0, x: 3, y: 3 }), 'mur'); // fontaine : interdit
  assert.ok(e.reachable(g).has(key(3, 2)));
  ok(e.apply({ type: 'play', hand: 0, x: 3, y: 2 }));
  assert.strictEqual(e.cell(3, 2).terrain, TERRAIN.ROCHER);
  assert.ok(!e.reachable(g).has(key(3, 2)));
  for (let i = 0; i < 6; i++) ok(e.apply({ type: 'end' }));
  assert.strictEqual(e.cell(3, 2).terrain, TERRAIN.PLAINE);
});

test('Soin : rend 4 PV sans dépasser le maximum', () => {
  const e = fresh();
  setMana(e, 0, 2);
  setHand(e, 0, ['soin']);
  const u = put(e, 'golem', 0, 3, 5);
  u.hp = 5;
  ok(e.apply({ type: 'play', hand: 0, unit: u.id }));
  assert.strictEqual(u.hp, 7);
});

test('Gel : la cible ne bouge pas, n\'attaque pas, ne riposte pas à son prochain tour, puis dégèle', () => {
  const e = fresh();
  setMana(e, 0, 2);
  setHand(e, 0, ['gel']);
  const foe = put(e, 'chevalier', 1, 3, 4);
  const mine = put(e, 'gobelin', 0, 3, 5);
  ok(e.apply({ type: 'play', hand: 0, unit: foe.id }));
  assert.ok(e.isFrozen(foe));
  ok(e.apply({ type: 'attack', unit: mine.id, target: { unit: foe.id } }));
  assert.strictEqual(mine.hp, 1, 'pas de riposte gelée');
  ok(e.apply({ type: 'end' }));
  assert.strictEqual(e.current, 1);
  assert.strictEqual(e.reachable(foe).size, 0);
  assert.deepStrictEqual(e.attackTargets(foe), []);
  ok(e.apply({ type: 'end' }));
  ok(e.apply({ type: 'end' }));
  assert.ok(!e.isFrozen(foe));
  assert.ok(e.reachable(foe).size > 0);
});

// --- équipements ---------------------------------------------------------------------------------------

test('équipement : bonus immédiats (ATQ, portée, déplacement, Vol), 2 au maximum', () => {
  const e = fresh();
  setMana(e, 0, 10);
  setHand(e, 0, ['epee_du_titan', 'arc_long', 'bottes_ailees', 'couronne_du_tyran']);
  const u = put(e, 'chevalier', 0, 3, 5);
  ok(e.apply({ type: 'play', hand: 0, unit: u.id }));
  assert.strictEqual(e.atkOf(u), 6);
  ok(e.apply({ type: 'play', hand: 0, unit: u.id }));
  assert.strictEqual(e.rngOf(u), 2);
  ko(e.apply({ type: 'play', hand: 0, unit: u.id }), '2 équipements');
  const w = put(e, 'gobelin', 0, 2, 6);
  ok(e.apply({ type: 'play', hand: 1, unit: w.id })); // couronne
  assert.strictEqual(e.movOf(w), 4);
  assert.strictEqual(w.movLeft, 4);
  ok(e.apply({ type: 'play', hand: 0, unit: w.id })); // bottes
  assert.ok(e.has(w, KW.VOL));
});

test('équipement : revient dans la main du propriétaire à la mort du porteur', () => {
  const e = fresh();
  setHand(e, 0, []);
  const a = put(e, 'gobelin', 0, 3, 5);
  a.equips.push('epee_du_titan');
  const b = put(e, 'ogre', 1, 3, 4);
  e.current = 1;
  ok(e.apply({ type: 'attack', unit: b.id, target: { unit: a.id } }));
  assert.ok(!e.units.has(a.id));
  assert.deepStrictEqual(e.players[0].hand, ['epee_du_titan']);
});

test('équipement : perdu si la main est pleine', () => {
  const e = fresh();
  setHand(e, 0, new Array(RULES.HAND_MAX).fill('gobelin'));
  const a = put(e, 'gobelin', 0, 3, 5);
  a.equips.push('arc_long');
  const b = put(e, 'ogre', 1, 3, 4);
  e.current = 1;
  ok(e.apply({ type: 'attack', unit: b.id, target: { unit: a.id } }));
  assert.strictEqual(e.players[0].hand.length, RULES.HAND_MAX);
  assert.ok(!e.players[0].hand.includes('arc_long'));
});

test('rendre un équipement : 1 mana, la carte revient en main, les bonus disparaissent', () => {
  const e = fresh();
  setMana(e, 0, 1);
  setHand(e, 0, []);
  const u = put(e, 'chevalier', 0, 3, 5);
  u.equips.push('epee_du_titan');
  ok(e.apply({ type: 'unequip', unit: u.id, index: 0 }));
  assert.strictEqual(e.players[0].mana, 0);
  assert.deepStrictEqual(e.players[0].hand, ['epee_du_titan']);
  assert.strictEqual(e.atkOf(u), 3);
  ko(e.apply({ type: 'unequip', unit: u.id, index: 0 }), 'introuvable');
});

// --- héros : auras et capacités -----------------------------------------------------------------------

test('Seigneur de Guerre : +1 ATQ aux alliés à distance <= 2, pas au-delà, pas à lui-même', () => {
  const e = fresh();
  const lord = put(e, 'seigneur_de_guerre', 0, 3, 5);
  const near = put(e, 'gobelin', 0, 3, 3);
  const far = put(e, 'gobelin', 0, 3, 2);
  assert.strictEqual(e.atkOf(near), 2);
  assert.strictEqual(e.atkOf(far), 1);
  assert.strictEqual(e.atkOf(lord), 3);
});

test('Archimage : les sorts visant une case de son aura coûtent 1 de moins (jamais sous 0)', () => {
  const e = fresh();
  put(e, 'archimage', 0, 3, 5);
  const fireball = cardById('boule_de_feu');
  assert.strictEqual(e.costOf(fireball, 0, { x: 3, y: 3 }), 3);
  assert.strictEqual(e.costOf(fireball, 0, { x: 3, y: 1 }), 4);
  assert.strictEqual(e.costOf(cardById('bouclier_temporel'), 0, { x: 3, y: 4 }), 0);
  assert.strictEqual(e.costOf(cardById('gobelin'), 0, { x: 3, y: 4 }), 1, 'pas de remise sur les créatures');
  setMana(e, 0, 3);
  setHand(e, 0, ['boule_de_feu']);
  ok(e.apply({ type: 'play', hand: 0, x: 3, y: 3 }));
  assert.strictEqual(e.players[0].mana, 0);
});

test('Paladin : -1 dégât aux alliés adjacents (plancher 1)', () => {
  const e = fresh();
  put(e, 'paladin', 0, 3, 5);
  const ally = put(e, 'golem', 0, 3, 4);  // 2/7
  const far = put(e, 'golem', 0, 3, 2);
  const foe = put(e, 'ogre', 1, 3, 3);    // ATQ 5
  assert.strictEqual(e.armorOf(ally), 1);
  assert.strictEqual(e.armorOf(far), 0, 'hors de l\'aura (rayon 1)');
  e.current = 1;
  ok(e.apply({ type: 'attack', unit: foe.id, target: { unit: ally.id } }));
  assert.strictEqual(ally.hp, 3, 'ogre 5 - 1 armure = 4 dégâts');
});

test('Nécromancienne : un allié mort dans l\'aura laisse une Ombre ; une Ombre n\'en laisse pas', () => {
  const e = fresh();
  put(e, 'necromancienne', 0, 3, 5);
  const ally = put(e, 'gobelin', 0, 3, 4);
  const foe = put(e, 'ogre', 1, 3, 3);
  e.current = 1;
  ok(e.apply({ type: 'attack', unit: foe.id, target: { unit: ally.id } }));
  const ombre = e.unitAt(3, 4);
  assert.ok(ombre && ombre.cardId === 'ombre');
  assert.strictEqual(ombre.owner, 0);
  foe.attacked = false;
  ok(e.apply({ type: 'attack', unit: foe.id, target: { unit: ombre.id } }));
  assert.strictEqual(e.unitAt(3, 4), null, 'pas d\'Ombre d\'Ombre');
});

test('capacités : Ralliement, Étincelle, Drain, Bénédiction — une fois par tour, coût en mana', () => {
  const e = fresh();
  setMana(e, 0, 10);
  const lord = put(e, 'seigneur_de_guerre', 0, 3, 5);
  const g = put(e, 'gobelin', 0, 3, 4);
  ok(e.apply({ type: 'ability', unit: lord.id, target: { self: true } }));
  assert.strictEqual(g.movLeft, 4);
  assert.strictEqual(e.players[0].mana, 8);
  ko(e.apply({ type: 'ability', unit: lord.id, target: { self: true } }), 'indisponible');

  const mage = put(e, 'archimage', 0, 2, 5);
  const foe = put(e, 'golem', 1, 2, 3);
  ok(e.apply({ type: 'ability', unit: mage.id, target: { unit: foe.id } }));
  assert.strictEqual(foe.hp, 6);

  const necro = put(e, 'necromancienne', 0, 4, 5);
  necro.hp = 1;
  const foe2 = put(e, 'golem', 1, 4, 3);
  ok(e.apply({ type: 'ability', unit: necro.id, target: { unit: foe2.id } }));
  assert.strictEqual(foe2.hp, 5);
  assert.strictEqual(necro.hp, 3);

  const pal = put(e, 'paladin', 0, 2, 4);
  ok(e.apply({ type: 'ability', unit: pal.id, target: { unit: g.id } }));
  assert.ok(g.shield);
  assert.strictEqual(e.players[0].mana, 8 - 1 - 2 - 2);
  ko(e.apply({ type: 'ability', unit: g.id, target: { unit: foe.id } }), 'capacité');
  e.players[0].mana = 0;
  const pal2 = put(e, 'paladin', 0, 5, 5);
  assert.deepStrictEqual(e.abilityTargets(pal2), []);
});

// --- terrain, fin de tour ------------------------------------------------------------------------------

test('fontaine : chaque fontaine occupée donne +1 mana au début du tour', () => {
  const e = fresh();
  put(e, 'gobelin', 0, 3, 3);
  put(e, 'gobelin', 0, 3, 4);
  ok(e.apply({ type: 'end' }));
  ok(e.apply({ type: 'end' }));
  assert.strictEqual(e.players[0].manaMax, 2);
  assert.strictEqual(e.players[0].mana, 4);
});

test('Prêtresse : soigne 1 PV aux alliés adjacents en fin de tour', () => {
  const e = fresh();
  put(e, 'pretresse', 0, 3, 5);
  const a = put(e, 'chevalier', 0, 3, 4);
  a.hp = 1;
  const far = put(e, 'chevalier', 0, 3, 2);
  far.hp = 1;
  ok(e.apply({ type: 'end' }));
  assert.strictEqual(a.hp, 2);
  assert.strictEqual(far.hp, 1);
});

test('fin de tour : déplacement et attaque rendus, la pioche a lieu, le tour compte', () => {
  const e = fresh();
  const u = put(e, 'gobelin', 0, 3, 5);
  ok(e.apply({ type: 'move', unit: u.id, x: 3, y: 4 }));
  u.attacked = true;
  const handBefore = e.players[1].hand.length;
  ok(e.apply({ type: 'end' }));
  assert.strictEqual(e.players[1].hand.length, handBefore + 1);
  ok(e.apply({ type: 'end' }));
  assert.strictEqual(e.round, 2);
  assert.strictEqual(u.movLeft, 3);
  assert.ok(!u.attacked);
});

test('snapshot / hashState : sérialisable, déterministe, sensible à l\'état', () => {
  const e = new Engine({ seed: 11 });
  const h1 = e.hashState();
  assert.strictEqual(new Engine({ seed: 11 }).hashState(), h1);
  assert.notStrictEqual(new Engine({ seed: 12 }).hashState(), h1);
  ok(e.apply({ type: 'end' }));
  assert.notStrictEqual(e.hashState(), h1);
  const s = e.snapshot();
  assert.strictEqual(typeof JSON.stringify(s), 'string');
  assert.strictEqual(s.players[0].hand.length, e.players[0].hand.length);
});

// --- bot ------------------------------------------------------------------------------------------------

test('bot : ne propose que des actions légales et finit toujours son tour', () => {
  for (const seed of [1, 2, 3, 4, 5, 6]) {
    const e = new Engine({ seed });
    let plies = 0;
    while (!e.over && plies < 120) {
      const before = e.current;
      playTurn(e, e.current);
      assert.ok(e.over || e.current !== before);
      plies++;
    }
    assert.ok(e.over, `seed ${seed} : la partie bot contre bot doit se terminer`);
  }
});

test('bot : frappe la tour ennemie quand elle est à portée', () => {
  const e = fresh();
  put(e, 'ogre', 0, 3, 1);
  const action = chooseAction(e, 0);
  assert.strictEqual(action.type, 'attack');
  assert.deepStrictEqual(action.target, { tower: true });
});

test('bot : rend end hors de son tour ou partie finie', () => {
  const e = fresh();
  assert.deepStrictEqual(chooseAction(e, 1), { type: 'end' });
  e.towerOf(1).hp = 0;
  e.checkWin();
  assert.deepStrictEqual(chooseAction(e, 0), { type: 'end' });
});

// --- contrôleur -------------------------------------------------------------------------------------------

test('contrôleur : carte -> zone de déploiement en surbrillance -> pose', () => {
  const e = fresh();
  setMana(e, 0, 1);
  setHand(e, 0, ['gobelin']);
  const c = new Controller(e);
  assert.ok(c.clickHand(0));
  const hl = c.highlights();
  assert.ok(hl.cells.get(key(3, 5)) === HL.DEPLOY);
  assert.ok(c.clickCell(3, 5));
  assert.strictEqual(e.unitAt(3, 5).name, 'Gobelin');
  assert.strictEqual(c.sel, null);
  assert.ok(c.clickHand(0) === false, 'main vide : rien à sélectionner');
});

test('contrôleur : unité -> déplacement -> attaque -> désélection', () => {
  const e = fresh();
  const u = put(e, 'chevalier', 0, 3, 5);
  const foe = put(e, 'gobelin', 1, 3, 2);
  const c = new Controller(e);
  assert.ok(c.clickCell(3, 5));
  let hl = c.highlights();
  assert.strictEqual(hl.cells.get(key(3, 5)), HL.SELECTED);
  assert.strictEqual(hl.cells.get(key(3, 4)), HL.MOVE);
  assert.ok(c.clickCell(3, 3));
  assert.deepStrictEqual([u.x, u.y], [3, 3]);
  hl = c.highlights();
  assert.strictEqual(hl.units.get(foe.id), HL.ATTACK);
  assert.ok(c.clickCell(3, 2));
  assert.ok(!e.units.has(foe.id));
  assert.strictEqual(c.sel, null);
  assert.ok(c.clickCell(3, 3));
  assert.ok(c.clickCell(3, 3), 'recliquer désélectionne');
  assert.strictEqual(c.sel, null);
});

test('contrôleur : portail en deux temps, capacité ciblée, équipement, fin de tour', () => {
  const e = fresh();
  setMana(e, 0, 10);
  setHand(e, 0, ['portail', 'epee_du_titan']);
  const u = put(e, 'chevalier', 0, 3, 5);
  const pal = put(e, 'paladin', 0, 2, 4);
  const foe = put(e, 'golem', 1, 3, 2);
  const c = new Controller(e);
  assert.ok(c.clickHand(0));
  assert.strictEqual(c.highlights().units.get(u.id), HL.TARGET);
  assert.ok(c.clickCell(3, 5));
  assert.strictEqual(c.sel.stage, 1);
  assert.strictEqual(c.highlights().cells.get(key(3, 3)), HL.TARGET);
  assert.ok(c.clickCell(3, 3));
  assert.deepStrictEqual([u.x, u.y], [3, 3]);
  assert.ok(c.clickHand(0));
  assert.ok(c.clickCell(3, 3));
  assert.deepStrictEqual(u.equips, ['epee_du_titan']);
  assert.ok(c.clickCell(2, 4));
  assert.ok(c.useAbility());
  assert.strictEqual(c.sel.kind, 'ability');
  assert.ok(c.clickCell(3, 3));
  assert.ok(u.shield);
  assert.ok(c.clickCell(3, 3));
  assert.ok(c.unequip(0));
  assert.deepStrictEqual(u.equips, []);
  assert.ok(c.endTurn());
  assert.strictEqual(e.current, 1);
  assert.ok(!c.isHumanTurn);
  assert.strictEqual(c.clickCell(3, 2), false, 'rien pendant le tour adverse');
  assert.strictEqual(c.highlights().cells.size, 0);
  void foe;
});

test('contrôleur : messages d\'aide, annulation, mana insuffisant', () => {
  const e = fresh();
  setMana(e, 0, 0);
  setHand(e, 0, ['gobelin']);
  const c = new Controller(e);
  assert.strictEqual(c.clickHand(0), false);
  assert.ok(c.message.includes('Mana'));
  assert.ok(c.cancel());
  assert.strictEqual(c.message, '');
  assert.strictEqual(c.useAbility(), false);
  assert.strictEqual(c.unequip(), false);
});

// --- entrées, géométrie, rendu, orchestration ----------------------------------------------------------------

test('input : touches -> intentions ; clic canvas -> coordonnées', () => {
  assert.deepStrictEqual(intentForKey('Escape'), { kind: INTENT.CANCEL });
  assert.deepStrictEqual(intentForKey('e'), { kind: INTENT.END });
  assert.deepStrictEqual(intentForKey('Enter'), { kind: INTENT.END });
  assert.deepStrictEqual(intentForKey('a'), { kind: INTENT.ABILITY });
  assert.deepStrictEqual(intentForKey('3'), { kind: INTENT.HAND, index: 2 });
  assert.strictEqual(intentForKey('z'), null);
  const listeners = {};
  const target = { addEventListener: (ev, fn) => { listeners[ev] = fn; } };
  const canvas = {
    width: 960, height: 720, addEventListener: (ev, fn) => { listeners[`canvas:${ev}`] = fn; },
    getBoundingClientRect: () => ({ left: 10, top: 20, width: 480, height: 360 }),
  };
  const input = new InputHandler(target, canvas);
  listeners.keydown({ key: 'e' });
  listeners.keydown({ key: 'q' });
  listeners['canvas:click']({ clientX: 10 + 100, clientY: 20 + 50 });
  const intents = input.drain();
  assert.deepStrictEqual(intents[0], { kind: INTENT.END });
  assert.deepStrictEqual(intents[1], { kind: INTENT.CLICK, px: 200, py: 100 });
  assert.deepStrictEqual(input.drain(), []);
  assert.deepStrictEqual(canvasPoint({ width: 10, height: 10 }, { clientX: 3, clientY: 4 }), { px: 3, py: 4 });
});

test('layout : cellAt et handIndexAt inversent cellRect et handRect', () => {
  for (let y = 0; y < ROWS; y++) {
    for (let x = 0; x < COLS; x++) {
      const r = cellRect(x, y);
      assert.deepStrictEqual(cellAt(r.x + 5, r.y + 5), { x, y });
    }
  }
  assert.strictEqual(cellAt(0, 0), null);
  assert.strictEqual(cellAt(900, 100), null);
  for (let i = 0; i < HAND.max; i++) {
    const r = handRect(i);
    assert.strictEqual(handIndexAt(r.x + 3, r.y + 3), i);
  }
  assert.strictEqual(handIndexAt(10, 10), null);
});

function makeCtx() {
  const calls = { fillText: [], fillRect: [], arc: [] };
  const noop = () => {};
  const ctx = new Proxy({ calls }, {
    get(t, p) {
      if (p === 'calls') return t.calls;
      if (p === 'measureText') return (s) => ({ width: String(s).length * 6 });
      if (p in t) return t[p];
      if (p === 'fillText') return (...a) => t.calls.fillText.push(a);
      if (p === 'fillRect') return (...a) => t.calls.fillRect.push(a);
      if (p === 'arc') return (...a) => t.calls.arc.push(a);
      return noop;
    },
    set(t, p, v) { t[p] = v; return true; },
  });
  return ctx;
}

function makeCanvas() {
  const ctx = makeCtx();
  return { width: 960, height: 720, ctx, getContext: () => ctx, addEventListener() {}, getBoundingClientRect: () => ({ left: 0, top: 0, width: 960, height: 720 }) };
}

test('render : dessine plateau, unités et main sans lever ; textes d\'overlay et d\'objectif', () => {
  const e = fresh();
  put(e, 'dragon', 0, 3, 5);
  setHand(e, 0, ['boule_de_feu', 'gobelin']);
  const canvas = makeCanvas();
  const r = new Renderer(canvas);
  const c = new Controller(e);
  c.clickCell(3, 5);
  r.render(e, c, 0);
  const texts = canvas.ctx.calls.fillText.map((a) => a[0]);
  assert.ok(texts.includes(GLYPHS.dragon));
  assert.ok(texts.some((t) => t.includes('Boule de Feu')));
  assert.ok(canvas.ctx.calls.fillRect.length > COLS * ROWS);
  assert.strictEqual(overlayTextFor(e), '');
  e.towerOf(1).hp = 0;
  e.checkWin();
  assert.strictEqual(overlayTextFor(e), WIN_TEXT);
  e.state = STATE_LOST;
  assert.strictEqual(overlayTextFor(e), LOSE_TEXT);
  r.renderOverlay(e);
  assert.ok(objectiveTextFor(e).includes('tour ennemie'));
  assert.deepStrictEqual(wrapText(canvas.ctx, 'un deux trois quatre', 60), ['un deux', 'trois', 'quatre']);
});

function makeDom() {
  const nodes = {};
  const mk = (id) => {
    const listeners = {};
    const canvas = makeCanvas();
    return {
      ...canvas,
      id,
      listeners,
      classList: {
        set: new Set(['hidden']),
        add(c) { this.set.add(c); },
        remove(c) { this.set.delete(c); },
        contains(c) { return this.set.has(c); },
      },
      textContent: '',
      children: [],
      appendChild(child) { this.children.push(child); },
      addEventListener(ev, fn) { (listeners[ev] ||= []).push(fn); },
      click() { for (const fn of listeners.click ?? []) fn({}); },
    };
  };
  for (const id of ['gameCanvas', 'overlay', 'overlayText', 'objectif', 'log', 'restart', 'endTurn', 'ability', 'unequip', 'cancel']) nodes[id] = mk(id);
  const doc = { readyState: 'complete', getElementById: (id) => nodes[id], createElement: () => ({ textContent: '' }) };
  const timers = [];
  const listeners = {};
  const win = {
    timers,
    setTimeout: (fn) => { timers.push(fn); return timers.length; },
    requestAnimationFrame: () => 7,
    cancelAnimationFrame: () => {},
    addEventListener: (ev, fn) => { listeners[ev] = fn; },
    location: { search: '?seed=5' },
  };
  return { nodes, doc, win };
}

test('main : contrat de jouabilité (window.__game, __game_debug.hit, #overlay, #restart)', () => {
  const { nodes, doc, win } = makeDom();
  const game = createGame({ window: win, document: doc, seed: 5, aiStepMs: 0 });
  assert.strictEqual(win.__game.state, STATE_PLAYING);
  assert.strictEqual(win.__game.over, false);
  assert.strictEqual(win.__game.seed, 5);
  assert.strictEqual(typeof win.__game.hash, 'string');
  assert.ok(nodes.objectif.textContent.includes('tour ennemie'));
  assert.ok(nodes.overlay.classList.contains('hidden'));
  win.__game_debug.hit();
  assert.strictEqual(win.__game.state, STATE_LOST);
  assert.ok(!nodes.overlay.classList.contains('hidden'));
  assert.strictEqual(nodes.overlayText.textContent, LOSE_TEXT);
  nodes.restart.click();
  assert.strictEqual(win.__game.state, STATE_PLAYING);
  assert.ok(nodes.overlay.classList.contains('hidden'));
  win.__game_debug.forceWin();
  assert.strictEqual(win.__game.state, STATE_WON);
  game.reset();
  assert.strictEqual(game.engine.round, 1);
});

test('main : fin de tour humaine => le bot joue par pas de temps, puis la main revient à l\'humain', () => {
  const { nodes, doc, win } = makeDom();
  const game = createGame({ window: win, document: doc, seed: 5, aiStepMs: 0 });
  nodes.endTurn.click();
  game.step();
  assert.strictEqual(game.engine.current, 1);
  let guard = 0;
  while (win.timers.length && game.engine.current === 1 && guard < 300) {
    win.timers.shift()();
    guard++;
  }
  assert.strictEqual(game.engine.current, 0);
  assert.strictEqual(game.engine.round, 2);
  assert.ok(guard >= 1, 'le tour du bot passe par au moins un pas de temps');
  assert.strictEqual(win.__game.aiActions, game.engine.log.filter((l) => l.startsWith('T1·J2') && !l.includes('début du tour')).length,
    'chaque action du bot est comptée');
  game.aiTurn();
  assert.strictEqual(game.engine.current, 0);
  assert.strictEqual(game.stop(), undefined);
});

test('main : seed d\'URL et bootstrap', () => {
  assert.strictEqual(seedFromLocation({ location: { search: '?seed=42' } }), 42);
  assert.strictEqual(seedFromLocation({ location: { search: '' } }), DEFAULT_SEED);
  assert.strictEqual(seedFromLocation({}), DEFAULT_SEED);
});

test('server : routes autorisées, brique KB servie, traversée refusée', () => {
  assert.strictEqual(routeFor('GET', '/').relPath, 'index.html');
  assert.strictEqual(routeFor('GET', '/engine.mjs').status, 200);
  assert.strictEqual(routeFor('GET', '/knowledge_base/systems/combat/damage_floor.mjs').status, 200);
  assert.strictEqual(routeFor('GET', '/knowledge_base/../forge/x.mjs').status, 404);
  assert.strictEqual(routeFor('GET', '/../secret.mjs').status, 404);
  assert.strictEqual(routeFor('POST', '/').status, 405);
  assert.strictEqual(typeFor('/a.mjs'), 'text/javascript; charset=utf-8');
  assert.strictEqual(typeFor('/a.bin'), 'application/octet-stream');
});
