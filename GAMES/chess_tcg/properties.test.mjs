// Tests de propriétés — invariants tenus sur de longues séquences d'actions LÉGALES tirées au
// hasard (rng injecté), sur plusieurs seeds. Ce que le moteur promet, quoi qu'on lui demande.

import { test } from 'node:test';
import assert from 'node:assert';

import { Engine, RULES, TERRAIN, makeRng, COLS, ROWS } from './engine.mjs';
import { cardById } from './cards.mjs';
import { playTurn } from './ai.mjs';

const SEEDS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
const MAX_STEPS = 1500;

function checkInvariants(e, ctx) {
  const cells = new Set();
  for (const u of e.units.values()) {
    const k = `${u.x},${u.y}`;
    assert.ok(!cells.has(k), `${ctx} : deux unités en ${k}`);
    cells.add(k);
    assert.ok(u.x >= 0 && u.x < COLS && u.y >= 0 && u.y < ROWS, `${ctx} : unité hors plateau`);
    assert.ok(u.hp >= 1 && u.hp <= u.hpMax, `${ctx} : PV hors bornes ${u.name} ${u.hp}/${u.hpMax}`);
    assert.ok(!e.isTowerCell(u.x, u.y), `${ctx} : unité sur une tour`);
    assert.notStrictEqual(e.cell(u.x, u.y).terrain, TERRAIN.ROCHER, `${ctx} : unité sur un rocher`);
    assert.ok(u.movLeft >= 0, `${ctx} : déplacement négatif`);
    assert.ok(u.equips.length <= RULES.MAX_EQUIPS, `${ctx} : trop d'équipements`);
    assert.strictEqual(u.hpMax, cardById(u.cardId).hp + u.equips.reduce((s, id) => s + cardById(id).mods.hp, 0));
  }
  for (const [i, p] of e.players.entries()) {
    assert.ok(p.mana >= 0 && p.mana <= RULES.MAX_MANA, `${ctx} : mana J${i + 1} hors bornes (${p.mana})`);
    assert.ok(p.manaMax >= 0 && p.manaMax <= RULES.MAX_MANA, `${ctx} : manaMax hors bornes`);
    assert.ok(p.hand.length <= RULES.HAND_MAX, `${ctx} : main > ${RULES.HAND_MAX}`);
    for (const id of p.hand) assert.ok(cardById(id), `${ctx} : carte inconnue en main`);
  }
  for (const t of e.towers) assert.ok(t.hp >= 0 && t.hp <= RULES.TOWER_HP, `${ctx} : PV de tour hors bornes`);
  for (const row of e.board) {
    for (const c of row) {
      assert.ok(c.ttl >= 0, `${ctx} : ttl négatif`);
      if (c.ttl === 0) assert.strictEqual(c.terrain, c.base, `${ctx} : terrain temporaire sans ttl`);
    }
  }
  if (e.over) assert.ok(e.winner === 0 || e.winner === 1, `${ctx} : partie finie sans vainqueur`);
  else assert.strictEqual(e.winner, null);
}

/** Cartes VISIBLES d'un camp : deck + main + unités non-jeton en jeu + équipements portés. */
function visibleCards(e, owner) {
  const p = e.players[owner];
  const onBoard = e.unitsOf(owner).filter((u) => !u.token).length;
  const equipped = e.unitsOf(owner).reduce((s, u) => s + u.equips.length, 0);
  return p.deck.length + p.hand.length + onBoard + equipped;
}

test('propriété : toute action légale est acceptée et préserve les invariants (12 seeds)', () => {
  for (const seed of SEEDS) {
    const e = new Engine({ seed });
    const rng = makeRng(seed * 7919 + 1);
    let steps = 0;
    while (!e.over && steps < MAX_STEPS) {
      const actions = e.legalActions();
      assert.ok(actions.length >= 1 && actions[actions.length - 1].type === 'end');
      const action = actions[Math.floor(rng() * actions.length)];
      const res = e.apply(action);
      assert.ok(res.ok, `seed ${seed} : action légale refusée ${JSON.stringify(action)} — ${res.error}`);
      checkInvariants(e, `seed ${seed} pas ${steps} ${JSON.stringify(action)}`);
      steps++;
    }
    assert.ok(e.over, `seed ${seed} : la partie aléatoire doit se terminer en ${MAX_STEPS} actions`);
    assert.deepStrictEqual(e.legalActions(), []);
  }
});

test('propriété : conservation des cartes — aucune carte n\'apparaît, les visibles ne font que décroître', () => {
  // Une carte ne quitte le jeu que consommée (sort lancé, unité morte, carte brûlée, équipement
  // perdu main pleine) : deck + main + plateau + équipements est donc <= 30 et non croissant.
  for (const seed of SEEDS.slice(0, 6)) {
    const e = new Engine({ seed });
    const rng = makeRng(seed * 31 + 7);
    let previous = [visibleCards(e, 0), visibleCards(e, 1)];
    assert.deepStrictEqual(previous, [30, 30]);
    let steps = 0;
    while (!e.over && steps < 600) {
      const actions = e.legalActions();
      const action = actions[Math.floor(rng() * actions.length)];
      e.apply(action);
      const now = [visibleCards(e, 0), visibleCards(e, 1)];
      for (const owner of [0, 1]) {
        assert.ok(now[owner] <= previous[owner],
          `seed ${seed} pas ${steps} J${owner + 1} : ${previous[owner]} -> ${now[owner]} cartes visibles (${JSON.stringify(action)})`);
      }
      previous = now;
      steps++;
    }
  }
});

test('propriété : déterminisme — même seed, mêmes actions => même empreinte à chaque pas', () => {
  for (const seed of [21, 22, 23]) {
    const a = new Engine({ seed });
    const b = new Engine({ seed });
    const rng = makeRng(seed);
    for (let i = 0; i < 400 && !a.over; i++) {
      const la = a.legalActions();
      assert.deepStrictEqual(b.legalActions(), la);
      const action = la[Math.floor(rng() * la.length)];
      a.apply(action);
      b.apply(action);
      assert.strictEqual(a.hashState(), b.hashState(), `seed ${seed} pas ${i} : divergence`);
    }
  }
});

test('propriété : init() remet exactement l\'état initial (rejouer = même partie)', () => {
  for (const seed of [1, 2, 3]) {
    const e = new Engine({ seed });
    const h0 = e.hashState();
    playTurn(e, 0);
    playTurn(e, 1);
    assert.notStrictEqual(e.hashState(), h0);
    e.init();
    assert.strictEqual(e.hashState(), h0);
  }
});

test('propriété : bot contre bot — la partie se termine toujours, avec un vainqueur, en moins de 120 demi-tours', () => {
  const lengths = [];
  for (const seed of SEEDS) {
    const e = new Engine({ seed });
    let plies = 0;
    while (!e.over && plies < 120) {
      playTurn(e, e.current);
      checkInvariants(e, `bot seed ${seed} ply ${plies}`);
      plies++;
    }
    assert.ok(e.over, `seed ${seed} : impasse bot contre bot`);
    lengths.push(plies);
  }
  assert.ok(Math.max(...lengths) <= 120);
});

test('propriété : le plancher de dégâts garantit qu\'un combat au contact progresse toujours', () => {
  // deux golems (ATQ 2) en forêt face à face (armure 1) : chaque coup retire >= 1 PV
  const e = new Engine({ seed: 3 });
  e.units.clear();
  const a = e.spawn('golem', 0, 1, 6);
  a.summonedPly = 0;
  const b = e.spawn('golem', 1, 1, 5);
  b.summonedPly = 0;
  let rounds = 0;
  while (e.units.has(a.id) && e.units.has(b.id) && rounds < 40) {
    const attacker = e.current === 0 ? a : b;
    const defender = e.current === 0 ? b : a;
    const before = defender.hp + attacker.hp;
    e.apply({ type: 'attack', unit: attacker.id, target: { unit: defender.id } });
    assert.ok(defender.hp + attacker.hp < before, 'un échange doit toujours faire avancer l\'état');
    e.apply({ type: 'end' });
    rounds++;
  }
  assert.ok(!(e.units.has(a.id) && e.units.has(b.id)), 'le duel se résout');
});
